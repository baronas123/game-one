import SwiftUI

// Bendri UI komponentai, kad visi žaidimai atrodytų kaip viena šeima.

/// Apvalus „✕“ mygtukas – uždaro žaidimą ir grąžina į Arkados meniu.
/// Kai žaidimas paleistas kaip atskira programa (nėra iš kur grįžti), mygtukas nerodomas.
struct GameCloseButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented

    var body: some View {
        if isPresented { button }
    }

    private var button: some View {
        Button {
            Haptics.tap()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Uždaryti žaidimą")
    }
}

/// Pagrindinis didelis mygtukas.
struct ArcadeButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(prominent ? Color.white : tint)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.15)))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// ★★☆ įvertinimas.
struct StarRow: View {
    let stars: Int
    var maxStars = 3
    var size: CGFloat = 28
    @State private var shown = 0

    var body: some View {
        HStack(spacing: size * 0.25) {
            ForEach(0..<maxStars, id: \.self) { i in
                Image(systemName: i < shown ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(i < shown ? Color.yellow : Color.secondary)
                    .scaleEffect(i < shown ? 1 : 0.8)
            }
        }
        .task {
            shown = 0
            for i in 1...max(stars, 1) where i <= stars {
                try? await Task.sleep(for: .milliseconds(280))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { shown = i }
                Haptics.tap()
            }
        }
        .accessibilityLabel("\(stars) iš \(maxStars) žvaigždučių")
    }
}

/// Vieno rodiklio „plytelė“ (laikas, ėjimai...).
struct StatChip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

extension Int {
    /// 75 → „1:15“
    var clockText: String { String(format: "%d:%02d", self / 60, self % 60) }
}

extension Double {
    /// 12.25 → „12,25“ – lietuviškas dešimtainis kablelis.
    func lt(_ decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f", self).replacingOccurrences(of: ".", with: ",")
    }
}
