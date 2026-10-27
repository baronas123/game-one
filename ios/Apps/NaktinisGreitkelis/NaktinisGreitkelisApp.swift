import SwiftUI

/// Atskira programa „Naktinis greitkelis“ – tas pats žaidimas kaip Arkadoje, tik be meniu.
/// Kodas bendras (`Arkada.swiftpm/Core` ir `Games`); šis failas – tik įėjimo taškas (project.yml).
@main
struct NaktinisGreitkelisApp: App {
    var body: some Scene {
        WindowGroup {
            NaktinisGreitkelis.RootView()
                .preferredColorScheme(.dark)
        }
    }
}
