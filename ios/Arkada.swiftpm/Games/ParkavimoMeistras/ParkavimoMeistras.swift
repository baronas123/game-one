import SwiftUI

/// „Parkavimo meistras“ – vairuok tikrai fizikai paklūstančią mašiną ir pastatyk ją į vietą.
///
/// Visi šio žaidimo tipai gyvena `ParkavimoMeistras` vardų erdvėje,
/// kad nesusikirstų su kitais Arkados žaidimais.
enum ParkavimoMeistras {
    static let id = "parkavimo-meistras"
    static let storage = GameStorage(gameID: id)

    static let info = GameInfo(
        id: id,
        title: "Parkavimo meistras",
        tagline: "12 aikštelių nuo Gedimino prospekto iki požeminio garažo. Vairas, pedalai ir galinio vaizdo kamera.",
        symbol: "car.side.fill",
        tint: Color(red: 1.0, green: 0.76, blue: 0.1)
    ) {
        RootView()
    }
}
