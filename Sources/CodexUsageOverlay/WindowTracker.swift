import AppKit
import ApplicationServices

final class ChatGPTWindowTracker {
    var onPlacementChange: ((CGRect?) -> Void)?

    private var accessibilityObserver: AXObserver?
    private var observedWindowElements: [AXUIElement] = []
    private var workspaceObserverTokens: [NSObjectProtocol] = []
    private var observedProcessID: pid_t?
    private var lastAccessibilityLookup = Date.distantPast
    private var cachedProfileFrame: CGRect?
    private var lastPublishedFrame: CGRect?
    private var hasPublishedPlacement = false

    func start() {
        stop()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceNotifications: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        workspaceObserverTokens = workspaceNotifications.map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                let isCodexLifecycleEvent = name == NSWorkspace.didLaunchApplicationNotification
                    || name == NSWorkspace.didTerminateApplicationNotification
                guard !isCodexLifecycleEvent
                    || Self.isCodexApplication(application?.bundleIdentifier)
                else { return }
                self?.handleWorkspaceChange(forceRebind: isCodexLifecycleEvent)
            }
        }
        handleWorkspaceChange(forceRebind: true)
    }

    func stop() {
        for token in workspaceObserverTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObserverTokens.removeAll()
        detachAccessibilityObserver()
        lastPublishedFrame = nil
        hasPublishedPlacement = false
    }

    private func handleWorkspaceChange(forceRebind: Bool = false) {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              Self.isCodexApplication(frontmost.bundleIdentifier)
        else {
            detachAccessibilityObserver()
            publishPlacement(nil)
            return
        }

        if forceRebind
            || observedProcessID != frontmost.processIdentifier
            || accessibilityObserver == nil {
            attachAccessibilityObserver(to: frontmost.processIdentifier)
        }
        refreshPlacement(forceProfileLookup: true)
    }

    private func handleAccessibilityEvent(_ notification: CFString) {
        // Accessibility sends this callback only when the observed app/window
        // changes. Re-read the anchor while it is moving, but do not poll when
        // the window is idle.
        let notificationName = notification as String
        if notificationName == kAXWindowCreatedNotification
            || notificationName == kAXUIElementDestroyedNotification
            || accessibilityObserver == nil {
            handleWorkspaceChange(forceRebind: true)
            return
        }
        refreshPlacement(forceProfileLookup: true)
    }

    private func attachAccessibilityObserver(to processID: pid_t) {
        detachAccessibilityObserver()
        observedProcessID = processID

        guard AXIsProcessTrusted() else { return }
        let application = AXUIElementCreateApplication(processID)
        var observer: AXObserver?
        guard AXObserverCreate(processID, Self.accessibilityCallback, &observer) == .success,
              let observer
        else { return }

        accessibilityObserver = observer
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let appNotifications = [
            kAXFocusedWindowChangedNotification,
            kAXWindowCreatedNotification,
            kAXUIElementDestroyedNotification
        ]
        for notification in appNotifications {
            AXObserverAddNotification(observer, application, notification as CFString, refcon)
        }

        if let windows = copyElementArrayAttribute(application, kAXWindowsAttribute) {
            for window in windows {
                observeWindow(window, with: observer, refcon: refcon)
            }
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    private func observeWindow(_ window: AXUIElement, with observer: AXObserver, refcon: UnsafeMutableRawPointer) {
        let notifications = [
            kAXMovedNotification,
            kAXResizedNotification,
            kAXUIElementDestroyedNotification,
            kAXTitleChangedNotification
        ]
        for notification in notifications {
            AXObserverAddNotification(observer, window, notification as CFString, refcon)
        }
        observedWindowElements.append(window)
    }

    private func detachAccessibilityObserver() {
        guard let observer = accessibilityObserver else {
            observedProcessID = nil
            observedWindowElements.removeAll()
            return
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        accessibilityObserver = nil
        observedProcessID = nil
        observedWindowElements.removeAll()
        cachedProfileFrame = nil
        lastAccessibilityLookup = .distantPast
    }

    private static let accessibilityCallback: AXObserverCallback = { _, _, notification, refcon in
        guard let refcon else { return }
        let tracker = Unmanaged<ChatGPTWindowTracker>.fromOpaque(refcon).takeUnretainedValue()
        DispatchQueue.main.async {
            tracker.handleAccessibilityEvent(notification)
        }
    }

    private func refreshPlacement(forceProfileLookup: Bool) {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              Self.isCodexApplication(frontmost.bundleIdentifier),
              let windowFrame = frontmostWindowFrame(for: frontmost.processIdentifier)
        else {
            publishPlacement(nil)
            return
        }

        if forceProfileLookup || Date().timeIntervalSince(lastAccessibilityLookup) > 1.5 {
            lastAccessibilityLookup = Date()
            cachedProfileFrame = findProfileFrame(
                processID: frontmost.processIdentifier,
                inside: windowFrame
            )
        }

        let cardSize = OverlayController.cardSize
        let cardFrame: CGRect
        if let profileFrame = cachedProfileFrame,
           windowFrame.intersects(profileFrame) {
            let rightReservedSpace: CGFloat = 36
            let preferredX = profileFrame.maxX + 8
            let maximumX = windowFrame.maxX - cardSize.width - rightReservedSpace
            cardFrame = CGRect(
                x: min(max(windowFrame.minX + 8, preferredX), maximumX),
                y: profileFrame.midY - cardSize.height / 2,
                width: cardSize.width,
                height: cardSize.height
            )
        } else {
            // Fallback: keep the compact label on the username row area.
            cardFrame = CGRect(
                x: windowFrame.minX + 88,
                y: windowFrame.minY + 8,
                width: cardSize.width,
                height: cardSize.height
            )
        }
        publishPlacement(cardFrame)
    }

    private func publishPlacement(_ frame: CGRect?) {
        if let frame {
            if let previous = lastPublishedFrame,
               abs(previous.minX - frame.minX) < 0.5,
               abs(previous.minY - frame.minY) < 0.5,
               abs(previous.width - frame.width) < 0.5,
               abs(previous.height - frame.height) < 0.5 {
                return
            }
            lastPublishedFrame = frame
            hasPublishedPlacement = true
        } else {
            guard hasPublishedPlacement else { return }
            lastPublishedFrame = nil
            hasPublishedPlacement = false
        }
        onPlacementChange?(frame)
    }

    private static func isCodexApplication(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleID == "com.openai.codex" || bundleID == "com.openai.chatgpt"
    }

    private func frontmostWindowFrame(for processID: pid_t) -> CGRect? {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]
        else { return nil }

        for window in rawWindows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 500,
                  frame.height > 300
            else { continue }
            return convertFromQuartz(frame)
        }
        return nil
    }

    private func findProfileFrame(processID: pid_t, inside windowFrame: CGRect) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(processID)
        guard let focusedWindow = copyElementAttribute(application, kAXFocusedWindowAttribute) else {
            return nil
        }

        let configuredText = ProcessInfo.processInfo.environment["CODEX_USAGE_PROFILE_TEXT"]?.lowercased()
        let username = NSUserName().lowercased()
        let fullName = NSFullUserName().lowercased()
        let hints = [configuredText, username, fullName, "profile", "account", "avatar", "个人资料", "账户"]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        var queue: [AXUIElement] = [focusedWindow]
        var index = 0
        while index < queue.count, index < 1_500 {
            let element = queue[index]
            index += 1
            let role = copyStringAttribute(element, kAXRoleAttribute) ?? ""
            let searchable = [
                copyStringAttribute(element, kAXTitleAttribute),
                copyStringAttribute(element, kAXDescriptionAttribute),
                copyStringAttribute(element, kAXHelpAttribute),
                copyStringAttribute(element, kAXIdentifierAttribute),
                copyStringAttribute(element, kAXValueAttribute)
            ].compactMap { $0?.lowercased() }.joined(separator: " ")

            if [kAXButtonRole as String, kAXGroupRole as String, kAXStaticTextRole as String].contains(role),
               hints.contains(where: { searchable.contains($0) }),
               let frame = copyQuartzFrame(element).map(convertFromQuartz),
               frame.minY < windowFrame.minY + 180,
               frame.minX < windowFrame.minX + 520 {
                return frame
            }

            if let children = copyElementArrayAttribute(element, kAXChildrenAttribute) {
                queue.append(contentsOf: children)
            }
        }
        return nil
    }

    private func copyElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyElementArrayAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func copyQuartzFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func convertFromQuartz(_ frame: CGRect) -> CGRect {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        var displayID = CGMainDisplayID()
        var displayCount: UInt32 = 0
        if CGGetDisplaysWithPoint(center, 1, &displayID, &displayCount) != .success || displayCount == 0 {
            displayID = CGMainDisplayID()
        }
        let quartzDisplayFrame = CGDisplayBounds(displayID)
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else {
            let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
            return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        }
        return CGRect(
            x: screen.frame.minX + (frame.minX - quartzDisplayFrame.minX),
            y: screen.frame.maxY - (frame.maxY - quartzDisplayFrame.minY),
            width: frame.width,
            height: frame.height
        )
    }
}
