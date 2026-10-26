import Foundation

extension LaisvasKaklas {

    enum ExerciseKind {
        /// Lėtas judesys iki taikinio, trumpas išlaikymas, grįžimas.
        case reach
        /// Raumens įtempimas nejudant (delnu spaudžiama, galva lieka vietoje).
        case isometric
        /// Laikmačio ritmu vedamas judesys (kamera pečių nemato).
        case rhythm
        /// Švelnus, ilgas tempimas su kvėpavimu.
        case stretch
    }

    enum TrackedAxis {
        case yaw, pitch, roll, depth, none
    }

    /// Vienas pratimas. Visa programa – `Program.standard`; dozes keisti čia.
    struct Exercise: Identifiable {
        let id: String
        let name: String
        let instruction: String
        let why: String
        let kind: ExerciseKind
        let axis: TrackedAxis
        /// Kartojimų iš viso (kai pakaitomis – abi pusės kartu).
        let reps: Int
        /// Išlaikymas taikinyje (s). `rhythm` – vieno kartojimo trukmė.
        let holdSeconds: Double
        /// Mažiausia judesio iki taikinio trukmė (s) – greičiau = „lėčiau“ užuomina.
        let minMoveSeconds: Double
        let alternateSides: Bool
        /// Taikinio dalis nuo (kalibruota amplitudė × dabartinis lygis).
        let rangeFraction: Double
        /// Galvos atlošimui (pitch < 0) taikinys papildomai mažinamas – atsargumas.
        let extensionFactor: Double
        /// Kita ašis turi likti rami (pvz. smakro įtraukimas – nelinkčioti).
        let guardAxis: TrackedAxis
        let guardLimitDegrees: Double
        let guardHint: String
        /// `isometric` – kryptys pakaitomis; `rhythm` – fazių užuominos vieno kartojimo metu.
        let cues: [String]

        init(id: String, name: String, instruction: String, why: String, kind: ExerciseKind,
             axis: TrackedAxis, reps: Int, holdSeconds: Double, minMoveSeconds: Double = 0,
             alternateSides: Bool = false, rangeFraction: Double = 1, extensionFactor: Double = 1,
             guardAxis: TrackedAxis = .none, guardLimitDegrees: Double = 0, guardHint: String = "",
             cues: [String] = []) {
            self.id = id
            self.name = name
            self.instruction = instruction
            self.why = why
            self.kind = kind
            self.axis = axis
            self.reps = reps
            self.holdSeconds = holdSeconds
            self.minMoveSeconds = minMoveSeconds
            self.alternateSides = alternateSides
            self.rangeFraction = rangeFraction
            self.extensionFactor = extensionFactor
            self.guardAxis = guardAxis
            self.guardLimitDegrees = guardLimitDegrees
            self.guardHint = guardHint
            self.cues = cues
        }

        /// Apytikslė trukmė sekundėmis (sąrašui rodyti).
        var estimatedSeconds: Double {
            switch kind {
            case .reach: return Double(reps) * (holdSeconds + max(minMoveSeconds, 2) * 2 + 0.5)
            case .isometric: return Double(reps) * (holdSeconds + 5.5)
            case .rhythm: return Double(reps) * holdSeconds
            case .stretch: return Double(reps) * (holdSeconds + 6)
            }
        }
    }

