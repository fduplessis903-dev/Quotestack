import SwiftUI

/// Everything that can move on the critter for one animation frame.
struct MascotPose {
    var bodyLift: CGFloat = 0   // grid units upwards
    var legPhase = 0            // 0 = standing, 1 / 2 = alternating steps
    var tuckLegs = false
    var leftArm: Double = 0     // degrees raised: 0 = straight out, 90 = straight up
    var rightArm: Double = 0
    var eyeOpen: CGFloat = 1    // 0 = closed ... 1 = open
    var eyeShift: CGFloat = 0   // grid units, looking left (-) / right (+)
    var tilt: Double = 0        // degrees of lean
    var sleepyZ: CGFloat? = nil // 0...1 phase of the floating "z" while asleep

    static func blink(_ t: TimeInterval) -> CGFloat {
        t.truncatingRemainder(dividingBy: 3.7) < 0.13 ? 0 : 1
    }

    static func idle(_ t: TimeInterval) -> MascotPose {
        var p = MascotPose()
        p.eyeOpen = blink(t)
        return p
    }

    static func waving(_ t: TimeInterval) -> MascotPose {
        var p = idle(t)
        p.rightArm = 70 + 25 * sin(t * 12)
        return p
    }

    static func alarmed(_ t: TimeInterval) -> MascotPose {
        var p = idle(t)
        p.leftArm = 80 + 10 * sin(t * 20)
        p.rightArm = 80 - 10 * sin(t * 20)
        p.bodyLift = CGFloat(abs(sin(t * 9))) * 1.2
        return p
    }
}

/// The pixel-art Claude critter, drawn on a 16 × 10 grid with 4 rows of headroom
/// above it for jumps and floating z's.
struct MascotFigure: View {
    var pose: MascotPose
    var color: Color = .claude

    static let gridWidth: CGFloat = 16
    static let gridHeight: CGFloat = 14

    var body: some View {
        Canvas { ctx, size in
            let u = min(size.width / Self.gridWidth, size.height / Self.gridHeight)
            let origin = CGPoint(x: (size.width - u * Self.gridWidth) / 2, y: size.height - u * 10)
            Self.draw(pose, in: ctx, unit: u, origin: origin, color: color)
        }
    }

    static func draw(_ p: MascotPose, in ctx: GraphicsContext, unit u: CGFloat, origin: CGPoint, color: Color) {
        let fill = GraphicsContext.Shading.color(color)
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
            Path(CGRect(x: x * u, y: y * u, width: w * u, height: h * u))
        }

        var c = ctx
        c.translateBy(x: origin.x, y: origin.y - p.bodyLift * u)
        // Lean around the point between the feet.
        c.translateBy(x: 8 * u, y: 10 * u)
        c.rotate(by: .degrees(p.tilt))
        c.translateBy(x: -8 * u, y: -10 * u)

        // Legs (a stepping leg gets shorter, so it looks lifted).
        let legs: [CGFloat] = [3, 5, 10, 12]
        for (i, legX) in legs.enumerated() {
            var height: CGFloat = p.tuckLegs ? 1 : 2
            if p.legPhase != 0 && (i % 2 == 0) == (p.legPhase == 1) { height -= 0.7 }
            c.fill(box(legX, 8, 1, height), with: fill)
        }

        // Body.
        c.fill(box(2, 0, 12, 8), with: fill)

        // Arms pivot at their own centre just outside the body, so raising swings them up
        // beside the body. They stretch when raised so a wave pokes above the head.
        let arms: [(pivotX: CGFloat, raise: Double, side: Double)] = [(1, p.leftArm, -1), (15, p.rightArm, 1)]
        for arm in arms {
            let length = 2 + 4.5 * CGFloat(max(0, min(arm.raise, 90)) / 90)
            var a = c
            a.translateBy(x: arm.pivotX * u, y: 5 * u)
            a.rotate(by: .degrees(-arm.raise * arm.side))
            a.fill(box(arm.side < 0 ? -(length - 1) : -1, -1, length, 2), with: fill)
        }

        // Eyes.
        let eyeHeight = max(0.3, 2 * p.eyeOpen)
        let eyeY = 2 + (2 - eyeHeight) / 2
        let shift = max(-1, min(1, p.eyeShift))
        for eyeX in [CGFloat(4), 11] {
            c.fill(box(eyeX + shift, eyeY, 1, eyeHeight), with: .color(Color(white: 0.1)))
        }

