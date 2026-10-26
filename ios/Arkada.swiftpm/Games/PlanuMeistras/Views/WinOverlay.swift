import SwiftUI

extension PlanuMeistras {

    /// Pergalės ekranas: ant plano trenkiamas „KOPIJA TIKRA“ antspaudas.
    struct WinOverlay: View {
        let engine: Engine
        let mode: Mode
        let onNext: () -> Void
        let onMenu: () -> Void

        @State private var stamped = false
        @State private var cardShown = false

        var body: some View {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()

                VStack(spacing: 28) {
                    Stamp()
                        .scaleEffect(stamped ? 1 : 2.6)
                        .opacity(stamped ? 1 : 0)
                        .rotationEffect(.degrees(stamped ? -12 : -30))

                    if cardShown {
                        card
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(24)
            }
            .task {
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { stamped = true }
                try? await Task.sleep(for: .milliseconds(180))
                Haptics.thud()
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { cardShown = true }
            }
        }

        private var card: some View {
            VStack(spacing: 16) {
                Text(engine.blueprint.title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("Planas atitinka natūrą. Inventorizatorius patenkintas.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                StarRow(stars: engine.stars)

                HStack(spacing: 8) {
                    StatChip(symbol: "stopwatch", text: engine.elapsedSeconds.clockText)
                    StatChip(symbol: "hand.draw", text: "\(engine.moves) ėj.")
                    StatChip(symbol: "lightbulb", text: "\(engine.hintsUsed)")
                }

                if case .level = mode {
                    Button("Kitas butas →", action: onNext)
                        .buttonStyle(ArcadeButtonStyle(tint: PlanuMeistras.info.tint))
                }
                Button("Į meniu", action: onMenu)
                    .buttonStyle(ArcadeButtonStyle(tint: PlanuMeistras.info.tint, prominent: false))
            }
            .padding(22)
            .frame(maxWidth: 380)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    /// Raudonas guminis antspaudas – kaip ant tikrų inventorizacijos bylų kopijų.
    struct Stamp: View {
        private var today: String {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: .now)
        }

        var body: some View {
            VStack(spacing: 4) {
                Text("KOPIJA TIKRA")
                    .font(.system(size: 34, weight: .black, design: .serif))
                    .tracking(2)
                Text("PLANŲ MEISTRAS · \(today)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(Palette.stamp)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.stamp, lineWidth: 4))
            .padding(5)
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.stamp, lineWidth: 1.5))
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 11))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            .accessibilityLabel("Kopija tikra")
        }
    }
}
