import AppKit

final class OverlayCardView: NSView {
    private let valueLabel = NSTextField(labelWithString: "周额度读取中…")

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.96).cgColor
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.12).cgColor
        layer?.borderWidth = 1

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = NSColor.white.withAlphaComponent(0.82)
        valueLabel.alignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)
        NSLayoutConstraint.activate([
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        toolTip = "点击悬浮窗可刷新额度"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(snapshot: UsageSnapshot) {
        guard let weekly = snapshot.weekly else {
            valueLabel.stringValue = "周额度读取中…"
            valueLabel.textColor = NSColor.white.withAlphaComponent(0.62)
            return
        }
        valueLabel.stringValue = "周额度剩余 \(weekly.remainingPercent)%"
        valueLabel.textColor = weekly.remainingPercent <= 10
            ? .systemRed
            : (weekly.remainingPercent <= 30 ? .systemOrange : .systemGreen)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: .codexUsageOverlayRefreshRequested, object: nil)
    }
}

final class OverlayController {
    static let cardSize = CGSize(width: 112, height: 24)
    private let cardView = OverlayCardView(frame: NSRect(x: 0, y: 0, width: 112, height: 24))
    private let panel: NSPanel
    private var isPresented = false
    private var animationToken = 0

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 112, height: 24),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = cardView
    }

    func update(snapshot: UsageSnapshot) {
        cardView.update(snapshot: snapshot)
    }

    func updatePlacement(_ frame: CGRect?) {
        animationToken += 1
        let token = animationToken

        guard let frame else {
            guard isPresented else {
                panel.orderOut(nil)
                return
            }

            isPresented = false
            let hiddenFrame = panel.frame.offsetBy(dx: 0, dy: -8)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 0
                panel.animator().setFrame(hiddenFrame, display: true)
            } completionHandler: { [weak self] in
                guard let self, self.animationToken == token else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
            return
        }

        if !isPresented {
            isPresented = true
            panel.setFrame(frame.offsetBy(dx: 0, dy: -8), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    func update(error: String) {
        cardView.toolTip = "额度读取失败：\(error)"
    }

    func hide() { panel.orderOut(nil) }
}

extension Notification.Name {
    static let codexUsageOverlayRefreshRequested = Notification.Name("CodexUsageOverlay.refreshRequested")
}
