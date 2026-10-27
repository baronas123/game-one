import SwiftUI

/// Atskira programa „Laisvas kaklas“ – tas pats žaidimas kaip Arkadoje, tik be meniu.
/// Kodas bendras (`Arkada.swiftpm/Core` ir `Games`); šis failas – tik įėjimo taškas (project.yml).
@main
struct LaisvasKaklasApp: App {
    var body: some Scene {
        WindowGroup {
            LaisvasKaklas.RootView()
                .preferredColorScheme(.dark)
        }
    }
}
