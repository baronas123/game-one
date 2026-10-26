import SwiftUI

extension LaisvasKaklas {

    /// Vienos mankštos eiga: skausmas prieš → (kalibravimas) → mankšta → skausmas po → santrauka.
    struct FlowView: View {
        enum Mode { case session, calibrationOnly }

        let journal: Journal
        let mode: Mode

        @Environment(\.dismiss) private var dismiss
        @State private var tracker = HeadTracker()
        @State private var stage: Stage = .prePain
        @State private var prePain = 0
        @State private var engine: SessionEngine?
        @State private var record: SessionRecord?
        @State private var levelBefore = 0.0

        enum Stage: Equatable {
            case prePain, calibrate, session, postPain, summary, stopped
        }

        init(journal: Journal, mode: Mode) {
            self.journal = journal
            self.mode = mode
            _stage = State(initialValue: mode == .calibrationOnly ? Stage.calibrate : Stage.prePain)
        }

        var body: some View {
            ZStack {
                LinearGradient(colors: [Palette.night, Color(red: 0.30, green: 0.20, blue: 0.42)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                content
                    .transition(.opacity)

                if stage != .session {
                    VStack {
                        HStack {
                            GameCloseButton()
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(16)
                }
            }
            .foregroundStyle(.white)
            .animation(.easeInOut(duration: 0.3), value: stage)
            .onAppear {
                tracker.start()
                levelBefore = journal.level
            }
            .onDisappear { tracker.stop() }
        }

        @ViewBuilder
        private var content: some View {
            switch stage {
            case .prePain:
                PainCheckView(title: "Kaip jaučiasi kaklas dabar?",
                              subtitle: "0 – visai neskauda, 10 – stipriausias įsivaizduojamas skausmas.",
                              initial: journal.history.last?.postPain ?? 2,
                              buttonTitle: "Pradėti mankštą") { value in
                    prePain = value
                    if value >= 8 {
                        stage = .stopped
                    } else {
                        stage = journal.calibration.measured ? .session : .calibrate
                    }
                }
            case .calibrate:
                CalibrationView(tracker: tracker, start: journal.calibration) { result in
                    journal.saveCalibration(result)
                    if mode == .calibrationOnly {
                        dismiss()
                    } else {
                        stage = .session
                    }
                }
            case .session:
                if let e = engine {
                    SessionView(tracker: tracker, engine: e, voiceOn: journal.voiceOn,
                                onFinish: { stage = .postPain },
                                onStop: { stopSession() })
                } else {
                    Color.clear.onAppear {
                        engine = SessionEngine(exercises: journal.enabledProgram,
                                               calibration: journal.calibration,
                                               level: journal.level)
                    }
                }
            case .postPain:
                PainCheckView(title: "O dabar?",
                              subtitle: "Įvertink skausmą po mankštos – taip matysi, ar pratimai tau tinka.",
                              initial: prePain,
                              buttonTitle: "Išsaugoti") { value in
                    let e = engine
                    let r = SessionRecord(date: Date(), prePain: prePain, postPain: value, completed: true,
                                          stopped: false,
                                          score: Int((e?.score ?? 0).rounded()),
                                          maxScore: Int(e?.maxScore ?? 0))
                    journal.record(r)
                    record = r
                    stage = .summary
                }
            case .summary:
                if let r = record {
                    SummaryView(record: r, journal: journal, levelBefore: levelBefore) { dismiss() }
                }
            case .stopped:
                if prePain >= 8 && engine == nil {
                    highPainView
                } else {
                    StopGuidanceView { dismiss() }
                }
            }
        }

        private var highPainView: some View {
            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Palette.warn)
                Text("Šiandien geriau pailsėk")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("Kai skauda labai stipriai, mankšta gali pabloginti. Pailsėk, o jei stiprus skausmas laikosi ilgiau nei kelias dienas ar plinta į ranką – kreipkis į gydytoją.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Supratau") { dismiss() }
                    .buttonStyle(ArcadeButtonStyle(tint: LaisvasKaklas.info.tint))
                Spacer()
            }
            .padding(20)
        }

        private func stopSession() {
            let e = engine
            journal.record(SessionRecord(date: Date(), prePain: prePain, postPain: nil, completed: false,
                                         stopped: true,
                                         score: Int((e?.score ?? 0).rounded()),
                                         maxScore: Int(e?.maxScore ?? 0)))
            tracker.stop()
            stage = .stopped
        }
    }

    /// Skausmo įvertinimas 0–10 (skaitinė skausmo skalė).
    struct PainCheckView: View {
        let title: String
        let subtitle: String
        let initial: Int
        let buttonTitle: String
        let onDone: (Int) -> Void

        @State private var value: Int?

        var body: some View {
            VStack(spacing: 20) {
                Spacer()
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))

                let current = value ?? initial
                Text("\(current)")
                    .font(.system(size: 72, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(color(current))
                    .contentTransition(.numericText())

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(0...10, id: \.self) { n in
                        Button {
                            Haptics.tap()
                            withAnimation { value = n }
                        } label: {
                            Text("\(n)")
                                .font(.system(.headline, design: .rounded).monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(n == current ? color(n) : Color.white.opacity(0.08))
                                )
                                .foregroundStyle(n == current ? Palette.ink : Color.white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Skausmas \(n) iš 10")
                    }
                }

                Spacer()
                Button(buttonTitle) {
                    Haptics.tap()
                    onDone(current)
                }
                .buttonStyle(ArcadeButtonStyle(tint: LaisvasKaklas.info.tint))
                Text("Tai mankšta, ne gydymas.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(20)
        }

        private func color(_ n: Int) -> Color {
            if n <= 3 { return Palette.calm }
            if n <= 6 { return Palette.gold }
            return Palette.warn
        }
    }

    /// Santrauka po mankštos.
    struct SummaryView: View {
        let record: SessionRecord
        let journal: Journal
        let levelBefore: Double
        let onClose: () -> Void

        private var stars: Int {
            guard record.maxScore > 0 else { return 1 }
            let f = Double(record.score) / Double(record.maxScore)
            return f >= 0.9 ? 3 : (f >= 0.65 ? 2 : 1)
        }

        var body: some View {
            ScrollView {
                VStack(spacing: 18) {
                    Text("Laisvas kaklas ✓")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .padding(.top, 50)
                    StarRow(stars: stars)
                    Text("Ramumo taškai: \(record.score) iš \(record.maxScore)")
                        .font(.headline)
                    HStack(spacing: 8) {
                        StatChip(symbol: "flame.fill", text: "\(journal.streak) d. iš eilės")
                        StatChip(symbol: "waveform.path.ecg", text: "Skausmas \(record.prePain) → \(record.postPain ?? record.prePain)")
                    }
                    Text(levelMessage)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.8))
                    if journal.painWarning != PainWarning.none {
                        WarningBanner(text: journal.painWarning.message)
                    }
                    Text("Geriausia – 1–2 kartus per dieną, kasdien. Tai mankšta, ne gydymas.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.6))
                    Button("Baigti", action: onClose)
                        .buttonStyle(ArcadeButtonStyle(tint: LaisvasKaklas.info.tint))
                }
                .padding(20)
            }
        }

        private var levelMessage: String {
            let before = Int((levelBefore * 100).rounded())
            let after = Int((journal.level * 100).rounded())
            if after > before {
                return "Kitą kartą taikiniai bus šiek tiek toliau: \(after) % tavo patogios ribos."
            } else if after < before {
                return "Skausmas padidėjo – kitą kartą taikiniai arčiau: \(after) % patogios ribos."
            }
            return "Taikiniai lieka \(after) % tavo patogios ribos."
        }
    }

    struct WarningBanner: View {
        let text: String

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warn)
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.warn.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.warn.opacity(0.5), lineWidth: 1))
        }
    }
}
