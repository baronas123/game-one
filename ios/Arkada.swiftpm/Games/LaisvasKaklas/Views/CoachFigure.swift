import SwiftUI
import SceneKit

extension LaisvasKaklas {

    /// SceneKit trenerio vaizdas. Pozą perduoda `CoachStage` kas kadrą.
    struct CoachFigure: UIViewRepresentable {
        let pose: CoachPose
        let ghost: CoachPose?
        let cameraAngle: Double
        var matched = false

        func makeCoordinator() -> CoachRig { CoachRig() }

        func makeUIView(context: Context) -> SCNView {
            let view = SCNView()
            view.scene = context.coordinator.scene
            view.pointOfView = context.coordinator.pointOfView
            view.backgroundColor = .clear
            view.antialiasingMode = .multisampling4X
            view.rendersContinuously = true
            view.preferredFramesPerSecond = 60
            view.isUserInteractionEnabled = false
            return view
        }

        func updateUIView(_ view: SCNView, context: Context) {
            context.coordinator.apply(pose, ghost: ghost, matched: matched, cameraAngle: cameraAngle)
        }
    }

    /// Ką rodyti rodyklėmis virš 3D figūros.
    struct MoveHint: Equatable {
        enum Mode: Equatable {
            /// Judėk link kontūro.
            case go
            /// Išlaikyk – žiedas pildosi.
            case hold
            /// Grįžk į centrą.
            case back
        }

        var axis: TrackedAxis
        /// Pusė anatomiškai (+1 – tavo dešinė / smakras žemyn); ekrane tai dešinė, kaip veidrodyje.
        var side: Int
        var mode: Mode
        /// Kiek jau atlikta, 0…1.
        var progress: Double
        /// Per kiek sekundžių švytintis taškas nubėga rodykle – rekomenduojamas tempas.
        var pace: Double
    }

    /// 3D vaizdas. Judesio pratimuose figūra – tai tu (kaip veidrodyje), o auksinis galvos kontūras
    /// rodo judesį: įžangoje jį kartoja, pratimo metu stovi taikinyje; rodyklės – kaip ten nueiti.
    /// Kai galva kontūre – kontūras žalias ir rodoma „✓ Teisingai“.
    /// Izometrijoje ir pečių pratimuose (kamera rankų ir pečių nemato) figūra pati rodo, ką daryti.
    struct CoachStage: View {
        let engine: SessionEngine
        let tracker: HeadTracker

