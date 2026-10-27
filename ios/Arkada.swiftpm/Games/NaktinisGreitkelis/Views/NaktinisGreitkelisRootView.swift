import SwiftUI

extension NaktinisGreitkelis {

    enum Phase {
        case menu, race, paused, over
    }

    struct RaceResult {
        var km: Double = 0
        var city = "Vilnius"
        var passed = 0
        var newBest = false
    }

    /// Žaidimo ekranas: pilno ekrano `Canvas` (meniu fone važiuoja „demo“), ant jo – HUD ir meniu.
    struct RootView: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.scenePhase) private var scenePhase
        @AppStorage(GameStorage.key(NaktinisGreitkelis.id, "useTilt")) private var useTilt = true
        @AppStorage(GameStorage.key(NaktinisGreitkelis.id, "camera")) private var cameraOn = false
        @AppStorage(GameStorage.key(NaktinisGreitkelis.id, "bestTenths")) private var bestTenths = 0

        @State private var engine = RaceEngine()
        @State private var backdrop = Backdrop()
        @State private var tilt = TiltSensor()
        @State private var phase: Phase = .menu
        @State private var result = RaceResult()

        var body: some View {
            ZStack {
                GeometryReader { geo in
                    // 60 kadrų/s užtenka (ProMotion telefonai kitaip piešia 120 k/s – dvigubas darbas).
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: phase == .paused)) { timeline in
                        let _ = step(timeline.date, size: geo.size)
                        Canvas { ctx, size in
                            RacePainter.draw(engine, backdrop: backdrop, in: &ctx, size: size)
                        }
                        // Piešiama vaizdo plokšte (Metal), ne procesoriumi – kitaip kadrai stringa.
                        .drawingGroup()
                    }
                    .contentShape(Rectangle())
                    .gesture(steerGesture(width: geo.size.width))
                }
                .ignoresSafeArea()

                if phase == .race {
                    HudView(engine: engine, cameraOn: cameraOn, nitroHint: useTilt && tilt.isAvailable ? "arba purtyk" : "laikyk",
                            onPause: pause)
                }

                switch phase {
                case .menu: menu.transition(.opacity)
                case .over: overScreen.transition(.opacity)
                case .paused: pausedScreen.transition(.opacity)
                case .race: EmptyView()
                }
            }
            .background(Neon.night.ignoresSafeArea())
            .foregroundStyle(.white)
            .statusBarHidden(phase == .race)
            .onAppear { tilt.start() }
            .onDisappear { tilt.stop() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active { pause() }
            }
        }

        // MARK: - Kadras

        private func step(_ date: Date, size: CGSize) {
            engine.layout(width: Double(size.width), height: Double(size.height))
            engine.useTilt = useTilt && tilt.isAvailable
            engine.tiltSteer = tilt.steer
            engine.reducedMotion = reduceMotion
            if tilt.shakeCount != engine.seenShakeCount {
                engine.seenShakeCount = tilt.shakeCount
                engine.shakeBoost()
            }
            engine.tick(date)
            for event in engine.drainEvents() {
                switch event {
                case .crash: Haptics.thud()
                case .pickup: Haptics.tap()
                case .checkpoint: Haptics.success()
                case .start: Haptics.place()
                case .gameOver: DispatchQueue.main.async { finish() }
                }
            }
        }

        private func steerGesture(width: CGFloat) -> some Gesture {
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard phase == .race else { return }
                    engine.touchSteer = v.location.x < width / 2 ? -1 : 1
                }
                .onEnded { _ in engine.touchSteer = 0 }
        }

        // MARK: - Veiksmai

        private func startRace() {
            Haptics.tap()
            engine.reducedMotion = reduceMotion
            engine.newRace()
            withAnimation(.easeOut(duration: 0.25)) { phase = .race }
        }

        private func pause() {
            guard phase == .race else { return }
            engine.pause()
            engine.touchSteer = 0
            engine.nitroHeld = false
            withAnimation { phase = .paused }
        }

        private func finish() {
            guard phase == .race || phase == .paused else { return }
            let tenths = Int((engine.km * 10).rounded(.down))
            result = RaceResult(km: engine.km, city: engine.reachedCity, passed: engine.passed, newBest: tenths > bestTenths)
            if tenths > bestTenths { bestTenths = tenths }
            engine.touchSteer = 0
            engine.nitroHeld = false
            withAnimation(.easeOut(duration: 0.3)) { phase = .over }
        }

        // MARK: - Ekranai

        private var bestText: String { "\((Double(bestTenths) / 10).lt(1)) km" }

        private var menu: some View {
            ScrollView {
                VStack(spacing: 20) {
                    HStack { GameCloseButton(); Spacer() }
                    Spacer(minLength: 40)
                    NeonTitle(top: "NAKTINIS", bottom: "GREITKELIS")
                    Text("Vilnius → Klaipėda per naktį. Spėk iki kito miesto, kol nesibaigė laikas. Lenk mašinas, rink nitro balionus.")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)

                    Button("VAŽIUOJAM", action: startRace)
                        .buttonStyle(ArcadeButtonStyle(tint: Neon.magenta))
                        .frame(maxWidth: 300)

                    Text("Rekordas: ").foregroundColor(.white.opacity(0.7)) + Text(bestText).bold().foregroundColor(Neon.amber)

                    VStack(spacing: 10) {
                        SettingRow(title: "Valdymas",
                                   hint: tilt.isAvailable ? nil : "Polinkio jutiklis nepasiekiamas") {
                            Picker("Valdymas", selection: $useTilt) {
                                Text("Polinkis").tag(true)
                                Text("Lietimas").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 170)
                        }
                        SettingRow(title: "Veidas veidrodėlyje", hint: "Priekinė kamera – tik tavo telefone") {
                            Toggle("Veidas veidrodėlyje", isOn: $cameraOn).labelsHidden().tint(Neon.cyan)
                        }
                    }
                    .frame(maxWidth: 380)

                    Text("Pakreipk telefoną arba laikyk kairę / dešinę ekrano pusę. Supurtyk – nitro.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .background(LinearGradient(colors: [Neon.night.opacity(0.25), Neon.night.opacity(0.8)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        }

        private var overScreen: some View {
            VStack(spacing: 18) {
                Spacer()
                NeonTitle(top: "LAIKAS", bottom: "BAIGĖSI")
                if result.newBest {
                    Text("★ NAUJAS REKORDAS ★")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Neon.amber)
                        .shadow(color: Neon.amber, radius: 8)
                }
                HStack(spacing: 8) {
                    StatTile(value: result.km.lt(1), label: "KM")
                    StatTile(value: result.city, label: "PASIEKTA")
                    StatTile(value: "\(result.passed)", label: "APLENKTA")
                }
                .frame(maxWidth: 380)
                Text("Rekordas: ").foregroundColor(.white.opacity(0.7)) + Text(bestText).bold().foregroundColor(Neon.amber)
                Button("DAR KARTĄ", action: startRace)
                    .buttonStyle(ArcadeButtonStyle(tint: Neon.magenta))
                    .frame(maxWidth: 300)
                Button("Į meniu") {
                    engine.backToMenu()
                    withAnimation { phase = .menu }
                }
                .buttonStyle(ArcadeButtonStyle(tint: .white, prominent: false))
                .frame(maxWidth: 300)
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Neon.night.opacity(0.6).ignoresSafeArea())
        }

        private var pausedScreen: some View {
            VStack(spacing: 18) {
                NeonTitle(top: "PAUZĖ", bottom: nil)
                Button("TĘSTI") {
                    engine.resume()
                    withAnimation { phase = .race }
                }
                .buttonStyle(ArcadeButtonStyle(tint: Neon.magenta))
                .frame(maxWidth: 300)
                Button("Baigti važiavimą") {
                    engine.quit()
                    phase = .race
                }
                .buttonStyle(ArcadeButtonStyle(tint: .white, prominent: false))
                .frame(maxWidth: 300)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Neon.night.opacity(0.6).ignoresSafeArea())
        }
    }

    /// Neoninis dviejų eilučių pavadinimas.
    struct NeonTitle: View {
        let top: String
        let bottom: String?

        var body: some View {
            VStack(spacing: 2) {
                Text(top)
                    .foregroundStyle(.white)
                    .shadow(color: Neon.magenta, radius: 6)
                    .shadow(color: Neon.magenta, radius: 18)
                if let bottom {
                    Text(bottom)
                        .foregroundStyle(Neon.cyan)
                        .shadow(color: Neon.cyan, radius: 6)
                        .shadow(color: Neon.cyan, radius: 18)
                }
            }
            .font(.system(size: 46, weight: .black, design: .rounded))
            .italic()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
        }
    }

    struct SettingRow<Control: View>: View {
        let title: String
        let hint: String?
        @ViewBuilder let control: () -> Control

        var body: some View {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.subheadline, design: .rounded).weight(.semibold))
                    if let hint {
                        Text(hint).font(.caption2).foregroundStyle(Neon.amber)
                    }
                }
                Spacer(minLength: 4)
                control()
            }
            .padding(12)
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
        }
    }

    struct StatTile: View {
        let value: String
        let label: String

        var body: some View {
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
