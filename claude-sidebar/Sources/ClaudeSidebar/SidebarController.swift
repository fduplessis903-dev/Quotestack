import AppKit
import SwiftUI

enum Side: String { case left, right }

final class SidebarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the always-on-top panel glued to the screen edge and its collapsed/expanded state.
final class SidebarController: ObservableObject {
    static let collapsedSize = NSSize(width: 30, height: 150)
    static let expandedSize = NSSize(width: 300, height: 650)

    let mascot = MascotBrain()

    @Published private(set) var expanded = false
    @Published private(set) var toast: AgentEvent?
    @Published var events: [AgentEvent] = []
    @Published private(set) var unread = 0

    @Published var side: Side {
        didSet { UserDefaults.standard.set(side.rawValue, forKey: "side"); layout(animated: false) }
    }
    @Published var playSound: Bool {
        didSet { UserDefaults.standard.set(playSound, forKey: "playSound") }
    }
    @Published var showMascot: Bool {
        didSet { UserDefaults.standard.set(showMascot, forKey: "showMascot") }
    }
    @Published var systemNotifications: Bool {
        didSet {
            UserDefaults.standard.set(systemNotifications, forKey: "systemNotifications")
            if systemNotifications { Notifier.requestAuthorization() }
        }
    }

    let usage: UsageStore
    let plan: PlanUsageStore
    private var panel: SidebarPanel!
    private var toastWork: DispatchWorkItem?
    private var openedByToast = false
    private var hovering = false

    init(usage: UsageStore, plan: PlanUsageStore) {
        self.usage = usage
        self.plan = plan
        let defaults = UserDefaults.standard
        side = Side(rawValue: defaults.string(forKey: "side") ?? "") ?? .right
        playSound = defaults.object(forKey: "playSound") as? Bool ?? true
        showMascot = defaults.object(forKey: "showMascot") as? Bool ?? true
        systemNotifications = defaults.object(forKey: "systemNotifications") as? Bool ?? false

        let panel = SidebarPanel(
            contentRect: NSRect(origin: .zero, size: Self.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let root = SidebarRootView()
            .environmentObject(self)
            .environmentObject(usage)
            .environmentObject(plan)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [] // we size the window ourselves
        panel.contentView = host
        self.panel = panel

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.layout(animated: false) }
    }

    func show() {
        layout(animated: false)
        panel.orderFrontRegardless()
    }

    /// User clicked the tab / chevron.
    func toggle() {
        openedByToast = false
        if !expanded {
            unread = 0
            plan.refresh()
        }
        setExpanded(!expanded)
    }

    func hover(_ inside: Bool) {
        hovering = inside
        // If the user moves onto a toast-opened sidebar, keep it open.
        if inside { openedByToast = false }
    }

    func present(_ event: AgentEvent) {
        events.insert(event, at: 0)
        if events.count > 30 { events.removeLast(events.count - 30) }
        if !expanded || openedByToast { unread += 1 }
        if playSound { NSSound(named: event.kind == .done ? "Glass" : "Ping")?.play() }
        if systemNotifications { Notifier.post(event) }
        if event.kind == .done { mascot.celebrate() } else { mascot.poke() }

        toast = event
        if !expanded {
            openedByToast = true
            setExpanded(true)
        }
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissToast() }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: work)
    }

    func dismissToast() {
        toastWork?.cancel()
        toast = nil
        if openedByToast && !hovering {
            openedByToast = false
            setExpanded(false)
        }
    }

    private func setExpanded(_ value: Bool) {
        guard value != expanded else { return }
        expanded = value
        layout(animated: true)
    }

    private func layout(animated: Bool) {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        var size = expanded ? Self.expandedSize : Self.collapsedSize
        size.height = min(size.height, visible.height - 40)
        let x = side == .right ? visible.maxX - size.width : visible.minX
        let frame = NSRect(x: x, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }
}