        // Sleepy z's drifting up.
        if let phase = p.sleepyZ {
            var z = c
            z.opacity = Double(1 - phase)
            z.draw(Text("z").font(.system(size: 3 * u, weight: .heavy, design: .rounded)).foregroundColor(.white),
                   at: CGPoint(x: (14.5 + phase) * u, y: (-0.5 - 3 * phase) * u))
        }
    }
}

/// Decides what the critter at the top of the sidebar is up to. Lives on the
/// SidebarController so it keeps its place when the sidebar closes and reopens.
final class MascotBrain {
    enum Action { case idle, walk, jump, wave, dance, look, sleep }

    /// 0 = far left of the stage, 1 = far right.
    private(set) var x: CGFloat = 0.5
    private var direction: CGFloat = 1
    private var action: Action = .idle
    private var start: TimeInterval?
    private var duration: TimeInterval = 2
    private var queue: [Action] = []
    private var lastTime: TimeInterval?

    /// Task finished: wave, jump for joy, then dance.
    func celebrate() {
        queue = [.wave, .jump, .dance]
        start = nil
    }

    /// Clicked, or Claude needs attention.
    func poke() {
        queue = [.jump, .look]
        start = nil
    }

    func pose(at t: TimeInterval) -> MascotPose {
        let dt = min(max(t - (lastTime ?? t), 0), 0.1)
        lastTime = t
        if start.map({ t - $0 > duration }) ?? true { next(t) }
        let e = t - (start ?? t)

        var p = MascotPose.idle(t)
        switch action {
        case .idle:
            break
        case .walk:
            x += direction * 0.16 * CGFloat(dt)
            if x >= 1 { x = 1; direction = -1 } else if x <= 0 { x = 0; direction = 1 }
            p.legPhase = Int(e * 6) % 2 + 1
            p.bodyLift = p.legPhase == 1 ? 0.3 : 0
            p.eyeShift = direction * 0.6
            p.leftArm = 12 * sin(e * 12)
            p.rightArm = -12 * sin(e * 12)
        case .jump:
            let hop = (e / 0.7).truncatingRemainder(dividingBy: 1)
            p.bodyLift = CGFloat(3.2 * sin(.pi * hop))
            p.tuckLegs = p.bodyLift > 0.8
            p.leftArm = 55
            p.rightArm = 55
        case .wave:
            p.rightArm = 70 + 25 * sin(e * 12)
        case .dance:
            let s = sin(e * 9)
            p.leftArm = 45 + 40 * s
            p.rightArm = 45 - 40 * s
            p.tilt = 8 * s
            p.bodyLift = CGFloat(abs(s)) * 0.6
            p.legPhase = s > 0 ? 1 : 2
        case .look:
            p.eyeShift = CGFloat(sin(e * 2.2))
        case .sleep:
            p.eyeOpen = 0
            p.sleepyZ = CGFloat((e / 1.6).truncatingRemainder(dividingBy: 1))
        }
        return p
    }

    private func next(_ t: TimeInterval) {
        start = t
        action = queue.isEmpty ? Self.randomAction() : queue.removeFirst()
        switch action {
        case .idle: duration = .random(in: 1.5...3)
        case .walk: duration = .random(in: 2.5...5)
        case .jump: duration = 1.4
        case .wave: duration = 2.2
        case .dance: duration = 2.8
        case .look: duration = 2.5
        case .sleep: duration = 5
        }
    }

    private static func randomAction() -> Action {
        let bag: [Action] = [.walk, .walk, .walk, .idle, .idle, .jump, .wave, .dance, .look, .sleep]
        return bag.randomElement() ?? .idle
    }
}

/// The strip at the top of the open sidebar where the critter roams. Click him to make him jump.
struct MascotStage: View {
    @EnvironmentObject var sidebar: SidebarController

    private let size = CGSize(width: 64, height: 56)

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { timeline in
                let pose = sidebar.mascot.pose(at: timeline.date.timeIntervalSinceReferenceDate)
                MascotFigure(pose: pose)
                    .frame(width: size.width, height: size.height)
                    .shadow(color: Color.claude.opacity(0.55), radius: 6)
                    .offset(x: sidebar.mascot.x * max(0, geo.size.width - size.width))
            }
        }
        .frame(height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { sidebar.mascot.poke() }
        .help("Poke me!")
    }
}

/// Small looping critter for the notification card and the collapsed tab.
struct MiniMascot: View {
    enum Mood { case idle, waving, alarmed }
    var mood: Mood

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            switch mood {
            case .idle: MascotFigure(pose: .idle(t))
            case .waving: MascotFigure(pose: .waving(t))
            case .alarmed: MascotFigure(pose: .alarmed(t))
            }
        }
    }
}
