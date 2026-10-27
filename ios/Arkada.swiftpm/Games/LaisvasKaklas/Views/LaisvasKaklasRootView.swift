import SwiftUI

extension LaisvasKaklas {

    /// Pradžios ekranas: saugumas → dienos mankšta, serija, skausmo tendencija, nustatymai.
    struct RootView: View {
        @State private var journal = Journal()
        @State private var flow: FlowRequest?
        @State private var showSources = false

        struct FlowRequest: Identifiable {
            let id = UUID()
            let mode: FlowView.Mode
        }

        var body: some View {
            ZStack {
                LinearGradient(colors: [Palette.night, Color(red: 0.36, green: 0.22, blue: 0.42),
                                        Color(red: 0.92, green: 0.60, blue: 0.48)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                switch journal.screening {
                case .notDone:
                    VStack(spacing: 0) {
                        header
                        ScreeningView { result in
                            withAnimation { journal.setScreening(result) }
                        }
                    }
                case .passed:
                    home
                default:
                    VStack(spacing: 0) {
                        header
                        ScrollView {
                            BlockedView(screening: journal.screening) {
                                withAnimation { journal.setScreening(.notDone) }
                            }
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .fullScreenCover(item: $flow) { request in
                FlowView(journal: journal, mode: request.mode)
            }
            .sheet(isPresented: $showSources) {
                SourcesView()
            }
        }

        private var header: some View {
            HStack {
                GameCloseButton()
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }

        // MARK: - Pradžia

        private var home: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header.padding(.horizontal, -16)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Laisvas kaklas")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                        Text("~8 minučių kaklo ir pečių mankšta. Telefonas seka galvos judesius – tu tik lėtai judi ir kvėpuoji.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.8))
                        Text("Tai mankšta, ne gydymas.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.peach)
                    }

                    if journal.painWarning != PainWarning.none {
                        WarningBanner(text: journal.painWarning.message)
                    }

                    HStack(spacing: 10) {
                        statTile(value: "\(journal.streak)", label: "d. iš eilės", symbol: "flame.fill")
                        statTile(value: "\(Int((journal.level * 100).rounded())) %", label: "taikinio dydis", symbol: "scope")
                        statTile(value: journal.doneToday ? "✓" : "–", label: "šiandien", symbol: "sun.max.fill")
                    }

                    Button {
                        Haptics.tap()
                        flow = FlowRequest(mode: .session)
                    } label: {
                        Label(journal.doneToday ? "Dar kartą (~\(minutes) min)" : "Pradėti mankštą (~\(minutes) min)",
                              systemImage: "play.fill")
                    }
                    .buttonStyle(ArcadeButtonStyle(tint: LaisvasKaklas.info.tint))

                    painCard
                    programCard
                    settingsCard
                }
                .padding(16)
            }
        }

        private var minutes: Int {
            let seconds = journal.enabledProgram.reduce(0.0) { $0 + $1.estimatedSeconds + SessionEngine.introSeconds }
            return max(1, Int((seconds / 60).rounded()))
        }

        private func statTile(value: String, label: String, symbol: String) -> some View {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .foregroundStyle(Palette.peach)
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        private var painCard: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Skausmas (paskutinės 14)")
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 10) {
                        legend(color: .white.opacity(0.45), text: "prieš")
                        legend(color: Palette.peach, text: "po")
                    }
                    .font(.caption)
                }
                if journal.recentPain.isEmpty {
                    Text("Po pirmos mankštos čia matysi, kaip keičiasi skausmas.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    PainTrendChart(records: journal.recentPain)
                        .frame(height: 110)
                }
            }
            .padding(14)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }

        private func legend(color: Color, text: String) -> some View {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(text).foregroundStyle(.white.opacity(0.75))
            }
        }

        private var programCard: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Programa")
                    .font(.headline)
                ForEach(Program.standard) { ex in
                    Toggle(isOn: Binding(
                        get: { !journal.disabledExercises.contains(ex.id) },
                        set: { journal.setExercise(ex.id, enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name)
                            Text(ex.why)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Palette.calm)
                }
                Button {
                    showSources = true
                } label: {
                    Label("Kodėl šie pratimai?", systemImage: "book.closed")
                        .font(.callout.weight(.semibold))
                }
                .foregroundStyle(Palette.peach)
            }
            .padding(14)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }

        private var settingsCard: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nustatymai")
                    .font(.headline)
                Toggle("Balso užuominos (jei yra lietuviškas balsas)", isOn: Binding(
                    get: { journal.voiceOn },
                    set: { journal.setVoice($0) }
                ))
                .tint(Palette.calm)
                Button {
                    flow = FlowRequest(mode: .calibrationOnly)
                } label: {
                    Label("Iš naujo išmatuoti patogias ribas", systemImage: "ruler")
                }
                Button {
                    journal.setScreening(.notDone)
                } label: {
                    Label("Pakartoti saugumo klausimyną", systemImage: "checklist")
                }
                Text("Kameros vaizdas apdorojamas tik telefone – niekur nesaugomas ir nesiunčiamas.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .font(.callout)
            .padding(14)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