        var body: some View {
            TimelineView(.animation) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let frame = frame(now: now)
                VStack(spacing: 8) {
                    ZStack(alignment: .top) {
                        CoachFigure(pose: frame.pose, ghost: frame.ghost, cameraAngle: frame.camera,
                                    matched: frame.matched)
                        if let hint = frame.hint {
                            MoveGuide(hint: hint, time: now)
                                .allowsHitTesting(false)
                        }
                        status(frame)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let ex = engine.current {
                        if frame.ghost != nil {
                            legend(followsYou: frame.followsYou)
                        }
                        StepStrip(steps: CoachDemo.steps(ex), active: frame.step)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Treneris rodo pratimą: \(engine.current?.name ?? "")")
        }

        private func legend(followsYou: Bool) -> some View {
            HStack(spacing: 14) {
                Label(followsYou ? "Figūra – tu" : "Sek figūrą", systemImage: "person.fill")
                    .foregroundStyle(.white)
                Label("Kontūras – kur judėti", systemImage: "circle.dashed")
                    .foregroundStyle(Palette.gold)
            }
            .font(.caption.weight(.semibold))
        }

        /// Ar darai teisingai: žalia „✓“ – galva kontūre, oranžinė – pataisyk.
        @ViewBuilder
        private func status(_ f: Frame) -> some View {
            if engine.phase == .active && !engine.warning.isEmpty {
                badge(engine.warning, symbol: "exclamationmark.triangle.fill", color: Palette.warn)
            } else if f.matched {
                badge(engine.current?.kind == .stretch ? "Teisingai – kvėpuok" : "Teisingai – laikyk",
                      symbol: "checkmark.circle.fill", color: Palette.calm)
            } else if engine.phase == .intro && f.ghost != nil {
                badge(f.followsYou ? "Pabandyk kartu su kontūru" : "Žiūrėk, kaip juda kontūras",
                      symbol: "eye.fill", color: Palette.gold)
            }
        }

        private func badge(_ text: String, symbol: String, color: Color) -> some View {
            Label(text, systemImage: symbol)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(color, in: Capsule())
                .padding(.top, 6)
                .transition(.opacity)
        }

        private struct Frame {
            var pose = CoachPose()
            var ghost: CoachPose?
            var camera = 0.0
            var step = 0
            var hint: MoveHint?
            var followsYou = false
            var matched = false
        }

        private func frame(now: Double) -> Frame {
            guard let ex = engine.current, engine.phase != .finished else { return Frame() }
            let moves = ex.kind == .reach || ex.kind == .stretch
            let pace = max(1.6, ex.minMoveSeconds)

            let followsYou = tracker.isTracking && !engine.guided

            if engine.phase == .intro {
                let demo = CoachDemo.loop(ex, t: now - engine.phaseStart)
                var f = Frame(pose: demo.pose, camera: Self.cameraAngle(ex, pose: demo.pose), step: demo.step)
                if moves {
                    // Kontūras kartoja judesį; figūra – tu (jei veidas matomas), kad galėtum pabandyti.
                    let r = CoachDemo.loopReach(ex, t: now - engine.phaseStart)
                    let mode: MoveHint.Mode = r.step == 0 ? .go : (r.step == 1 ? .hold : .back)
                    f.hint = MoveHint(axis: ex.axis, side: r.side, mode: mode, progress: r.progress, pace: pace)
                    f.ghost = demo.pose
                    f.followsYou = followsYou
                    f.pose = followsYou
                        ? CoachDemo.mirrorPose(yaw: tracker.yaw, pitch: tracker.pitch, roll: tracker.roll,
                                               depthCm: tracker.hasDepth ? tracker.depthCm : 0)
                        : CoachPose()
                }
                return f
            }

            guard moves else {
                let demo = CoachDemo.live(engine, now: now)
                return Frame(pose: demo.pose, camera: Self.cameraAngle(ex, pose: demo.pose), step: demo.step)
            }

            // Judesio pratimas: figūra – tu (arba laikmatis, kai veido nematau), kontūras – taikinys.
            let pose = followsYou
                ? CoachDemo.userPose(ex, valueNorm: engine.valueNorm,
                                     yaw: tracker.yaw, pitch: tracker.pitch, roll: tracker.roll)
                : CoachDemo.live(engine, now: now).pose
            let side = engine.demoSide
            let v = engine.valueNorm * Double(side)
            var f = Frame(pose: pose, camera: Self.cameraAngle(ex, pose: pose), followsYou: followsYou)
            switch engine.stage {
            case .hold:
                f.step = 1
                f.matched = true
                f.ghost = CoachDemo.targetPose(ex, side: side)
                f.hint = MoveHint(axis: ex.axis, side: side, mode: .hold, progress: engine.holdProgress, pace: pace)
            case .returning:
                f.step = 2
                f.ghost = CoachPose()
                f.hint = MoveHint(axis: ex.axis, side: side, mode: .back,
                                  progress: max(0, min(1, 1 - v)), pace: pace)
            default:
                f.step = 0
                f.ghost = CoachDemo.targetPose(ex, side: side)
                f.hint = MoveHint(axis: ex.axis, side: side, mode: .go,
                                  progress: max(0, min(1, v / 0.92)), pace: pace)
            }
            return f
        }

        /// Iš kur geriausiai matyti judesys: smakro įtraukimas ir mentės – iš šono.
        static func cameraAngle(_ ex: Exercise, pose: CoachPose) -> Double {
            switch ex.kind {
            case .reach, .stretch:
                switch ex.axis {
                case .depth: return 75
                case .pitch: return 40
                default: return 0
                }
            case .isometric:
                switch pose.hand {
                case .forehead, .backOfHead: return 40
                default: return 0
                }
            case .rhythm:
                return 60
            }
        }
    }

    /// Rodyklės aplink figūros galvą: kur ir kaip sukti. Blanki – visas kelias, ryški – kiek jau nueita,
    /// švytintis taškas bėga rekomenduojamu tempu. Išlaikant – žalias žiedas.
    struct MoveGuide: View {
        let hint: MoveHint
        let time: Double

        var body: some View {
            Canvas { ctx, size in
                let head = CoachRig.headOnScreen
                let c = CGPoint(x: size.width / 2, y: size.height * head.y)
                let r = size.height * head.radius
                let width = max(6, r * 0.2)
                let p = max(0, min(1, hint.progress))

                if hint.mode == .hold {
                    let ring = Path { path in
                        path.addArc(center: c, radius: r * 1.5, startAngle: .degrees(-90),
                                    endAngle: .degrees(270), clockwise: false)
                    }
                    ctx.stroke(ring, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: width))
                    ctx.stroke(ring.trimmedPath(from: 0, to: p), with: .color(Palette.calm),
                               style: StrokeStyle(lineWidth: width, lineCap: .round))
                    return
                }

                var points = Self.points(hint.axis, side: hint.side, c: c, r: r)
                guard points.count > 1 else { return }
                if hint.mode == .back { points.reverse() }
                let color = hint.mode == .back ? Color.white : Palette.gold
                let path = Path { $0.addLines(points) }

                ctx.stroke(path, with: .color(color.opacity(0.25)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                if p > 0.01 {
                    ctx.stroke(path.trimmedPath(from: 0, to: p), with: .color(color),
                               style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                }
                ctx.fill(Self.arrowHead(points, size: width * 2.6), with: .color(color))

                // Tempas: taškas bėga nuo pradžios iki galo per `pace` sekundžių.
                let k = (time / hint.pace).truncatingRemainder(dividingBy: 1)
                let dot = Self.point(points, at: k)
                let alpha = min(1, min(k, 1 - k) * 6)
                let d = width * 1.5
                ctx.fill(Path(ellipseIn: CGRect(x: dot.x - d / 2, y: dot.y - d / 2, width: d, height: d)),
                         with: .color(.white.opacity(0.9 * alpha)))
            }
        }

        /// Rodyklės kelias ekrane (pradžia → taikinys). Kampai – kaip `CoachStage.cameraAngle`:
        /// pasukimas ir lenkimas – iš priekio, linktelėjimas ir smakras – iš šono (veidas į kairę).
        static func points(_ axis: TrackedAxis, side: Int, c: CGPoint, r: CGFloat) -> [CGPoint] {
            let s = CGFloat(side >= 0 ? 1 : -1)
            func arc(_ center: CGPoint, rx: CGFloat, ry: CGFloat, from a: CGFloat, to b: CGFloat) -> [CGPoint] {
                (0...40).map { i in
                    let t = (a + (b - a) * CGFloat(i) / 40) * .pi / 180
                    return CGPoint(x: center.x + rx * cos(t), y: center.y + ry * sin(t))
                }
            }
            switch axis {
            case .yaw:
                // Žiedas virš galvos (žiūrim šiek tiek iš viršaus): nuo veido pusės į šoną ir atgal.
                return arc(CGPoint(x: c.x, y: c.y - r * 1.35), rx: r * 1.55, ry: r * 0.5,
                           from: 90, to: 90 - s * 150)
            case .roll:
                // Lankas virš galvos – viršugalvis krypsta į šoną.
                return arc(CGPoint(x: c.x, y: c.y + r * 1.0), rx: r * 2.15, ry: r * 2.15,
                           from: -90, to: -90 + s * 40)
            case .pitch:
                // Prieš veidą: žemyn (smakras link krūtinės) arba šiek tiek aukštyn.
                return s > 0
                    ? arc(c, rx: r * 1.9, ry: r * 1.9, from: 205, to: 140)
                    : arc(c, rx: r * 1.9, ry: r * 1.9, from: 165, to: 210)
            case .depth:
                // Tiesiai atgal, smakro aukštyje.
                let y = c.y + r * 0.55
                return (0...10).map { i in CGPoint(x: c.x - r * (2.3 - 1.15 * CGFloat(i) / 10), y: y) }
            case .none:
                return []
            }
        }

        private static func point(_ points: [CGPoint], at k: Double) -> CGPoint {
            let f = max(0, min(1, k)) * Double(points.count - 1)
            let i = min(points.count - 2, Int(f))
            let t = CGFloat(f - Double(i))
            let a = points[i], b = points[i + 1]
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }

        private static func arrowHead(_ points: [CGPoint], size: CGFloat) -> Path {
            let tip = points[points.count - 1]
            let prev = points[max(0, points.count - 4)]
            let angle = atan2(tip.y - prev.y, tip.x - prev.x)
            func at(_ a: CGFloat, _ len: CGFloat) -> CGPoint {
                CGPoint(x: tip.x + cos(angle + a) * len, y: tip.y + sin(angle + a) * len)
            }
            // Smaigalys šiek tiek už kelio galo, kad linijos galas po juo nesimatytų.
            let front = at(0, size * 0.45)
            return Path { path in
                path.move(to: front)
                path.addLine(to: at(.pi * 0.78, size))
                path.addLine(to: at(-.pi * 0.78, size))
                path.closeSubpath()
            }
        }
    }

    /// „Pasuk · Išlaikyk · Grįžk“ – dabartinis žingsnis paryškintas.
    struct StepStrip: View {
        let steps: [CoachStep]
        let active: Int

        var body: some View {
            HStack(spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    let on = i == active
                    Label(s.title, systemImage: s.symbol)
                        .font(.system(.subheadline, design: .rounded).weight(on ? .bold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(on ? Palette.ink : Color.white.opacity(0.75))
                        .background(on ? AnyShapeStyle(Palette.peach) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                        .scaleEffect(on ? 1.04 : 1)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: active)
        }
    }

    /// Juosta po treneriu: kiek liko iki taikinio, o išlaikant – kiek liko laikyti.
    struct MoveMeter: View {
        let title: String
        let value: Double
        let holding: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule()
                            .fill(holding ? Palette.gold : Palette.calm)
                            .frame(width: g.size.width * max(0.04, min(1, value)))
                    }
                }
                .frame(height: 12)
            }
            .animation(.linear(duration: 0.1), value: value)
        }
    }
}
