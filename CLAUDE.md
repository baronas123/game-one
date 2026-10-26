# game-one

Arkada – žaidimų platforma.

- `ios/`: iOS programėlė (SwiftUI, `.swiftpm` app paketas, iOS 17+). Išsamiau – `ios/README.md`.
- `web/`: naršyklės versijos (vienas HTML failas be priklausomybių), kad žaidimą būtų galima išbandyti telefone be Xcode.

## Arkada – taisyklės kuriant žaidimus

- Naujas žaidimas kuriamas tik per `ios/scripts/new_game.sh <PascalVardas> "<Pavadinimas>"`.
  Skriptas nukopijuoja `ios/templates/GameTemplate` ir įrašo žaidimą į `Core/GameRegistry.swift`.
- Visi žaidimai yra viename Swift modulyje (`AppModule`). Kiekvieno žaidimo tipai rašomi
  `extension <Vardas> { … }` viduje. Globalių tipų ir funkcijų žaidimo aplanke nekurti.
- Kas bendra keliems žaidimams, keliauja į `ios/Arkada.swiftpm/Core/`. Kiekvienas žaidimas naudoja
  `GameStorage` (ne tiesiogiai `UserDefaults`), `Haptics`, `ArcadeButtonStyle`, `GameCloseButton`.
- Žaidimo `id` nekeičiamas, nes nuo jo priklauso išsaugotas progresas.
- Žaidimo logika – `Model/` (be SwiftUI), vaizdai – `Views/`.
- UI tekstai lietuviški; skaičiai su dešimtainiu kableliu (`Double.lt()`).
- Swift 5 kalbos režimas (`swift-tools-version: 5.9`). `@MainActor` žymėjimų venk, kad kodas
  kompiliuotųsi ir Xcode 15, ir Xcode 16.
- Šiame Linux konteineryje Swift/Xcode nėra, todėl SwiftUI kodo sukompiliuoti negalima.
  Algoritmus verta patikrinti atskirai (pvz. perrašius į JS ir paleidus `node`).
- Naršyklės versija (`web/<žaidimas>.html`) – vienas savarankiškas failas; žaidimo logika turi atitikti iOS versiją.
