import SwiftUI

/// „Naktinis greitkelis“ – pseudo-3D naktinės lenktynės Vilnius → Klaipėda.
///
/// Spėk iki kito miesto, kol nesibaigė laikas: lenk mašinas, rink nitro balionus.
/// Valdymas – telefono polinkiu (arba lietimu), nitro – purtant arba mygtuku,
/// o priekinė kamera rodo tavo veidą galinio vaizdo veidrodėlyje.
/// Visi šio žaidimo tipai rašomi `extension NaktinisGreitkelis { ... }` viduje.
enum NaktinisGreitkelis {
    static let id = "naktinis-greitkelis"
    static let storage = GameStorage(gameID: id)

    static let info = GameInfo(
        id: id,
        title: "Naktinis greitkelis",
        tagline: "Neoninės lenktynės Vilnius → Klaipėda. Vairuok pakreipdamas telefoną.",
        symbol: "car.rear.road.lane",
        tint: Color(red: 1.0, green: 0.24, blue: 0.65)
    ) {
        RootView()
    }
}
