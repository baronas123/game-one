import UIKit

/// Bendri vibracijos (haptic) signalai visiems žaidimams.
/// Galima kviesti iš bet kurios vietos – patys persijungia į pagrindinę giją.
enum Haptics {
    static func tap() { run { UIImpactFeedbackGenerator(style: .light).impactOccurred() } }
    static func place() { run { UIImpactFeedbackGenerator(style: .medium).impactOccurred() } }
    static func thud() { run { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() } }
    static func success() { run { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func error() { run { UINotificationFeedbackGenerator().notificationOccurred(.error) } }

    private static func run(_ body: @escaping @MainActor () -> Void) {
        Task { @MainActor in body() }
    }
}
