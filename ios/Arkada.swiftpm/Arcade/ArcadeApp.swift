import SwiftUI

@main
struct ArcadeApp: App {
    var body: some Scene {
        WindowGroup {
            ArcadeHomeView()
                .preferredColorScheme(.dark)
        }
    }
}
