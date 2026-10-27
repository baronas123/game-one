import AVFoundation
import SwiftUI

extension Sankryza {

    /// HUD reikšmės – atnaujinamos tik kai pasikeičia (ne kiekvieną kadrą).
    struct HudState: Equatable {
        var score = 0
        var hearts = 3
        var combo = 0
        var multiplier = 1
        var city = Sankryza.cities[0]
        var stageText = "1 etapas"
        var estopReady = true
        var banner: BannerInfo?
    }

    struct FinalStats {
        var score = 0
        var best = 0
        var record = false
        var time = 0
        var maxCombo = 0
        var stage = 1
        var city = ""
        var cause: Cause = .crash
        var crashPoint = CGPoint.zero
        var date = Date()
    }

    enum Screen { case start, play, over }

    struct RootView: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @State private var sim = Simulation()
        @State private var hud = HudState()
        @State private var screen: Screen = .start
        @State private var tilt = TiltSensor()
        @State private var sensorsOn = false
        @State private var cameraOn = false
        @State private var lastTick: Date?
        @State private var parallax = CGSize.zero
        @State private var stats = FinalStats()
        @State private var best = Sankryza.storage.int("best")

        var body: some View {
            GeometryReader { outer in
                ZStack {
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                                Canvas { ctx, _ in
                                    Renderer.draw(ctx, sim: sim, time: timeline.date.timeIntervalSinceReferenceDate,
                                                  parallax: parallax, reducedMotion: reduceMotion)
                                }
                                // Piešiama vaizdo plokšte (Metal), ne procesoriumi.
                                .drawingGroup()
                                .onChange(of: timeline.date) { _, now in tick(now) }
                            }
                            .contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { value in sim.tap(at: value.location) })

                            if cameraOn && screen != .over && sim.city.unit > 0 {
                                billboardCamera
                            }
                        }
                        .onAppear { configure(geo.size, outer.safeAreaInsets) }
                        .onChange(of: geo.size) { _, s in configure(s, outer.safeAreaInsets) }
                    }
                    .ignoresSafeArea()

                    if screen == .play || screen == .over { hudBar }
                    if let b = hud.banner, screen == .play { bannerView(b) }
                    if screen == .play { estopButton }
                    if screen == .start { startPanel }
                    if screen == .over { overPanel }
                }
            }
            .background(Color(red: 0.11, green: 0.125, blue: 0.15).ignoresSafeArea())
            .statusBarHidden(screen == .play)
            .onAppear {
                sim.onEvent = { event in
                    switch event {
                    case .click: Haptics.tap()
                    case .pass: break
                    case .heart: Haptics.error()
                    case .crash: Haptics.thud()
                    case .stage: Haptics.success()
                    case .estop: Haptics.thud()
                    }
                }
            }
            .onDisappear { tilt.stop() }
            .onChange(of: tilt.shakeCount) { _, _ in
                if sensorsOn && screen == .play { sim.emergencyStop() }
            }
        }

        // MARK: Ciklas

        private func configure(_ size: CGSize, _ insets: EdgeInsets) {
            sim.configure(size: size, topInset: Double(insets.top) + 66, bottomInset: Double(insets.bottom) + 12)
        }

        private func tick(_ now: Date) {
            let dt = lastTick.map { now.timeIntervalSince($0) } ?? 0
            lastTick = now
            let ended = sim.step(dt)
            if sensorsOn {
                let target = CGSize(width: tilt.steer * 6, height: tilt.pitch * 6)
                let next = CGSize(width: parallax.width + (target.width - parallax.width) * 0.15,
                                  height: parallax.height + (target.height - parallax.height) * 0.15)
                if abs(next.width - parallax.width) > 0.05 || abs(next.height - parallax.height) > 0.05 { parallax = next }
            } else if parallax != .zero {
                parallax = .zero
            }
            var h = HudState()
            h.score = sim.score
            h.hearts = sim.hearts
            h.combo = sim.combo
            h.multiplier = sim.multiplier
            h.city = sim.cityName
            h.stageText = "\(sim.stage + 1) etapas · \(sim.passed % Simulation.perStage)/\(Simulation.perStage)"
            h.estopReady = sim.estopReady
            h.banner = sim.banner
            if h != hud { hud = h }
            if ended { finish() }
        }

        private func start() {
            Haptics.tap()
            sim.startGame()
            lastTick = nil
            withAnimation(.easeOut(duration: 0.25)) { screen = .play }
        }

        private func finish() {
            let record = Sankryza.storage.setIfHigher(sim.score, for: "best")
            best = Sankryza.storage.int("best")
            stats = FinalStats(score: sim.score, best: best, record: record, time: Int(sim.playT), maxCombo: sim.maxCombo,
                               stage: sim.stage + 1, city: sim.cityName, cause: sim.cause, crashPoint: sim.crashPoint, date: Date())
            Haptics.error()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { screen = .over }
        }

        private func toMenu() {
            sim.reset(.attract)
            sim.warmUp()
            withAnimation { screen = .start }
        }

        // MARK: HUD

        private var hudBar: some View {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(hud.score)")
                            .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        Text("PRAVAŽIAVO")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.7))
                        if hud.combo >= 3 {
                            Text("SRAUTAS \(hud.combo)" + (hud.multiplier > 1 ? " · ×\(hud.multiplier)" : ""))
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(Palette.amber.color)
                                .padding(.top, 6)
                        }
                    }
                    Spacer(minLength: 4)
                    VStack(spacing: 4) {
                        Text(hud.city)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color(red: 0.11, green: 0.42, blue: 0.23), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 2))
                        Text(hud.stageText.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { i in
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(i < hud.hearts ? Palette.red.color : Color.white.opacity(0.18))
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(hud.hearts) širdelės")
                        Button {
                            Haptics.tap()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 34, height: 34)
                                .background(.black.opacity(0.35), in: Circle())
                        }
                        .accessibilityLabel("Uždaryti žaidimą")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 18)
                .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top))
                Spacer()
            }
            .foregroundStyle(.white)
        }

        private func bannerView(_ b: BannerInfo) -> some View {
            VStack(spacing: 2) {
                Text(b.title).font(.system(size: 20, weight: .black, design: .rounded)).multilineTextAlignment(.center)
                Text(b.subtitle.uppercased()).font(.system(size: 12, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(b.warn ? RGB(0xb3261e).color : Color(red: 0.11, green: 0.42, blue: 0.23), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 8)
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 200)
            .transition(.scale.combined(with: .opacity))
            .id(b.id)
            .allowsHitTesting(false)
        }

        private var estopButton: some View {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        sim.emergencyStop()
                    } label: {
                        VStack(spacing: 2) {
                            Text("STOP").font(.system(size: 15, weight: .black, design: .rounded))
                            Text(hud.estopReady ? (sensorsOn ? "ARBA PURTYK" : "VISI RAUDONI") : "KITAME ETAPE")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(
                            Circle().fill(RadialGradient(colors: [RGB(0xff6b5e).color, RGB(0xc4170c).color],
                                                         center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 50))
                        )
                        .overlay(Circle().stroke(RGB(0xffd21f).color, lineWidth: 4))
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 6)
                        .saturation(hud.estopReady ? 1 : 0)
                        .opacity(hud.estopReady ? 1 : 0.6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hud.estopReady)
                    .accessibilityLabel("Avarinis stabdymas: visi šviesoforai raudoni")
                }
            }
            .padding(16)
        }

        /// Gyva priekinė kamera ant LED ekrano prie sankryžos.
        private var billboardCamera: some View {
            let u = sim.city.unit
            let b = sim.city.board
            return CameraPreview(position: .front, mirrored: true) { Color.clear }
                .frame(width: b.width * u, height: b.height * u)
                .overlay(
                    VStack(spacing: 0.09 * u - 1) {
                        ForEach(0..<Int(b.height / 0.09), id: \.self) { _ in Color.black.opacity(0.22).frame(height: 1) }
                    }
                    .allowsHitTesting(false)
                )
                .overlay(alignment: .topLeading) {
                    Circle().fill(Color.red).frame(width: 7, height: 7).padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 0.06 * u))
                .position(x: b.midX * u + parallax.width, y: b.midY * u + parallax.height)
                .allowsHitTesting(false)
        }

        // MARK: Kortelės

        private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 0) {
                    HazardStripe().frame(height: 12)
                    VStack(alignment: .leading, spacing: 14) { content() }
                        .padding(18)
                }
                .frame(maxWidth: 440)
                .background(Color(red: 0.086, green: 0.094, blue: 0.118).opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 25, y: 12)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .foregroundStyle(.white)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        private var startPanel: some View {
            card {
                HStack {
                    Text("EISMO REGULIUOTOJO PAMAINA")
                        .font(.system(size: 12, weight: .bold, design: .rounded)).tracking(2)
                        .foregroundStyle(Palette.amber.color)
                    Spacer()
                    GameCloseButton()
                }
                Text("SANKRYŽA").font(.system(size: 40, weight: .black, design: .rounded))
                Text("Piko valanda. Šviesoforai – tavo rankose. Praleisk kuo daugiau automobilių ir neleisk jiems susidurti.")
                    .font(.callout).foregroundStyle(.white.opacity(0.75))
                VStack(alignment: .leading, spacing: 6) {
                    rule(Palette.green.color, "Bakstelėk šviesoforą arba juostą – žalia ⇄ raudona.")
                    rule(Palette.red.color, "Statmenos kryptys kartu žalios – garantuota avarija.")
                    rule(Palette.amber.color, "Ilgai stovintis vairuotojas pypsi. Nespėsi – prarasi širdelę.")
                    rule(RGB(0x3d8bff).color, "Policijai – pirmenybė (+3). Supurtyk telefoną – visi raudoni.")
                }
                .font(.subheadline)
                toggleRow(on: sensorsOn, title: "Judesio jutikliai",
                          hint: tilt.isAvailable ? "Purtymas – avarinis stabdymas, polinkis – 3D gylis."
                                                 : "Jutikliai šiame įrenginyje nepasiekiami – naudok STOP mygtuką.",
                          warn: !tilt.isAvailable) {
                    sensorsOn.toggle()
                    if sensorsOn { tilt.start() } else { tilt.stop() }
                }
                toggleRow(on: cameraOn, title: "Šviesoforo kamera",
                          hint: cameraHint, warn: cameraDenied) {
                    cameraOn.toggle()
                }
                HStack(spacing: 12) {
                    Button(action: start) { Text("PRADĖTI PAMAINĄ") }
                        .buttonStyle(ArcadeButtonStyle(tint: Sankryza.info.tint))
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("REKORDAS").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                        Text("\(best)").font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
                    }
                }
            }
        }

        private var cameraDenied: Bool {
            let s = AVCaptureDevice.authorizationStatus(for: .video)
            return s == .denied || s == .restricted
        }

        private var cameraHint: String {
            cameraDenied ? "Kamerai neleista – Nustatymuose leisk prieigą. Ekrane bus reklama."
                         : "Tavo veidas – ant sankryžos LED ekrano."
        }

        private func rule(_ color: Color, _ text: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(color).frame(width: 11, height: 11)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
        }

        private func toggleRow(on: Bool, title: String, hint: String, warn: Bool, action: @escaping () -> Void) -> some View {
            Button {
                Haptics.tap()
                action()
            } label: {
                HStack(spacing: 10) {
                    Capsule()
                        .fill(on ? Palette.green.color : Color.white.opacity(0.18))
                        .frame(width: 38, height: 22)
                        .overlay(alignment: on ? .trailing : .leading) {
                            Circle().fill(.white).frame(width: 16, height: 16).padding(3)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 14, weight: .bold))
                        Text(hint).font(.caption).foregroundStyle(warn ? Palette.amber.color : Color.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.16), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(on ? "Įjungta" : "Išjungta")
        }

        private var overTitle: String {
            switch stats.cause {
            case .crash: return "AVARIJA!"
            case .jam: return "KAMŠTIS!"
            case .patience: return "KANTRYBĖ BAIGĖSI"
            }
        }

        private var overPanel: some View {
            card {
                Text("PAMAINA BAIGTA · \(stats.city.uppercased())")
                    .font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.5)
                    .foregroundStyle(Palette.amber.color)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(overTitle).font(.system(size: 34, weight: .black, design: .rounded))
                speedCamera
                HStack {
                    Text("\(stats.score)").font(.system(size: 52, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(Palette.amber.color)
                    Spacer()
                    if stats.record {
                        Text("NAUJAS REKORDAS")
                            .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(1.2)
                            .foregroundStyle(RGB(0x1a1406).color)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Palette.amber.color, in: RoundedRectangle(cornerRadius: 4))
                    } else {
                        Text("REKORDAS \(stats.best)").font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                HStack(spacing: 8) {
                    statBox(stats.time.clockText, "Pamaina")
                    statBox("\(stats.maxCombo)", "Geriausias srautas")
                    statBox("\(stats.stage)", "Etapas")
                }
                HStack(spacing: 12) {
                    Button(action: start) { Text("DAR KARTĄ") }
                        .buttonStyle(ArcadeButtonStyle(tint: Sankryza.info.tint))
                    Button(action: toMenu) { Text("Meniu") }
                        .buttonStyle(ArcadeButtonStyle(tint: .white, prominent: false))
                        .frame(maxWidth: 120)
                }
            }
        }

        private func statBox(_ value: String, _ label: String) -> some View {
            VStack(spacing: 2) {
                Text(value).font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
                Text(label.uppercased()).font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.16), lineWidth: 1))
        }

        /// „Greičio kameros“ kadras: priekinė kamera (jei įjungta) arba sustabdytas avarijos vaizdas.
        private var speedCamera: some View {
            ZStack {
                if cameraOn && !cameraDenied {
                    CameraPreview(position: .front, mirrored: true) { Color.black }
                } else {
                    Canvas { ctx, size in
                        let u = sim.city.unit
                        guard u > 0 else { return }
                        var g = ctx
                        let k = size.width / (9 * u)
                        g.translateBy(x: size.width / 2, y: size.height / 2)
                        g.scaleBy(x: k, y: k)
                        g.translateBy(x: -stats.crashPoint.x * u, y: -stats.crashPoint.y * u)
                        Renderer.draw(g, sim: sim, time: stats.date.timeIntervalSinceReferenceDate, parallax: .zero, reducedMotion: true)
                    }
                }
            }
            .grayscale(1)
            .contrast(1.25)
            .overlay {
                VStack(spacing: 0) {
                    HStack {
                        Text("GREIČIO KAMERA").font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(Palette.amber.color)
                        Spacer()
                        Text(stats.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute().second()))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.6))
                    Spacer()
                    HStack {
                        Text(stats.city.uppercased()).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Text("\(stats.score) TŠK.").font(.system(size: 15, weight: .black, design: .rounded)).foregroundStyle(Palette.amber.color)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.black.opacity(0.6))
                }
                .foregroundStyle(.white)
            }
            .overlay { CornerBrackets().stroke(.white.opacity(0.75), lineWidth: 2).padding(.horizontal, 26).padding(.vertical, 38) }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("Greičio kameros kadras, \(stats.score) taškų")
        }
    }

    /// Geltonai juoda „pavojaus“ juosta kortelės viršuje.
    struct HazardStripe: View {
        var body: some View {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.08, green: 0.086, blue: 0.1)))
                var p = Path()
                var x: CGFloat = -size.height
                while x < size.width + size.height {
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    p.addLine(to: CGPoint(x: x + size.height + 12, y: 0))
                    p.addLine(to: CGPoint(x: x + 12, y: size.height))
                    p.closeSubpath()
                    x += 24
                }
                ctx.fill(p, with: .color(Palette.amber.color))
            }
        }
    }

    /// Greičio kameros taikiklio kampai.
    struct CornerBrackets: Shape {
        func path(in rect: CGRect) -> Path {
            let k: CGFloat = 22
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + k)); p.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.minX + k, y: rect.minY))
            p.move(to: CGPoint(x: rect.maxX - k, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + k))
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY - k)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX + k, y: rect.maxY))
            p.move(to: CGPoint(x: rect.maxX - k, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - k))
            return p
        }
    }
}
