import AppKit
import ApplicationServices
import Foundation

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = AppServerClient()
    private let tracker = ChatGPTWindowTracker()
    private let overlay = OverlayController()
    private var workspaceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)

        client.onSnapshot = { [weak self] snapshot in
            self?.overlay.update(snapshot: snapshot)
        }
        client.onError = { [weak self] message in
            self?.overlay.update(error: message)
        }
        tracker.onPlacementChange = { [weak self] frame in
            self?.overlay.updatePlacement(frame)
        }
        NotificationCenter.default.addObserver(
            forName: .codexUsageOverlayRefreshRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.client.refreshNow()
        }

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  application.bundleIdentifier == "com.openai.codex"
                    || application.bundleIdentifier == "com.openai.chatgpt"
            else { return }
            self?.client.refreshNow()
        }

        client.start()
        tracker.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        tracker.stop()
        client.stop()
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
