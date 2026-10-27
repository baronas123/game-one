# Arkada – iOS žaidimų platforma

Viena iOS programėlė, kurioje gyvena **daug žaidimų**. Bendri dalykai (meniu, mygtukai,
vibracija, rekordų saugojimas, atsitiktiniai lygiai) parašyti vieną kartą `Core/` aplanke,
o kiekvienas žaidimas turi savo aplanką `Games/<Vardas>/`.

| Žaidimas | Esmė |
|---|---|
| **Planų Meistras** | Mėlyno brėžinio stiliaus galvosūkis: iš kambarių („45-1 / 6,75 m²“) sudėliok buto planą. Lygiai generuojami be galo, yra ir dienos iššūkis. Kai butas pilnas, uždedamas antspaudas „KOPIJA TIKRA“. |

## Įdiegti į iPhone – viena komanda (Mac)

```bash
git clone https://github.com/baronas123/game-one ~/game-one   # pirmą kartą
cd ~/game-one && git pull && ios/scripts/install_iphone.sh
```

Skriptas pats: įdiegia XcodeGen (jei reikia), sugeneruoja `Arkada.xcodeproj` iš `ios/project.yml`,
suranda tavo Apple Development komandą (tą pačią, kuria pasirašytas b-finance), sukompiliuoja,
įdiegia į prijungtą iPhone ir paleidžia. `ios/scripts/install_iphone.sh --sim` – tik patikrina, ar kompiliuojasi.

## Kaip paleisti

Reikia **Mac su Xcode 15+** arba **Swift Playgrounds** (iPad / Mac).

1. Atidaryk `ios/Arkada.swiftpm` (dukart spustelėjus atsidaro Xcode arba Playgrounds).
2. Pasirink iPhone simuliatorių ir spausk ▶︎ **Run**.
3. Jei nori paleisti savo iPhone: Xcode → *Signing & Capabilities* → pasirink savo Apple ID komandą.

Tai `.swiftpm` programėlės paketas, todėl `.xcodeproj` failo nėra ir jo nereikia.

## Struktūra

```
ios/
├── Arkada.swiftpm/              ← pati programėlė
│   ├── Package.swift            ← pavadinimas, ikona, bundle ID, iOS versija
│   ├── Arcade/                  ← pradžios ekranas su žaidimų kortelėmis (@main)
│   ├── Core/                    ← BENDRA infrastruktūra visiems žaidimams
│   │   ├── GameRegistry.swift   ← GameInfo + visų žaidimų sąrašas
│   │   ├── GameStorage.swift    ← rekordai/progresas, atskirti pagal žaidimą
│   │   ├── Haptics.swift        ← vibracijos signalai
│   │   ├── SeededRandom.swift   ← deterministinis RNG, dienos iššūkio „sėkla“
│   │   └── Components.swift     ← ✕ mygtukas, mygtukų stilius, ★★★, StatChip, 1:15 / 12,25 formatai
│   └── Games/
│       └── PlanuMeistras/       ← vienas žaidimas = vienas aplankas
├── templates/GameTemplate/      ← naujo žaidimo šablonas
└── scripts/new_game.sh          ← naujo žaidimo generatorius
```

## Naujas žaidimas per 10 sekundžių

```bash
ios/scripts/new_game.sh SpalvuGaudynes "Spalvų gaudynės"
```

Skriptas:
1. nukopijuoja šabloną į `Games/SpalvuGaudynes/`,
2. sugeneruoja ID `spalvu-gaudynes` (naudojamas rekordų raktams),
3. įrašo žaidimą į `Core/GameRegistry.swift`, ir jis iškart atsiranda Arkados meniu.

Šablone yra veikiantis mini žaidimas, kuris parodo, kaip naudoti `Core`. Jį gali iškart paleisti,
o tada perrašyti `Views/<Vardas>RootView.swift` savo žaidimu.

## Taisyklės (kad žaidimai netrukdytų vienas kitam)

1. **Vardų erdvė.** Visi žaidimai kompiliuojami į vieną Swift modulį, todėl kiekvieno žaidimo tipai
   rašomi `extension <Vardas> { … }` viduje. Tada `PlanuMeistras.Cell` ir `KitasZaidimas.Cell` nesikerta.
2. **Saugojimas tik per `GameStorage`.** Raktai automatiškai gauna `<žaidimo-id>.` priešdėlį.
   Žaidimo ID niekada nekeisk, nes kitaip žaidėjai praras progresą.
3. **Uždarymas.** Žaidimas atidaromas per visą ekraną, o grįžti į Arkadą galima per `GameCloseButton()`
   arba `@Environment(\.dismiss)`.
4. **Logika atskirai nuo UI.** Taisykles laikyk `Model/` aplanke (be `SwiftUI`), o vaizdus – `Views/` aplanke.
   Taip logiką lengva testuoti ir perkelti.
5. **Lietuviška sąsaja.** Tekstai lietuviški, skaičiai su kableliu (`12,25`), tam yra `Double.lt()`.
6. **Bendras kodas – į `Core/`.** Jei tas pats dalykas reikalingas dviem žaidimams, perkelk jį į `Core/`.
7. **Unikalūs failų vardai.** Viename modulyje du failai negali vadintis vienodai (pvz. du `RootView.swift`),
   todėl bendrus vardus rašyk su žaidimo priešdėliu: `Views/<Vardas>RootView.swift`.

## Ką galima pridėti vėliau

- App Store ikoną (dabar naudojama Playgrounds „placeholder“ ikona).
- Game Center lyderių lenteles (`Core/` lygyje, kad turėtų visi žaidimai).
- CI su `xcodebuild` macOS runner'iu.
