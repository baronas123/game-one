import SwiftUI

extension __NAME__ {

    /// Pradinis žaidimo ekranas. Pakeisk savo žaidimu – čia tik veikiantis pavyzdys,
    /// rodantis, kaip naudoti Core: GameCloseButton, Haptics, GameStorage, StarRow.
    struct RootView: View {
        @AppStorage(GameStorage.key(__NAME__.id, "best")) private var best = 0
        @State private var score = 0

        var body: some View {
            VStack(spacing: 24) {
                HStack {
                    GameCloseButton()
                    Spacer()
                    StatChip(symbol: "trophy", text: "\(best)")
                }

                Spacer()

                Text("__TITLE__")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))

                Text("\(score)")
                    .font(.system(size: 80, weight: .black, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())

                StarRow(stars: min(3, score / 10))
                    .id(score / 10)

                Button("Spausk!") {
                    Haptics.tap()
                    withAnimation { score += 1 }
                    __NAME__.storage.setIfHigher(score, for: "best")
                }
                .buttonStyle(ArcadeButtonStyle(tint: __NAME__.info.tint))

                Spacer()
            }
            .padding(20)
            .foregroundStyle(.white)
            .background(Color.black.ignoresSafeArea())
        }
    }
}
