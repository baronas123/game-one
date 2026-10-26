import SwiftUI

/// „Sankryža“ – arkadinis eismo reguliuotojas: valdyk šviesoforus piko valandą.
///
/// Visi šio žaidimo tipai gyvena `Sankryza` vardų erdvėje,
/// kad nesusikirstų su kitais Arkados žaidimais.
enum Sankryza {
    static let id = "sankryza"
    static let storage = GameStorage(gameID: id)

    static let info = GameInfo(
        id: id,
        title: "Sankryža",
        tagline: "Valdyk šviesoforus piko valandą. Supurtyk telefoną – visi raudoni!",
        symbol: "car.2.fill",
        tint: Color(red: 0.18, green: 0.82, blue: 0.48)
    ) {
        RootView()
    }
}
