import Foundation
import Observation

extension LaisvasKaklas {

    /// Vienas galvos padėties matavimas (iš `HeadTracker`), santykinis su neutralia padėtimi.
    struct HeadReading {
        var yaw: Double
        var pitch: Double
        var roll: Double
        var depthCm: Double
        var hasDepth: Bool
    }

    /// Patogi (be skausmo) judesio amplitudė kiekviena kryptimi.
    /// Numatytosios reikšmės atsargios – mažesnės už vidutinę sveiko suaugusiojo amplitudę.
    struct Calibration: Codable, Equatable {
        var yawRight = 45.0
        var yawLeft = 45.0
        var rollRight = 25.0
        var rollLeft = 25.0
        var pitchDown = 30.0
        var pitchUp = 20.0
        var depthBack = 1.6
        var measured = false

        func range(_ axis: TrackedAxis, side: Int) -> Double {
            switch axis {
            case .yaw: return side >= 0 ? yawRight : yawLeft
            case .roll: return side >= 0 ? rollRight : rollLeft
            case .pitch: return side >= 0 ? pitchDown : pitchUp
            case .depth: return depthBack
            case .none: return 1
            }
        }

        mutating func set(_ axis: TrackedAxis, side: Int, value: Double) {
            switch axis {
            case .yaw:
                let v = min(80, max(15, value))
                if side >= 0 { yawRight = v } else { yawLeft = v }
            case .roll:
                let v = min(45, max(10, value))
                if side >= 0 { rollRight = v } else { rollLeft = v }
            case .pitch:
                if side >= 0 { pitchDown = min(60, max(10, value)) } else { pitchUp = min(45, max(8, value)) }
            case .depth:
                depthBack = min(4, max(0.8, value))
            case .none:
                break
            }
        }
    }

    struct SessionRecord: Codable, Identifiable {
        var id = UUID()
        var date: Date
        var prePain: Int
        var postPain: Int?
        var completed: Bool
        var stopped: Bool
        var score: Int
        var maxScore: Int
    }

    enum PainWarning {
        case none
        /// Skausmas po mankštos padidėjo ≥ 2 balais.
        case rose
        /// Dvi sesijas iš eilės po mankštos skauda labiau nei prieš.
        case persistent

        var message: String {
            switch self {
            case .none: return ""
            case .rose:
                return "Po paskutinės mankštos skausmas padidėjo 2 ar daugiau balų. Kelias dienas pailsėk nuo šių pratimų. Jei skausmas nepraeina – pasitark su gydytoju ar kineziterapeutu."
            case .persistent:
                return "Jau dvi mankštos iš eilės po jų skauda labiau. Padaryk pertrauką ir pasitark su gydytoju ar kineziterapeutu."
            }
        }
    }

    /// Saugumo klausimyno rezultatas.
    enum Screening: Int {
        case notDone = 0
        case passed
        /// Skubiai į priėmimo skyrių / 112.
        case emergency
        /// Skubiai susisiekti su gydytoju.
        case urgent
        /// Pasitarti su gydytoju prieš pradedant.
        case consult
    }

    /// Progresas, kalibravimas, istorija ir nustatymai (UserDefaults per `GameStorage` raktus).
    @Observable
    final class Journal {
        private(set) var calibration: Calibration
        /// Taikinio dalis nuo kalibruotos amplitudės: pradžia 0,65, +0,05 po sėkmingos sesijos, ne daugiau 0,90.
        private(set) var level: Double
        private(set) var history: [SessionRecord]
        private(set) var screening: Screening
        private(set) var voiceOn: Bool
        private(set) var disabledExercises: Set<String>

        static let startLevel = 0.65
        static let maxLevel = 0.90
        static let minLevel = 0.60

        private let defaults = UserDefaults.standard

        private static func key(_ name: String) -> String { GameStorage.key(LaisvasKaklas.id, name) }

