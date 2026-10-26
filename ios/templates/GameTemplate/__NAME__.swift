import SwiftUI

/// __TITLE__ – trumpai aprašyk žaidimo idėją čia.
///
/// Visi šio žaidimo tipai rašomi `extension __NAME__ { ... }` viduje,
/// kad nesusikirstų su kitų Arkados žaidimų pavadinimais.
enum __NAME__ {
    static let id = "__ID__"
    static let storage = GameStorage(gameID: id)

    static let info = GameInfo(
        id: id,
        title: "__TITLE__",
        tagline: "Vienas sakinys, kuo šis žaidimas įdomus.",
        symbol: "sparkles",
        tint: .purple
    ) {
        RootView()
    }
}
