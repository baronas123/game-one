import Foundation
import Observation

extension LaisvasKaklas {

    /// Patogios amplitudės matavimas: „pasuk tiek, kiek patogu, be skausmo“.
    /// Taikiniai mankštoje = šios amplitudės dalis (pradžioje 65 %).
    @Observable
    final class CalibrationEngine {
        struct Step {
            let axis: TrackedAxis
            let side: Int
            let title: String
            let instruction: String
        }

        enum Stage: Equatable {
            case neutral
            case measure(Int)
            case pause(Int)
            case done
        }

        static let measureSeconds = 6.0
        static let pauseSeconds = 2.5
        static let neutralSeconds = 3.0

        let steps: [Step]
        private(set) var stage: Stage = .neutral
        private(set) var progress: Double = 0
        /// Dabartinė reikšmė matuojama kryptimi (laipsniai / cm).
        private(set) var liveValue: Double = 0
        private(set) var bestValue: Double = 0
        private(set) var result: Calibration
        private(set) var sawFace = false

        @ObservationIgnored private var stageStart: Double?
        @ObservationIgnored private var lastTime: Double?
        @ObservationIgnored private var neutralRequested = false

        init(hasDepth: Bool, start: Calibration) {
            var s: [Step] = [
                Step(axis: .yaw, side: 1, title: "Pasukimas į dešinę",
                     instruction: "Lėtai pasuk galvą į dešinę tiek, kiek patogu, be skausmo. Palaikyk ir grįžk."),
                Step(axis: .yaw, side: -1, title: "Pasukimas į kairę",
                     instruction: "Dabar – į kairę. Tik tiek, kiek patogu."),
                Step(axis: .roll, side: 1, title: "Ausis link dešiniojo peties",
                     instruction: "Lenk dešinę ausį link peties, galvos nesukdamas. Be skausmo."),
                Step(axis: .roll, side: -1, title: "Ausis link kairiojo peties",
                     instruction: "Dabar kairę ausį link kairiojo peties."),
                Step(axis: .pitch, side: 1, title: "Smakras žemyn",
                     instruction: "Lėtai nuleisk smakrą link krūtinės, kiek patogu."),
                Step(axis: .pitch, side: -1, title: "Galva atgal",
                     instruction: "Švelniai ir nedaug pakelk galvą atgal. Jei svaigsta – sustok.")
            ]
            if hasDepth {
                s.append(Step(axis: .depth, side: 1, title: "Smakro įtraukimas",
                              instruction: "Žiūrėdamas tiesiai trauk smakrą atgal („antras smakras“), kiek patogu."))
            }
            steps = s
            var r = start
            r.measured = false
            result = r
        }

        var isDone: Bool { stage == .done }

        var currentStep: Step? {
            switch stage {
            case .measure(let i), .pause(let i):
                return i >= 0 && i < steps.count ? steps[i] : nil
            default:
                return nil
            }
        }

        /// Vaizdas iškviečia `HeadTracker.calibrateNeutral()`, kai grąžinama `true`.
        func consumeNeutralRequest() -> Bool {
            let r = neutralRequested
            neutralRequested = false
            return r
        }

        func update(now: Double, reading: HeadReading?) {
            if stageStart == nil { stageStart = now }
            let dt = min(0.1, max(0, now - (lastTime ?? now)))
            lastTime = now
            if reading != nil { sawFace = true }

            switch stage {
            case .done:
                return

            case .neutral:
                // Laikmatis eina tik matant veidą – neutrali padėtis turi būti tikra.
                if reading != nil {
                    progress = min(1, progress + dt / Self.neutralSeconds)
                }
                if progress >= 1 {
                    neutralRequested = true
                    stage = .pause(-1)
                    stageStart = now
                    progress = 0
                }

            case .measure(let i):
                guard i < steps.count else {
                    finish()
                    return
                }
                let step = steps[i]
                if let r = reading {
                    let v = value(step.axis, r) * Double(step.side)
                    liveValue = max(0, v)
                    bestValue = max(bestValue, v)
                }
                let t = now - (stageStart ?? now)
                progress = min(1, t / Self.measureSeconds)
                if t >= Self.measureSeconds {
                    // Per mažas judesys (ar nematytas veidas) – paliekam atsargią numatytąją reikšmę.
                    let minimum = step.axis == .depth ? 0.5 : 6.0
                    if bestValue >= minimum {
                        result.set(step.axis, side: step.side, value: bestValue)
                    }
                    stage = .pause(i)
                    stageStart = now
                    progress = 0
                }

            case .pause(let i):
                let t = now - (stageStart ?? now)
                progress = min(1, t / Self.pauseSeconds)
                if t >= Self.pauseSeconds {
                    let next = i + 1
                    if next < steps.count {
                        stage = .measure(next)
                        stageStart = now
                        progress = 0
                        bestValue = 0
                        liveValue = 0
                    } else {
                        finish()
                    }
                }
            }
        }

        /// Praleisti – lieka atsargios numatytosios reikšmės (kalibruoti galima vėliau nustatymuose).
        func skipAll() {
            finish()
        }

        /// `measured` reiškia „kalibravimo žingsnis atliktas arba praleistas“ – kad nebūtų klausiama kaskart.
        private func finish() {
            result.measured = true
            stage = .done
        }

        private func value(_ axis: TrackedAxis, _ r: HeadReading) -> Double {
            switch axis {
            case .yaw: return r.yaw
            case .pitch: return r.pitch
            case .roll: return r.roll
            case .depth: return r.depthCm
            case .none: return 0
            }
        }
    }
}
