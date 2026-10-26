import SwiftUI

/// „Laisvas kaklas“ – kaklo ir pečių mankšta, kurioje telefonas seka galvos judesius.
///
/// Programa paremta Cochrane (2015), JOSPT (2017) ir NHS rekomendacijomis; dozės atsargios.
/// Tai mankšta, ne gydymas. Visi šio žaidimo tipai – `LaisvasKaklas` vardų erdvėje.
enum LaisvasKaklas {
    static let id = "laisvas-kaklas"
    static let storage = GameStorage(gameID: id)

    static let info = GameInfo(
        id: id,
        title: "Laisvas kaklas",
        tagline: "8 min. kaklo ir pečių mankšta. Telefonas seka galvos judesius.",
        symbol: "figure.mind.and.body",
        tint: Color(red: 0.93, green: 0.52, blue: 0.40)
    ) {
        RootView()
    }
}
