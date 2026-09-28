import AppKit
import SwiftUI

extension Color {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
}

enum Fmt {
    static func money(_ v: Double) -> String {
        v >= 100 ? String(format: "$%.0f", v) : String(format: "$%.2f", v)
    }

    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1e9 { return String(format: "%.1fB", d / 1e9) }
        if d >= 1e6 { return String(format: "%.1fM", d / 1e6) }
        if d >= 1e3 { return String(format: "%.0fK", d / 1e3) }
        return "\(n)"
    }

    static func duration(_ t: TimeInterval) -> String {
        let m = max(0, Int(t / 60))
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func ago(_ d: Date) -> String {
        Date().timeIntervalSince(d) < 60 ? "now" : relative.localizedString(for: d, relativeTo: Date())
    }
}

extension AgentEvent.Kind {
    var icon: String {
        switch self {
        case .done: return "checkmark.circle.fill"
        case .needsInput: return "exclamationmark.bubble.fill"
        }
    }

    var color: Color {
        switch self {
        case .done: return .green
        case .needsInput: return .orange
        }
    }
}

func modelColor(_ name: String) -> Color {
    let n = name.lowercased()
    if n.contains("opus") { return .claude }
    if n.contains("sonnet") { return .blue }
    if n.contains("haiku") { return .green }
    return .gray
}

// MARK: - Building blocks

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Frosted background rounded only on the side facing away from the screen edge
/// (the other side is pushed past the window bounds and clipped).
struct PanelBackground: ViewModifier {
    let side: Side

    func body(content: Content) -> some View {
        content.background(
            VisualEffect()
                .overlay(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1)))
                .padding(side == .right ? .trailing : .leading, -24)
        )
    }
}

struct Ring: View {
    var fraction: Double
    var lineWidth: CGFloat

    private var color: Color { fraction > 0.9 ? .red : fraction > 0.7 ? .orange : .claude }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.6)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Root

struct SidebarRootView: View {
    @EnvironmentObject var sidebar: SidebarController

