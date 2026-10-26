import SwiftUI

extension PlanuMeistras {

    /// Žaidimo pradinis ekranas Arkadoje.
    struct MenuView: View {
        @AppStorage(GameStorage.key(PlanuMeistras.id, "unlocked")) private var unlocked = 1
        @State private var playing: Session?
        @State private var refresh = 0

        struct Session: Identifiable {
            let id = UUID()
            let mode: Mode
        }

        private var dailyStars: Int {
            _ = refresh
            return PlanuMeistras.storage.int("daily.\(LevelGenerator.dayKey())")
        }

        var body: some View {
            ZStack {
                BlueprintBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            GameCloseButton()
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Planų Meistras")
                                .font(.system(size: 38, weight: .heavy, design: .rounded))
                            Text("Inventorizatorius pametė planą. Sudėliok kambarius atgal – kiekvienas kvadratėlis turi būti savo vietoje.")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.75))
                        }

                        Button {
                            start(.level(unlocked))
                        } label: {
                            Label("Tęsti · Butas Nr. \(unlocked)", systemImage: "play.fill")
                        }
                        .buttonStyle(ArcadeButtonStyle(tint: PlanuMeistras.info.tint))

                        Button {
                            start(.daily)
                        } label: {
                            HStack {
                                Label("Dienos butas", systemImage: "calendar")
                                if dailyStars > 0 {
                                    Text(String(repeating: "★", count: dailyStars))
                                        .foregroundStyle(.yellow)
                                }
                            }
                        }
                        .buttonStyle(ArcadeButtonStyle(tint: .orange, prominent: false))

                        levels
                        howTo
                    }
                    .padding(20)
                }
            }
            .foregroundStyle(.white)
            .fullScreenCover(item: $playing, onDismiss: { refresh += 1 }) { session in
                GameView(mode: session.mode)
            }
        }

        private var levels: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("BUTAI")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(1...max(1, unlocked), id: \.self) { n in
                        let earned = stars(for: n)
                        Button {
                            start(.level(n))
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(n)")
                                    .font(.system(.headline, design: .monospaced))
                                Text(earned > 0 ? String(repeating: "★", count: earned) : "·")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.yellow)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(.white.opacity(n == unlocked ? 0.18 : 0.08),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.white.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        private var howTo: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("KAIP ŽAISTI")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Label("Tempk kambarį į plano kontūrą.", systemImage: "hand.draw")
                Label("Bakstelėk – kambarys pasisuka 90°.", systemImage: "rotate.right")
                Label("Užpildyk visą butą – gausi antspaudą.", systemImage: "checkmark.seal")
                Label("Be užuominų ir greitai – ★★★.", systemImage: "star")
            }
            .font(.callout)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        private func stars(for level: Int) -> Int {
            _ = refresh
            return PlanuMeistras.storage.int("stars.\(level)")
        }

        private func start(_ mode: Mode) {
            Haptics.tap()
            playing = Session(mode: mode)
        }
    }
}