        init() {
            let d = UserDefaults.standard
            let decoder = JSONDecoder()
            if let data = d.data(forKey: Self.key("calibration")),
               let c = try? decoder.decode(Calibration.self, from: data) {
                calibration = c
            } else {
                calibration = Calibration()
            }
            if let data = d.data(forKey: Self.key("history")),
               let h = try? decoder.decode([SessionRecord].self, from: data) {
                history = h
            } else {
                history = []
            }
            let storedLevel = d.double(forKey: Self.key("level"))
            level = storedLevel > 0 ? storedLevel : Self.startLevel
            screening = Screening(rawValue: d.integer(forKey: Self.key("screening"))) ?? .notDone
            voiceOn = d.object(forKey: Self.key("voice")) as? Bool ?? true
            disabledExercises = Set(d.stringArray(forKey: Self.key("disabled")) ?? [])
        }

        // MARK: - Programa

        var enabledProgram: [Exercise] {
            Program.standard.filter { !disabledExercises.contains($0.id) }
        }

        func setExercise(_ id: String, enabled: Bool) {
            if enabled { disabledExercises.remove(id) } else { disabledExercises.insert(id) }
            // Bent vienas pratimas turi likti.
            if enabledProgram.isEmpty { disabledExercises.remove(id) }
            defaults.set(Array(disabledExercises), forKey: Self.key("disabled"))
        }

        func setVoice(_ on: Bool) {
            voiceOn = on
            defaults.set(on, forKey: Self.key("voice"))
        }

        // MARK: - Saugumas

        func setScreening(_ s: Screening) {
            screening = s
            defaults.set(s.rawValue, forKey: Self.key("screening"))
        }

        // MARK: - Kalibravimas

        func saveCalibration(_ c: Calibration) {
            calibration = c
            if let data = try? JSONEncoder().encode(c) {
                defaults.set(data, forKey: Self.key("calibration"))
            }
        }

        // MARK: - Istorija

        func record(_ r: SessionRecord) {
            history.append(r)
            if history.count > 120 { history.removeFirst(history.count - 120) }
            if let data = try? JSONEncoder().encode(history) {
                defaults.set(data, forKey: Self.key("history"))
            }
            // Progresija – tik po užbaigtos sesijos su įvertintu skausmu.
            guard r.completed, let post = r.postPain else { return }
            if post - r.prePain >= 2 {
                level = max(Self.minLevel, level - 0.05)
            } else if post <= r.prePain {
                level = min(Self.maxLevel, level + 0.05)
            }
            defaults.set(level, forKey: Self.key("level"))
        }

        var painWarning: PainWarning {
            let rated = history.filter { $0.postPain != nil }
            guard let last = rated.last, let lastPost = last.postPain else { return .none }
            if rated.count >= 2 {
                let prev = rated[rated.count - 2]
                if let prevPost = prev.postPain, lastPost > last.prePain, prevPost > prev.prePain {
                    return .persistent
                }
            }
            if lastPost - last.prePain >= 2 { return .rose }
            return .none
        }

        /// Kiek dienų iš eilės (iki šiandien arba vakar) atlikta bent viena užbaigta mankšta.
        var streak: Int {
            let cal = Calendar.current
            let days = Set(history.filter { $0.completed }.map { cal.startOfDay(for: $0.date) })
            var day = cal.startOfDay(for: Date())
            if !days.contains(day) {
                guard let y = cal.date(byAdding: .day, value: -1, to: day), days.contains(y) else { return 0 }
                day = y
            }
            var count = 0
            while days.contains(day) {
                count += 1
                guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
                day = prev
            }
            return count
        }

        var doneToday: Bool {
            let cal = Calendar.current
            return history.contains { $0.completed && cal.isDateInToday($0.date) }
        }

        /// Paskutinės 14 sesijų su įvertintu skausmu (diagramai).
        var recentPain: [SessionRecord] {
            Array(history.filter { $0.postPain != nil }.suffix(14))
        }
    }
}
