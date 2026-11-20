import AppKit
import QuartzCore

/// The Mac's quick launcher: an X that floats above every window, like a fidget spinner. Each arm
/// ends in a round button for one tab (Alarms, Timers, To-Do, Notes); the hub in the middle spins
/// it. Drag anywhere to move it (the spot is remembered).
final class QuickLauncher {
    private var panel: NSPanel?
    private let open: (URL) -> Void

    init(open: @escaping (URL) -> Void) { self.open = open }

    var isShown: Bool { panel != nil }

    func show() {
        guard panel == nil else { return }
        let size = LauncherView.size
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating                  // above ordinary windows, in every app
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                  // the view draws its own soft shadow
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = LauncherView(frame: NSRect(x: 0, y: 0, width: size, height: size), open: open)
        panel.setFrameAutosaveName("AlarmieQuickLauncher")
        if !panel.setFrameUsingName("AlarmieQuickLauncher"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size - 40, y: screen.maxY - size - 40))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class LauncherView: NSView {
    static let size: CGFloat = 150
    private static let lobeRadius: CGFloat = 22
    private static let hubRadius: CGFloat = 20

    /// The four arms, from the top left going clockwise.
    private static let arms: [(symbol: String, label: String, url: String)] = [
        ("alarm.fill", "Alarms", "alarmapp://alarms"),
        ("timer", "Timers", "alarmapp://timers"),
        ("note.text", "Notes", "alarmapp://notes"),
        ("checklist", "To-Do", "alarmapp://todos"),
    ]

    private let open: (URL) -> Void
    private let spinner = CALayer()
    private var mouseDownPoint: NSPoint?
    private var dragged = false

    init(frame: NSRect, open: @escaping (URL) -> Void) {
        self.open = open
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        buildLayers()
        toolTip = "Alarmie: click an arm to open a tab, drag to move"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Arm centers, at the corners of the X.
    private func lobeCenter(_ index: Int) -> CGPoint {
        let c = Self.size / 2, d = Self.size / 2 - Self.lobeRadius - 6
        let (dx, dy): (CGFloat, CGFloat) = [(-1, -1), (1, -1), (1, 1), (-1, 1)][index]
        let k = d / sqrt(2) * 1.25
        return CGPoint(x: c + dx * k, y: c + dy * k)
    }

    private func buildLayers() {
        spinner.frame = bounds
        spinner.shadowColor = NSColor.black.cgColor
        spinner.shadowOpacity = 0.25
        spinner.shadowRadius = 6
        spinner.shadowOffset = CGSize(width: 0, height: -2)
        layer?.addSublayer(spinner)

        let orange = NSColor.systemOrange.cgColor
        // The two bars of the X.
        let center = CGPoint(x: Self.size / 2, y: Self.size / 2)
        for pair in [(0, 2), (1, 3)] {
            let bar = CAShapeLayer()
            let path = CGMutablePath()
            path.move(to: lobeCenter(pair.0))
            path.addLine(to: lobeCenter(pair.1))
            bar.path = path
            bar.strokeColor = NSColor.systemOrange.withAlphaComponent(0.85).cgColor
            bar.lineWidth = 16
            bar.lineCap = .round
            spinner.addSublayer(bar)
        }
        // The arm ends: a round button with the tab's symbol.
        for (index, arm) in Self.arms.enumerated() {
            let lobe = CAShapeLayer()
            let p = lobeCenter(index), r = Self.lobeRadius
            lobe.path = CGPath(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r), transform: nil)
            lobe.fillColor = orange
            lobe.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
            lobe.lineWidth = 2
            spinner.addSublayer(lobe)

            let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let image = NSImage(systemSymbolName: arm.symbol, accessibilityDescription: arm.label)?.withSymbolConfiguration(config) {
                let icon = CALayer()
                let side: CGFloat = 22
                icon.frame = CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side)
                icon.contents = image
                icon.contentsGravity = .resizeAspect
                spinner.addSublayer(icon)
            }
        }
        // The hub.
        let hub = CAShapeLayer()
        let r = Self.hubRadius
        hub.path = CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r), transform: nil)
        hub.fillColor = NSColor(white: 0.12, alpha: 0.95).cgColor
        hub.strokeColor = orange
        hub.lineWidth = 3
        spinner.addSublayer(hub)
        let dot = CAShapeLayer()
        dot.path = CGPath(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10), transform: nil)
        dot.fillColor = orange
        spinner.addSublayer(dot)
    }

    // MARK: Clicks and dragging

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragged, let start = mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - start.x, point.y - start.y) > 3 {
            dragged = true
            window?.performDrag(with: event) // the window follows the mouse until it's released
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard !dragged else { return }
        let point = convert(event.locationInWindow, from: nil)
        let center = CGPoint(x: Self.size / 2, y: Self.size / 2)
        if hypot(point.x - center.x, point.y - center.y) <= Self.hubRadius + 4 {
            spin()
            return
        }
        for (index, arm) in Self.arms.enumerated() {
            let p = lobeCenter(index)
            if hypot(point.x - p.x, point.y - p.y) <= Self.lobeRadius + 6, let url = URL(string: arm.url) {
                pulse()
                open(url)
                return
            }
        }
    }

    /// A full turn that slows to a stop, like a flicked fidget spinner.
    private func spin() {
        spinner.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        spinner.position = CGPoint(x: bounds.midX, y: bounds.midY)
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = CGFloat.pi * 4
        turn.duration = 1.4
        turn.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0.85, 0.3, 1)
        spinner.add(turn, forKey: "spin")
    }

    /// A small bounce when a tab opens.
    private func pulse() {
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1, 0.92, 1.04, 1]
        bounce.duration = 0.25
        spinner.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        spinner.position = CGPoint(x: bounds.midX, y: bounds.midY)
        spinner.add(bounce, forKey: "pulse")
    }
}
