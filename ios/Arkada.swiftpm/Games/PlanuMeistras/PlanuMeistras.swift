import SwiftUI

/// „Planų Meistras“ – sudėliok butą iš kambarių kaip dėlionę.
///
/// Visi šio žaidimo tipai gyvena `PlanuMeistras` vardų erdvėje,
/// kad nesusikirstų su kitais Arkados žaidimais.
enum PlanuMeistras {
    static let id = "planu-meistras"
    static let storage = GameStorage(gameID: id)

    static let info = GameInfo(
        id: id,
        title: "Planų Meistras",
        tagline: "Sudėliok butą iš kambarių. Kiekvienas kvadratas – 2,25 m².",
        symbol: "square.split.bottomrightquarter",
        tint: Color(red: 0.16, green: 0.42, blue: 0.95)
    ) {
        MenuView()
    }
}
