import AVFoundation
import SwiftUI

extension ParkavimoMeistras {

    struct GameView: View {
        @Environment(\.dismiss) private var dismiss
        @AppStorage(GameStorage.key(ParkavimoMeistras.id, "tilt")) private var useTilt = false
        @AppStorage(GameStorage.key(ParkavimoMeistras.id, "ar")) private var useAR = false

        @State private var sim: Simulation
        @State private var scenery: Scenery
        @State private var tilt = TiltSensor()
        @State private var wheel: Double?
        @State private var gas = false
        @State private var rev = false
        @State private var result: Outcome?
        @State private var showBanner = true

        struct Outcome: Equatable {
            let stars: Int
            let time: Double
            let scratches: Int
        }

        struct Viewport {
            let s: Double
            let ox: Double
            let oy: Double
        }

        init(level: Int) {
            _sim = State(initialValue: Simulation(index: level))
            _scenery = State(initialValue: Scenery(level: Levels.all[level]))
        }

        private var tiltActive: Bool { useTilt && tilt.isAvailable && tilt.isRunning }

        /// Vairo padėtis -1…1: lietimas > polinkis > tiesiai.
        private var steerInput: Double {
            if let w = wheel { return w }
            if tiltActive { return tilt.steer }
            return 0
        }

        var body: some View {
            GeometryReader { geo in
                let vp = viewport(geo.size)
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: result != nil)) { tl in
                    let snap = advanceFrame(tl.date)
                    ZStack(alignment: .top) {
                        Canvas { ctx, _ in
                            var c = ctx
                            let shake = sim.shake * 0.4
                            let jx = shake > 0 ? Double.random(in: -0.5...0.5) * shake : 0
                            let jy = shake > 0 ? Double.random(in: -0.5...0.5) * shake : 0
                            c.translateBy(x: vp.ox + jx * vp.s, y: vp.oy + jy * vp.s)
                            c.scaleBy(x: vp.s, y: vp.s)
                            Art.world(c, sim: sim, scenery: scenery, time: sim.clock)
                        }
                        // Piešiama vaizdo plokšte (Metal), ne procesoriumi.
                        .drawingGroup()

                        hud(snap)

                        if let t = snap.toast {
                            Text(t)
                                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                                .textCase(.uppercase)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.red, in: Capsule())
                                .foregroundStyle(.white)
                                .padding(.top, 70)
                                .transition(.opacity)
                        }

                        if snap.gear == .reverse && !snap.won {
                            let carY = vp.oy + sim.car.y * vp.s
                            let atBottom = carY < Double(geo.size.height) / 2
                            RearCamera(sim: sim, scenery: scenery, ar: useAR)
                                .frame(width: min(250, geo.size.width * 0.6), height: min(250, geo.size.width * 0.6) * 0.62)
                                .frame(maxHeight: .infinity, alignment: atBottom ? Alignment.bottom : Alignment.top)
                                .padding(.top, 66)
                                .padding(.bottom, 190)
                        }
                    }
                    .onChange(of: snap.bumps) { _, _ in Haptics.thud() }
                    .onChange(of: snap.beeps) { _, _ in
                        if sim.rearDistance < 0.6 { Haptics.place() } else { Haptics.tap() }
                    }
                    .onChange(of: snap.won) { _, won in if won { finish() } }
                }
            }
            .overlay(alignment: .bottom) { controls }
            .overlay { banner }
            .overlay {
                if let r = result {
                    WinCard(level: sim.level, index: sim.index, result: r,
                            hasNext: sim.index + 1 < Levels.all.count,
                            onNext: { load(sim.index + 1) },
                            onAgain: { load(sim.index) },
                            onMenu: { dismiss() })
                }
            }
            .background(Color(red: 0.09, green: 0.1, blue: 0.12).ignoresSafeArea())
            .statusBarHidden(true)
            .onAppear { if useTilt { tilt.start() } }
            .onDisappear { tilt.stop() }
            .task(id: sim.index) {
                showBanner = true
                try? await Task.sleep(for: .seconds(2.6))
                withAnimation(.easeOut(duration: 0.4)) { showBanner = false }
            }
        }

        // MARK: - Kadras

        private func advanceFrame(_ date: Date) -> Snapshot {
            sim.controls = Controls(steer: steerInput, direct: wheel != nil || tiltActive, gas: gas, rev: rev, hand: false)
            return sim.advance(to: date)
        }

        private func viewport(_ size: CGSize) -> Viewport {
            let lv = sim.level
            let top = 60.0, bottom = 150.0
            let availW = Double(size.width) - 12, availH = max(120, Double(size.height) - top - bottom)
            let s = min(availW / lv.w, availH / lv.h)
            return Viewport(s: s, ox: (Double(size.width) - lv.w * s) / 2, oy: top + (availH - lv.h * s) / 2)
        }

        private func load(_ index: Int) {
            wheel = nil; gas = false; rev = false
            sim = Simulation(index: index)
            scenery = Scenery(level: Levels.all[index])
            withAnimation { result = nil }
        }

        private func finish() {
            let stars = Physics.stars(time: sim.time, scratches: sim.scratches, par: sim.level.par)
            let s = ParkavimoMeistras.storage
            s.setIfHigher(stars, for: "stars.\(sim.index)")
            s.setIfLower(Int(sim.time * 10), for: "best.\(sim.index)")
            Haptics.success()
            let r = Outcome(stars: stars, time: sim.time, scratches: sim.scratches)
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { result = r }
            }
        }

        // MARK: - Prietaisų skydelis

        private func hud(_ snap: Snapshot) -> some View {
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.45), in: SwiftUI.Circle())
                }
                .accessibilityLabel("Atgal į meniu")

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(sim.index + 1). \(sim.level.name)")
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .textCase(.uppercase)
                        .lineLimit(1)
                    Text(sim.level.place)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f s", Double(snap.tenths) / 10).replacingOccurrences(of: ".", with: ","))
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    HStack(spacing: 6) {
                        Text("Įbr. \(snap.scratches)").foregroundStyle(.red)
                        Text(snap.gear.rawValue).foregroundStyle(Color(red: 1, green: 0.76, blue: 0.1))
                    }
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                }
                Button {
                    Haptics.tap()
                    load(sim.index)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.45), in: SwiftUI.Circle())
                }
                .accessibilityLabel("Pradėti iš naujo")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .background(LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        }

        @ViewBuilder
        private var banner: some View {
            if showBanner {
                VStack(spacing: 6) {
                    Text(sim.level.name)
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(Color(red: 1, green: 0.76, blue: 0.1))
                    Text(sim.level.tip)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                }
                .padding(16)
                .frame(maxWidth: 340)
                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }

        // MARK: - Vairas ir pedalai (veikia keliais pirštais vienu metu)

        private var controls: some View {
            HStack(alignment: .bottom, spacing: 10) {
                SteeringWheel(turn: steerInput, label: wheel != nil ? "VAIRUOJI" : (tiltActive ? "POLINKIS" : "TEMPK"))
                    .frame(width: 140, height: 150)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in wheel = Physics.clamp(Double(v.translation.width) / 70, -1, 1) }
                            .onEnded { _ in wheel = nil }
                    )
                Spacer(minLength: 0)
                Pedal(title: "R", caption: "ATBUL.", pressed: rev, accent: .red)
                    .frame(width: 68, height: 92)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in if !rev { rev = true; Haptics.tap() } }
                            .onEnded { _ in rev = false }
                    )
                Pedal(title: "D", caption: "GAZAS", pressed: gas, accent: .green)
                    .frame(width: 80, height: 132)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in if !gas { gas = true; Haptics.tap() } }
                            .onEnded { _ in gas = false }
                    )
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .padding(.top, 24)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .allowsHitTesting(result == nil)
        }
    }

    // MARK: - Vairas

    struct SteeringWheel: View {
        let turn: Double
        let label: String

        var body: some View {
            VStack(spacing: 2) {
                ZStack {
                    SwiftUI.Circle().stroke(Color(white: 0.08), lineWidth: 14)
                    SwiftUI.Circle().stroke(
                        RadialGradient(colors: [Color(white: 0.32), Color(white: 0.12)], center: .top, startRadius: 0, endRadius: 140),
                        lineWidth: 10)
                    WheelSpokes().fill(Color(white: 0.18))
                    SwiftUI.Circle().fill(Color(white: 0.14)).frame(width: 34, height: 34)
                    SwiftUI.Circle().fill(Color(red: 1, green: 0.76, blue: 0.1)).frame(width: 10, height: 10)
                    Capsule().fill(Color(red: 1, green: 0.76, blue: 0.1))
                        .frame(width: 7, height: 12)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(7)
                .rotationEffect(.degrees(turn * 135))
                .animation(.linear(duration: 0.05), value: turn)
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Vairas")
        }
    }

    struct WheelSpokes: Shape {
        func path(in rect: CGRect) -> Path {
            let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2
            var p = Path()
            p.addRect(CGRect(x: c.x - r, y: c.y - 3, width: r * 2, height: 9))
            p.addRect(CGRect(x: c.x - 5, y: c.y, width: 10, height: r))
            return p
        }
    }

    struct Pedal: View {
        let title: String
        let caption: String
        let pressed: Bool
        let accent: Color

        var body: some View {
            VStack(spacing: 4) {
                Text(title).font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(pressed ? accent : Color.white.opacity(0.9))
                Text(caption).font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(PedalRibs().stroke(Color.black.opacity(0.35), lineWidth: 3).padding(.vertical, 8).allowsHitTesting(false))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black, radius: 0, y: pressed ? 1 : 6)
            .offset(y: pressed ? 5 : 0)
            .scaleEffect(y: pressed ? 0.96 : 1, anchor: .bottom)
            .animation(.easeOut(duration: 0.06), value: pressed)
            .accessibilityLabel(title == "D" ? "Akceleratorius" : "Stabdis ir atbulinė")
        }
    }

    struct PedalRibs: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            var y = rect.minY
            while y <= rect.maxY {
                p.move(to: CGPoint(x: rect.minX + 8, y: y))
                p.addLine(to: CGPoint(x: rect.maxX - 8, y: y))
                y += 12
            }
            return p
        }
    }

    // MARK: - Galinio vaizdo kamera

    struct RearCamera: View {
        let sim: Simulation
        let scenery: Scenery
        let ar: Bool

        var body: some View {
            ZStack(alignment: .topLeading) {
                if ar {
                    CameraPreview(position: .back, mirrored: false) { Color.black }
                }
                Canvas { ctx, size in draw(ctx, size) }
                HStack(spacing: 5) {
                    SwiftUI.Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text(ar ? "GALINIS VAIZDAS · AR" : "GALINIS VAIZDAS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 1)
                }
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(white: 0.2), lineWidth: 2))
            .shadow(color: .black.opacity(0.55), radius: 14, y: 8)
            .allowsHitTesting(false)
            .accessibilityLabel("Galinio vaizdo kamera, iki kliūties \(String(format: "%.1f", sim.rearDistance)) metro")
        }

        private func draw(_ base: GraphicsContext, _ size: CGSize) {
            let W = Double(size.width), H = Double(size.height)
            let car = sim.car
            let k = H / 6.2   // matome ~6 m už mašinos
            let rx = car.x - cos(car.a) * CarSpec.length / 2
            let ry = car.y - sin(car.a) * CarSpec.length / 2
            var world = base
            world.translateBy(x: W / 2, y: H * 0.97)
            world.scaleBy(x: k, y: k)
            world.rotate(by: .radians(-Double.pi / 2 - (car.a + Double.pi)))
            world.translateBy(x: -rx, y: -ry)

            if !ar {
                Art.world(world, sim: sim, scenery: scenery, time: sim.clock, hidePlayer: true)
                base.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.16, green: 0.31, blue: 0.55).opacity(0.12)))
                base.fill(Path(CGRect(origin: .zero, size: size)),
                          with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.6)]),
                                                center: CGPoint(x: W / 2, y: H / 2), startRadius: H * 0.3, endRadius: W * 0.75))
                var lines = Path()
                var y = 0.0
                while y < H { lines.addRect(CGRect(x: 0, y: y, width: W, height: 1)); y += 3 }
                base.fill(lines, with: .color(.white.opacity(0.03)))
            } else {
                base.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.12)))
            }

            // buferis
            base.fill(Path(roundedRect: CGRect(x: W * 0.18, y: H * 0.95, width: W * 0.64, height: H * 0.08), cornerRadius: 6),
                      with: .color(Color(red: 1, green: 0.76, blue: 0.1).opacity(0.85)))

            // kreipiamosios linijos
            let left = sim.guidePath(side: -1), right = sim.guidePath(side: 1)
            let bands: [(Int, Int, Color)] = [(0, 10, .red), (10, 20, .yellow), (20, 30, .green)]
            for pts in [left, right] {
                for (a, b, col) in bands {
                    var p = Path()
                    p.move(to: CGPoint(x: pts[a].0, y: pts[a].1))
                    for i in (a + 1)...b { p.addLine(to: CGPoint(x: pts[i].0, y: pts[i].1)) }
                    world.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 0.09, lineCap: .round))
                }
            }
            for (i, col) in [(10, Color.red), (20, Color.yellow)] {
                var p = Path()
                p.move(to: CGPoint(x: left[i].0, y: left[i].1))
                p.addLine(to: CGPoint(x: right[i].0, y: right[i].1))
                world.stroke(p, with: .color(col), lineWidth: 0.07)
            }

            // atstumo juostos
            let dist = sim.rearDistance
            let bars = dist >= 3 ? 0 : min(5, Int(ceil((3 - dist) / 0.6)))
            for i in 0..<5 {
                let col: Color = i < 2 ? .green : (i < 4 ? .yellow : .red)
                let bw = W * 0.05, bh = H * (0.12 + Double(i) * 0.05)
                let x = W - Double(6 - i) * (bw + 4) - 4
                base.fill(Path(CGRect(x: x, y: H * 0.38 - bh, width: bw, height: bh)),
                          with: .color(i < bars ? col : Color.white.opacity(0.15)))
            }
            let label = dist >= 3 ? "> 3,0 m" : String(format: "%.1f m", dist).replacingOccurrences(of: ".", with: ",")
            base.draw(Text(label).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.white),
                      at: CGPoint(x: W - 8, y: H * 0.5), anchor: .trailing)
        }
    }

    // MARK: - Pergalė

    struct WinCard: View {
        let level: Level
        let index: Int
        let result: GameView.Outcome
        let hasNext: Bool
        let onNext: () -> Void
        let onAgain: () -> Void
        let onMenu: () -> Void

        var body: some View {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("Suparkuota!")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .textCase(.uppercase)
                        .foregroundStyle(Color(red: 1, green: 0.76, blue: 0.1))
                    Text("\(index + 1). \(level.name) · \(level.place)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    StarRow(stars: result.stars, size: 34)
                    HStack(spacing: 8) {
                        StatChip(symbol: "stopwatch", text: result.time.lt(1) + " s")
                        StatChip(symbol: "bandage", text: "\(result.scratches) įbr.")
                        StatChip(symbol: "flag.checkered", text: "Norma \(Int(level.par)) s")
                    }
                    if hasNext {
                        Button("Kita aikštelė →", action: onNext)
                            .buttonStyle(ArcadeButtonStyle(tint: ParkavimoMeistras.info.tint))
                    }
                    HStack(spacing: 10) {
                        Button("Dar kartą", action: onAgain)
                            .buttonStyle(ArcadeButtonStyle(tint: ParkavimoMeistras.info.tint, prominent: false))
                        Button("Meniu", action: onMenu)
                            .buttonStyle(ArcadeButtonStyle(tint: ParkavimoMeistras.info.tint, prominent: false))
                    }
                }
                .padding(22)
                .frame(maxWidth: 380)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(20)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}
