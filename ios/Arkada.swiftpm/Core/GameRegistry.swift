import SwiftUI

/// Žaidimo „vizitinė kortelė“ – viskas, ko reikia Arkados meniu.
///
/// Kiekvienas žaidimas `Games/<Vardas>/<Vardas>.swift` faile aprašo
/// `static let info = GameInfo(...)` ir yra įrašomas į `GameRegistry.all`.
struct GameInfo: Identifiable {
    /// Unikalus, nekintantis ID (naudojamas ir išsaugojimo raktams). Pvz. "planu-meistras".
    let id: String
    let title: String
    let tagline: String
    /// SF Symbol pavadinimas kortelės ikonai.
    let symbol: String
    let tint: Color
    /// Žaidimo pradinis ekranas. Uždaryti – `@Environment(\.dismiss)` arba `GameCloseButton()`.
    let makeRoot: () -> AnyView

    init(id: String, title: String, tagline: String, symbol: String, tint: Color,
         @ViewBuilder root: @escaping () -> some View) {
        self.id = id
        self.title = title
        self.tagline = tagline
        self.symbol = symbol
        self.tint = tint
        self.makeRoot = { AnyView(root()) }
    }

    var storage: GameStorage { GameStorage(gameID: id) }
}

enum GameRegistry {
    /// Meniu rodomi žaidimai. `install_iphone.sh --only <id>` palieka tik vieną (Info.plist `ArkadaOnlyGame`).
    static let all: [GameInfo] = {
        guard let only = Bundle.main.object(forInfoDictionaryKey: "ArkadaOnlyGame") as? String,
              !only.isEmpty else { return registered }
        return registered.filter { $0.id == only }
    }()

    /// Visi Arkados žaidimai šia tvarka.
    private static let registered: [GameInfo] = [
        PlanuMeistras.info,
        NaktinisGreitkelis.info,
        Sankryza.info,
        ParkavimoMeistras.info,
        LaisvasKaklas.info,
        // @registry — scripts/new_game.sh naujus žaidimus įrašo virš šios eilutės
    ]
}