    var body: some View {
        Group {
            if sidebar.expanded { ExpandedView() } else { CollapsedTab() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { sidebar.hover($0) }
    }
}

struct CollapsedTab: View {
    @EnvironmentObject var sidebar: SidebarController
    @EnvironmentObject var usage: UsageStore
    @EnvironmentObject var plan: PlanUsageStore

    /// Real plan % when we have it, otherwise the estimate from local Claude Code logs.
    private var fraction: Double {
        if let session = plan.session { return min(session.percent / 100, 1) }
        return usage.sessionFraction
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Ring(fraction: fraction, lineWidth: 3).frame(width: 18, height: 18)
                if sidebar.unread > 0 {
                    Circle().fill(Color.green).frame(width: 7, height: 7).offset(x: 3, y: -3)
                }
            }
            Text("\(Int(fraction * 100))%")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
            Image(systemName: sidebar.side == .right ? "chevron.left" : "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(PanelBackground(side: sidebar.side))
        .contentShape(Rectangle())
        .onTapGesture { sidebar.toggle() }
        .help("Claude usage — click to open")
    }
}

struct ExpandedView: View {
    @EnvironmentObject var sidebar: SidebarController
    @EnvironmentObject var usage: UsageStore
    @EnvironmentObject var plan: PlanUsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Header()
            if let toast = sidebar.toast {
                ToastCard(event: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    PlanCard()
                    if usage.summary.foundLogs {
                        if plan.limits.isEmpty { SessionCard() }
                        TodayCard()
                        WeekCard()
                    }
                    ActivityCard()
                    if usage.summary.foundLogs {
                        Text("Dollar figures are API-equivalent estimates from your Claude Code logs, not your bill.")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(PanelBackground(side: sidebar.side))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: sidebar.toast?.id)
    }
}

struct Header: View {
    @EnvironmentObject var sidebar: SidebarController

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle").foregroundColor(.claude)
            Text("Claude").font(.system(size: 14, weight: .semibold))
            Spacer()
            Menu { SettingsMenu() } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            Button { sidebar.toggle() } label: {
                Image(systemName: sidebar.side == .right ? "chevron.right" : "chevron.left")
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

struct SettingsMenu: View {
    @EnvironmentObject var sidebar: SidebarController
    @EnvironmentObject var usage: UsageStore
    @EnvironmentObject var plan: PlanUsageStore

    var body: some View {
        Picker("100% session mark", selection: $usage.sessionLimit) {
            Text("Auto (your busiest session)").tag(0.0)
            ForEach([5.0, 10, 20, 35, 50, 100, 150, 250], id: \.self) { v in
                Text("\(Fmt.money(v)) per 5h").tag(v)
            }
        }
        Picker("Dock to", selection: $sidebar.side) {
            Text("Right edge").tag(Side.right)
            Text("Left edge").tag(Side.left)
        }
        Toggle("Play sound", isOn: $sidebar.playSound)
        Toggle("Also send macOS notifications", isOn: $sidebar.systemNotifications)
        Toggle("Launch at login", isOn: Binding(get: { LoginItem.enabled }, set: { LoginItem.set($0) }))
        Divider()
        Button("Refresh usage") {
            usage.refresh()
            plan.refresh()
        }
        Button("Show test notification") { sidebar.present(.test) }
        Divider()
        Button("Quit Claude Sidebar") { NSApp.terminate(nil) }
    }
}

// MARK: - Cards

struct ToastCard: View {
    let event: AgentEvent
    @EnvironmentObject var sidebar: SidebarController

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.kind.icon)
                .font(.system(size: 20))
                .foregroundColor(event.kind.color)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(event.title) · \(event.project)")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(event.detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(event.kind.color.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(event.kind.color.opacity(0.5)))
        .contentShape(Rectangle())
        .onTapGesture { sidebar.dismissToast() }
    }
}

/// The same bars as Claude's Settings → Usage page.
struct PlanCard: View {
    @EnvironmentObject var plan: PlanUsageStore

    var body: some View {
        Card(title: "Plan usage") {
            if plan.limits.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(plan.limits) { LimitRow(limit: $0) }
                if plan.status != .ok {
                    Text(message)
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var message: String {
        switch plan.status {
        case .loading, .ok:
            return "Loading…"
        case .needsLogin:
            return "Sign in to Claude Code once (type claude in Terminal) so the sidebar can read your plan usage."
        case .expired:
            return "Your Claude Code sign-in needs refreshing: open Claude Code once (type claude in Terminal)."
        case .failed(let reason):
            return "Couldn't reach Anthropic (\(reason)). Will retry."
        }
    }
}

struct LimitRow: View {
    let limit: PlanLimit

    private static let resetFormat: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE j:mm")
        return f
    }()

    private var fraction: Double { min(max(limit.percent / 100, 0), 1) }
    private var color: Color { fraction > 0.9 ? .red : fraction > 0.7 ? .orange : .claude }

    private var resetText: String? {
        guard let date = limit.resetsAt else { return nil }
        let left = date.timeIntervalSinceNow
        if left <= 0 { return "Resetting…" }
        return left < 86_400 ? "Resets in \(Fmt.duration(left))" : "Resets \(Self.resetFormat.string(from: date))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(limit.label).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(limit.percent.rounded()))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(color).frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.4), value: fraction)
            if let resetText {
                Text(resetText).font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }
}

struct SessionCard: View {
    @EnvironmentObject var usage: UsageStore

    var body: some View {
        let s = usage.summary
        Card(title: "Current 5-hour session") {
            HStack(spacing: 14) {
                ZStack {
                    Ring(fraction: usage.sessionFraction, lineWidth: 7)
                    VStack(spacing: 0) {
                        Text("\(Int(usage.sessionFraction * 100))%")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("used").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    if s.sessionActive, let end = s.sessionEnd {
                        Text(Fmt.money(s.sessionCost))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text("of ~\(Fmt.money(usage.effectiveLimit)) · \(Fmt.tokens(s.sessionTokens)) tok")
                            .font(.caption).foregroundColor(.secondary)
                        Label("Resets in \(Fmt.duration(end.timeIntervalSinceNow))", systemImage: "clock")
                            .font(.caption)
                        Label("\(Fmt.money(s.sessionBurnPerHour))/hr", systemImage: "flame")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("No active session").font(.system(size: 13, weight: .semibold))
                        Text(s.foundLogs
                             ? "Starts with your next Claude Code message."
                             : "No Claude Code logs found in ~/.claude yet.")
                            .font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct TodayCard: View {
    @EnvironmentObject var usage: UsageStore

    var body: some View {
        let s = usage.summary
        Card(title: "Today") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.money(s.todayCost)).font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("\(Fmt.tokens(s.todayTokens)) tokens").font(.caption).foregroundColor(.secondary)
            }
            ForEach(s.todayModels.prefix(4)) { m in
                HStack(spacing: 6) {
                    Circle().fill(modelColor(m.model)).frame(width: 6, height: 6)
                    Text(m.model).font(.caption)
                    Spacer()
                    Text(Fmt.money(m.cost)).font(.caption.monospacedDigit()).foregroundColor(.secondary)
                }
            }
        }
    }
}

struct WeekCard: View {
    @EnvironmentObject var usage: UsageStore

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }()

    var body: some View {
        let week = usage.summary.week
        let maxCost = max(week.map(\.cost).max() ?? 0, 0.01)
        Card(title: "Last 7 days") {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(week) { d in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Calendar.current.isDateInToday(d.day) ? Color.claude : Color.white.opacity(0.25))
                            .frame(height: max(3, CGFloat(d.cost / maxCost) * 54))
                        Text(Self.weekday.string(from: d.day))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(Fmt.money(d.cost)) · \(Fmt.tokens(d.tokens)) tokens")
                }
            }
            .frame(height: 72, alignment: .bottom)
            Text("Week total \(Fmt.money(week.reduce(0.0) { $0 + $1.cost }))")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}

struct ActivityCard: View {
    @EnvironmentObject var sidebar: SidebarController

    var body: some View {
        Card(title: "Recent activity") {
            if sidebar.events.isEmpty {
                Text("When Claude Code finishes a task or needs your input, it pops out here.")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(sidebar.events.prefix(8)) { EventRow(event: $0) }
                Button("Clear") { sidebar.events.removeAll() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct EventRow: View {
    let event: AgentEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: event.kind.icon)
                .font(.system(size: 12))
                .foregroundColor(event.kind.color)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.project).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(Fmt.ago(event.date)).font(.system(size: 9)).foregroundColor(.secondary)
                }
                Text(event.detail).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2)
            }
        }
    }
}