    /// Mankštos programa pagal: Cochrane apžvalgą (Gross ir kt., 2015) – kaklo ir mentių stiprinimas
    /// bei tempimo + stiprinimo derinys; JOSPT gaires (2017); NHS lankstinukus (lėtai, iki patogios
    /// ribos, 10–20 kartojimų); Andersen ir kt. (2013) – mentių funkcijos pratimai.
    /// Dozės atsargios (asmeniniam naudojimui, be kineziterapeuto priežiūros).
    enum Program {
        static let standard: [Exercise] = [
            Exercise(
                id: "smakras",
                name: "Smakro įtraukimas",
                instruction: "Žiūrėk tiesiai. Lėtai trauk smakrą tiesiai atgal, lyg darytum „antrą smakrą“. Galvos nelenk.",
                why: "Stiprina giliuosius kaklo lenkiamuosius raumenis, kurie palaiko galvą, ir mažina „galvos į priekį“ laikyseną.",
                kind: .reach, axis: .depth, reps: 8, holdSeconds: 4, minMoveSeconds: 1.5,
                guardAxis: .pitch, guardLimitDegrees: 12,
                guardHint: "Nelenk galvos – smakrą trauk tiesiai atgal"
            ),
            Exercise(
                id: "pasukimai",
                name: "Galvos pasukimai",
                instruction: "Lėtai pasuk galvą į šoną, kiek patogu, ir grįžk. Pakaitomis į kairę ir į dešinę.",
                why: "Palaiko kaklo judrumą. Lėtas, kontroliuojamas judesys – be trūkčiojimų.",
                kind: .reach, axis: .yaw, reps: 12, holdSeconds: 1.5, minMoveSeconds: 2,
                alternateSides: true,
                guardAxis: .roll, guardLimitDegrees: 15,
                guardHint: "Tik pasuk – nelenk galvos į šoną"
            ),
            Exercise(
                id: "ausis",
                name: "Ausis link peties",
                instruction: "Lėtai lenk ausį link peties, galvos nesukdamas. Pečiai lieka nuleisti. Pakaitomis.",
                why: "Judina ir švelniai tempia šoninius kaklo raumenis.",
                kind: .reach, axis: .roll, reps: 12, holdSeconds: 1.5, minMoveSeconds: 2,
                alternateSides: true,
                guardAxis: .yaw, guardLimitDegrees: 15,
                guardHint: "Nesuk galvos – tik lenk ausį link peties"
            ),
            Exercise(
                id: "linktelejimai",
                name: "Linktelėjimai",
                instruction: "Lėtai nuleisk smakrą link krūtinės, tada švelniai pakelk – atgal tik nedaug. Pakaitomis.",
                why: "Palaiko lenkimo ir tiesimo judrumą. Atlošimas ribotas – tai saugiau.",
                kind: .reach, axis: .pitch, reps: 6, holdSeconds: 1.5, minMoveSeconds: 2,
                alternateSides: true, extensionFactor: 0.5
            ),
            Exercise(
                id: "izometrija",
                name: "Izometrija",
                instruction: "Delnu švelniai (~30 % jėgos) spausk galvą, o galva priešinasi ir nejuda.",
                why: "Stiprina kaklo raumenis be judesio – vienas geriausiai ištirtų kaklo pratimų tipų.",
                kind: .isometric, axis: .none, reps: 8, holdSeconds: 5,
                cues: [
                    "Delnas ant kaktos – spausk į priekį",
                    "Delnas ant dešiniojo smilkinio",
                    "Delnas ant kairiojo smilkinio",
                    "Delnai už pakaušio – spausk atgal"
                ]
            ),
            Exercise(
                id: "mentes",
                name: "Mentių suspaudimas",
                instruction: "Pečius atitrauk atgal ir žemyn, suspausk mentes, išlaikyk, atpalaiduok.",
                why: "Stiprina mentes laikančius raumenis (apatinę trapecijos dalį) – mažina kaklo ir pečių įtampą.",
                kind: .rhythm, axis: .none, reps: 8, holdSeconds: 5,
                cues: ["Pečiai atgal ir žemyn – suspausk mentes", "Išlaikyk ir kvėpuok", "Atpalaiduok"]
            ),
            Exercise(
                id: "peciu-ratai",
                name: "Pečių ratai",
                instruction: "Lėtai kelk pečius į viršų, sukdamas juos ratu atgal, ir nuleisk.",
                why: "Atpalaiduoja pečių juostą ir gerina kraujotaką po sėdimo darbo.",
                kind: .rhythm, axis: .none, reps: 6, holdSeconds: 4,
                cues: ["Kelk pečius į viršų", "Ratu atgal", "Nuleisk ir atpalaiduok"]
            ),
            Exercise(
                id: "trapecija",
                name: "Trapecijos tempimas",
                instruction: "Lenk ausį link peties, kol pajusi švelnų tempimą. Ranka gali lengvai prilaikyti – netempk jėga.",
                why: "Ramus tempimas pabaigai. Vien tempimas mažai padeda – todėl jis eina po stiprinimo pratimų.",
                kind: .stretch, axis: .roll, reps: 2, holdSeconds: 25,
                alternateSides: true, rangeFraction: 0.9
            )
        ]
    }
}
