import SwiftUI

/// Arkados pradžios ekranas – visų žaidimų kortelės iš `GameRegistry`.
struct ArcadeHomeView: View {
    @State private var playing: GameInfo?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(GameRegistry.all) { game in
                        Button {
                            Haptics.tap()
                            playing = game
                        } label: {
                            GameCard(game: game)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Daugiau žaidimų – netrukus")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding(16)
            }
            .background(
                LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.16), .black],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .navigationTitle("Arkada")
        }
        .fullScreenCover(item: $playing) { game in
            game.makeRoot()
        }
    }
}

private struct GameCard: View {
    let game: GameInfo

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: game.symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(game.tint.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(game.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.fill")
                .foregroundStyle(game.tint)
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(game.tint.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
