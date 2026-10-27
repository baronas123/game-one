import Foundation
import Observation

extension LaisvasKaklas {

    /// Sėkmingo kartojimo „žiežirbos“ (piešiamos scenoje).
    struct Burst {
        let time: Double
        /// -1 kairė, 1 dešinė, 0 centras.
        let side: Int
    }

    /// Mankštos sesijos logika – be UI. Kviečiama ~30 k/s iš `SessionView`.
    ///
    /// Taškai skiriami už lėtą, kontroliuojamą judesį, išlaikymą ir ramumą – niekada už greitį
    /// ar didžiausią amplitudę. Kai veido nesimato (ar ašis nepalaikoma), pratimas tęsiamas
    /// laikmačio režimu.
    @Observable
    final class SessionEngine {
        enum Phase: Equatable { case intro, active, finished }
        /// Kartojimo žingsnis (pagal jį 3D treneris rodo, ką daryti dabar).
        enum RepStage: Equatable { case approach, hold, returning, prepare, press, rest, rhythm }

        let exercises: [Exercise]
        let calibration: Calibration
        let level: Double

        private(set) var phase: Phase = .intro
        private(set) var index = 0
        private(set) var repIndex = 0
        private(set) var cue = ""
        /// Švelni pastaba (pvz. „Lėčiau“), rodoma kelias sekundes.
        private(set) var warning = ""
        private(set) var holdProgress: Double = 0
        /// Izometrija: laukiama, kol pasakysi, kad delnas jau vietoje.
        private(set) var waitingForReady = false
        /// Dabartinė padėtis, padalyta iš taikinio dydžio (taikinys = ±1).
        private(set) var valueNorm: Double = 0
        /// Kuriose pusėse rodyti taikinius: [1], [-1], [1, -1] arba [] (centras).
        private(set) var targetSides: [Int] = []
        private(set) var isHolding = false
        private(set) var guided = false
        private(set) var score: Double = 0
        private(set) var successCount = 0
        private(set) var bursts: [Burst] = []
        /// Isometrijos metu – kiek laipsnių galva pajudėjo nuo pradžios.
        private(set) var stillDeviation: Double = 0
        private(set) var announcement = ""
        private(set) var announcementID = 0
        private(set) var skippedCount = 0

        /// Įžanga trunka, kol paspausi „Pradėti“; tai – tik apytikslė trukmė viso laiko skaičiavimui.
        static let introSeconds = 12.0
        static let graceSeconds = 1.5

        @ObservationIgnored private var started = false
        /// Dabartinės fazės (įžangos ar pratimo) pradžia – trenerio demonstracijai.
        @ObservationIgnored private(set) var phaseStart: Double = 0
        @ObservationIgnored private var stepStart: Double = 0
        @ObservationIgnored private(set) var stage: RepStage = .approach
        @ObservationIgnored private(set) var stageStart: Double = 0
        @ObservationIgnored private var lockedSide: Int?
        @ObservationIgnored private var expectedSide: Int?
        @ObservationIgnored private var lastSide: Int?
        @ObservationIgnored private var moveStart: Double?
        @ObservationIgnored private var holdAccum: Double = 0
        @ObservationIgnored private var lastTime: Double?
        @ObservationIgnored private var lastSeen: Double = 0
        @ObservationIgnored private var repScore: Double = 1
        @ObservationIgnored private var warnUntil: Double = 0
        @ObservationIgnored private var baseline: HeadReading?
        @ObservationIgnored private var maxDeviation: Double = 0
        @ObservationIgnored private var skipIntroRequested = false
        @ObservationIgnored private var readyRequested = false
        @ObservationIgnored private var skipExerciseRequested = false

        init(exercises: [Exercise], calibration: Calibration, level: Double) {
            self.exercises = exercises
            self.calibration = calibration
            self.level = level
        }

        var current: Exercise? { index < exercises.count ? exercises[index] : nil }
        var maxScore: Double { Double(exercises.reduce(0) { $0 + $1.reps }) }
        var isFinished: Bool { phase == .finished }

        var sessionProgress: Double {
            guard !exercises.isEmpty else { return 1 }
            if phase == .finished { return 1 }
            let reps = Double(max(1, current?.reps ?? 1))
            return min(1, (Double(index) + Double(repIndex) / reps) / Double(exercises.count))
        }

        var currentAxis: TrackedAxis { current?.axis ?? .none }

        /// Į kurią pusę dabar judama (kai galima į bet kurią – dešinė).
        var demoSide: Int { lockedSide ?? expectedSide ?? 1 }

        // MARK: - Vartotojo veiksmai

        func startNow() { skipIntroRequested = true }
        /// Izometrija: delnas vietoje – galima spausti.
        func confirmReady() { readyRequested = true }
        func skipExercise() { skipExerciseRequested = true }

        // MARK: - Pagrindinis ciklas

        func update(now: Double, reading: HeadReading?) {
            if !started {
                started = true
                lastSeen = now
                beginIntro(now)
            }
            let dt = min(0.1, max(0, now - (lastTime ?? now)))
            lastTime = now
            if reading != nil { lastSeen = now }
            if now > warnUntil { warning = "" }

            if skipExerciseRequested {
                skipExerciseRequested = false
                if phase != .finished {
                    skippedCount += 1
                    nextExercise(now)
                    return
                }
            }

            switch phase {
            case .finished:
                return
            case .intro:
                // Niekur neskubam: treneris kartoja demonstraciją, kol paspausi „Pradėti“.
                if skipIntroRequested {
                    skipIntroRequested = false
                    beginActive(now)
                }
            case .active:
                guard let ex = current else {
                    finish()
                    return
                }
                if !guided && shouldGoGuided(ex, reading: reading, now: now) {
                    guided = true
                    stepStart = now
                    warn("Nematau veido – sek laikmatį", now: now, seconds: 3)
                }
                switch ex.kind {
                case .reach, .stretch:
                    if guided { updateGuidedReach(ex, now: now) } else { updateReach(ex, reading: reading, now: now, dt: dt) }
                case .isometric:
                    updateIsometric(ex, reading: reading, now: now)
                case .rhythm:
                    updateRhythm(ex, now: now)
                }
            }
        }

        private func shouldGoGuided(_ ex: Exercise, reading: HeadReading?, now: Double) -> Bool {
            switch ex.axis {
            case .none:
                return false   // isometrija / ritmas turi savo logiką
            case .depth:
                if let r = reading, !r.hasDepth { return true }
                return reading == nil && now - lastSeen > Self.graceSeconds
            default:
                return reading == nil && now - lastSeen > Self.graceSeconds
            }
        }

        // MARK: - Fazės

        private func beginIntro(_ now: Double) {
            guard let ex = current else {
                finish()
                return
            }
            phase = .intro
            phaseStart = now
            repIndex = 0
            lastSide = nil
            valueNorm = 0
            holdProgress = 0
            isHolding = false
            targetSides = []
            guided = false
            cue = ex.instruction
            announce("\(ex.name). \(ex.instruction)")
        }

        private func beginActive(_ now: Double) {
            phase = .active
            startRep(now)
        }

        private func startRep(_ now: Double) {
            guard let ex = current else { return }
            stepStart = now
            holdAccum = 0
            moveStart = nil
            repScore = 1
            lockedSide = nil
            baseline = nil
            maxDeviation = 0
            stillDeviation = 0
            holdProgress = 0
            isHolding = false
            readyRequested = false
            waitingForReady = false

            switch ex.kind {
            case .reach, .stretch:
                setStage(.approach, now)
                if ex.alternateSides {
                    expectedSide = lastSide.map { -$0 }
                } else {
                    expectedSide = 1
                }
                targetSides = expectedSide.map { [$0] } ?? [1, -1]
                // Pasukus galvą ekrano nesimato – ką daryti, pasakom balsu.
                announce(expectedSide.map { sideName(ex, $0) } ?? "Pradėk į bet kurią pusę")
            case .isometric:
                setStage(.prepare, now)
                waitingForReady = true
                targetSides = []
                let direction = ex.cues.isEmpty ? "" : ex.cues[repIndex % ex.cues.count]
                announce(direction)
            case .rhythm:
                setStage(.rhythm, now)
                targetSides = []
            }
        }

        private func completeRep(_ now: Double, success: Bool = true) {
            guard let ex = current else { return }
            if success {
                score += repScore
                successCount += 1
                bursts.append(Burst(time: now, side: lockedSide ?? 0))
                if bursts.count > 6 { bursts.removeFirst(bursts.count - 6) }
            }
            lastSide = lockedSide ?? expectedSide
            repIndex += 1
            if repIndex >= ex.reps {
                nextExercise(now)
            } else {
                startRep(now)
            }
        }

        private func nextExercise(_ now: Double) {
            index += 1
            if index >= exercises.count {
                finish()
            } else {
                beginIntro(now)
            }
        }

        private func finish() {
            phase = .finished
            targetSides = []
            isHolding = false
            cue = "Mankšta baigta"
            announce("Puiku. Mankšta baigta.")
        }

        // MARK: - Judesys iki taikinio (kamera)

        private func targetMagnitude(_ ex: Exercise, side: Int) -> Double {
            var m = calibration.range(ex.axis, side: side) * level * ex.rangeFraction
            if ex.axis == .pitch && side < 0 { m *= ex.extensionFactor }
            return max(ex.axis == .depth ? 0.4 : 3, m)
        }

        private func axisValue(_ axis: TrackedAxis, _ r: HeadReading) -> Double {
            switch axis {
            case .yaw: return r.yaw
            case .pitch: return r.pitch
            case .roll: return r.roll
            case .depth: return r.depthCm
            case .none: return 0
            }
        }

        private func sideName(_ ex: Exercise, _ side: Int) -> String {
            switch ex.axis {
            case .yaw: return side > 0 ? "Lėtai pasuk į dešinę" : "Lėtai pasuk į kairę"
            case .roll:
                if ex.kind == .stretch {
                    return side > 0 ? "Dešinę ausį – link dešiniojo peties" : "Kairę ausį – link kairiojo peties"
                }
                return side > 0 ? "Dešinę ausį – link peties" : "Kairę ausį – link peties"
            case .pitch: return side > 0 ? "Lėtai smakrą žemyn" : "Švelniai pakelk galvą"
            case .depth: return "Lėtai trauk smakrą atgal"
            case .none: return ""
            }
        }

        private func updateReach(_ ex: Exercise, reading: HeadReading?, now: Double, dt: Double) {
            guard let r = reading else { return }   // trumpas dingimas – laukiam
            let v = axisValue(ex.axis, r)
            let displaySide = lockedSide ?? expectedSide ?? (v >= 0 ? 1 : -1)
            valueNorm = v / targetMagnitude(ex, side: displaySide)

            var guardBroken = false
            if ex.guardAxis != .none && ex.guardLimitDegrees > 0 {
                if abs(axisValue(ex.guardAxis, r)) > ex.guardLimitDegrees {
                    guardBroken = true
                    warn(ex.guardHint, now: now)
                }
            }

            switch stage {
            case .approach:
                isHolding = false
                if lockedSide == nil {
                    let s = v >= 0 ? 1 : -1
                    if abs(v) > 0.2 * targetMagnitude(ex, side: s) {
                        if expectedSide == nil || expectedSide == s {
                            lockedSide = s
                            moveStart = now
                            targetSides = [s]
                        } else if abs(v) > 0.5 * targetMagnitude(ex, side: s) {
                            // Tik aiškiai ne į tą pusę (ne grįžtant iš ankstesnio kartojimo).
                            warn("Dabar – į kitą pusę", now: now)
                        }
                    }
                }
                guard let side = lockedSide else {
                    cue = expectedSide.map { sideName(ex, $0) } ?? (ex.alternateSides ? "Pradėk į bet kurią pusę" : sideName(ex, 1))
                    return
                }
                cue = sideName(ex, side)
                let p = v * Double(side) / targetMagnitude(ex, side: side)
                if p < 0.08 && moveStart.map({ now - $0 > 0.6 }) == true {
                    // Grįžo nepasiekęs – leidžiam pradėti iš naujo.
                    lockedSide = nil
                    moveStart = nil
                    targetSides = expectedSide.map { [$0] } ?? [1, -1]
                    return
                }
                if p >= 0.92 && !guardBroken {
                    // Matuojama tik nuo 20 % iki 92 % kelio (~70 % judesio), todėl riba – 60 % minMoveSeconds.
                    let duration = now - (moveStart ?? now)
                    if ex.minMoveSeconds > 0 && duration < ex.minMoveSeconds * 0.6 {
                        repScore = 0.6
                        warn("Lėčiau – judėk ramiai ir sklandžiai", now: now)
                    }
                    setStage(.hold, now)
                    holdAccum = 0
                    announce(ex.kind == .stretch ? "Gerai. Kvėpuok ramiai" : "Gerai. Laikyk")
                }

            case .hold:
                guard let side = lockedSide else {
                    setStage(.approach, now)
                    return
                }
                let p = v * Double(side) / targetMagnitude(ex, side: side)
                isHolding = true
                if p >= (ex.kind == .stretch ? 0.6 : 0.75) && !guardBroken {
                    holdAccum += dt
                }
                if p < 0.45 {
                    setStage(.approach, now)
                    holdAccum = 0
                    moveStart = now
                    warn("Grįžk iki kontūro ir išlaikyk", now: now)
                }
                holdProgress = min(1, holdAccum / ex.holdSeconds)
                let remaining = max(0, Int((ex.holdSeconds - holdAccum).rounded(.up)))
                cue = ex.kind == .stretch ? breathing(now) : "Išlaikyk… \(remaining)"
                if holdAccum >= ex.holdSeconds {
                    setStage(.returning, now)
                    holdProgress = 1
                    isHolding = false
                    cue = "Lėtai grįžk į centrą"
                    announce("Grįžk į centrą")
                }

            case .returning:
                let side = lockedSide ?? 1
                cue = "Lėtai grįžk į centrą"
                if abs(v) < 0.3 * targetMagnitude(ex, side: side) {
                    completeRep(now)
                }

            default:
                setStage(.approach, now)
            }
        }

        // MARK: - Judesys pagal laikmatį (be kameros)

        private func updateGuidedReach(_ ex: Exercise, now: Double) {
            let side = lockedSide ?? expectedSide ?? 1
            if lockedSide == nil {
                lockedSide = side
                targetSides = [side]
            }
            let move = max(ex.minMoveSeconds, 2.5)
            let hold = ex.holdSeconds
            let t = now - stepStart
            let s = Double(side)
            if t < move {
                setStage(.approach, now)
                isHolding = false
                valueNorm = s * t / move
                holdProgress = 0
                cue = sideName(ex, side)
            } else if t < move + hold {
                setStage(.hold, now)
                isHolding = true
                valueNorm = s
                holdProgress = (t - move) / hold
                cue = ex.kind == .stretch ? breathing(now) : "Išlaikyk… \(max(1, Int((move + hold - t).rounded(.up))))"
            } else if t < move * 2 + hold {
                setStage(.returning, now)
                isHolding = false
                valueNorm = s * (1 - (t - move - hold) / move)
                holdProgress = 1
                cue = "Lėtai grįžk į centrą"
            } else {
                completeRep(now)
                stepStart = now
            }
        }

        // MARK: - Izometrija

        private func updateIsometric(_ ex: Exercise, reading: HeadReading?, now: Double) {
            let direction = ex.cues.isEmpty ? "" : ex.cues[repIndex % ex.cues.count]
            let t = now - stepStart
            valueNorm = 0
            switch stage {
            case .prepare:
                // Laukiam, kol uždėsi delną ir paspausi „Delnas vietoje“ – laikmatis neskubina.
                isHolding = false
                holdProgress = 0
                cue = direction
                if readyRequested {
                    readyRequested = false
                    waitingForReady = false
                    setStage(.press, now)
                    stepStart = now
                    baseline = reading
                    maxDeviation = 0
                    announce("Spausk švelniai")
                }
            case .press:
                isHolding = true
                holdProgress = min(1, t / ex.holdSeconds)
                let remaining = max(1, Int((ex.holdSeconds - t).rounded(.up)))
                cue = "Spausk švelniai – galva nejuda · \(remaining)"
                if let r = reading {
                    if let b = baseline {
                        let dev = max(abs(r.yaw - b.yaw), abs(r.pitch - b.pitch), abs(r.roll - b.roll))
                        stillDeviation = dev
                        maxDeviation = max(maxDeviation, dev)
                    } else {
                        baseline = r
                    }
                }
                if t >= ex.holdSeconds {
                    if baseline == nil {
                        repScore = 1   // be kameros – vertinam tik atlikimą
                    } else if maxDeviation <= 5 {
                        repScore = 1
                    } else if maxDeviation <= 10 {
                        repScore = 0.7
                        warn("Spausk švelniau – galva turi likti vietoje", now: now)
                    } else {
                        repScore = 0.4
                        warn("Spausk švelniau – galva turi likti vietoje", now: now)
                    }
                    setStage(.rest, now)
                    stepStart = now
                    isHolding = false
                    announce("Atpalaiduok")
                }
            case .rest:
                holdProgress = 0
                stillDeviation = 0
                cue = "Atpalaiduok"
                if t >= 3 {
                    completeRep(now)
                }
            default:
                setStage(.prepare, now)
                stepStart = now
            }
        }

        // MARK: - Ritmas (mentės, pečiai)

        private func updateRhythm(_ ex: Exercise, now: Double) {
            let t = now - stepStart
            let duration = max(2, ex.holdSeconds)
            let fraction = min(1, t / duration)
            holdProgress = fraction
            isHolding = fraction > 0.3 && fraction < 0.8
            valueNorm = sin(fraction * .pi) * 0.6
            if !ex.cues.isEmpty {
                let i = min(ex.cues.count - 1, Int(fraction * Double(ex.cues.count)))
                if cue != ex.cues[i] {
                    cue = ex.cues[i]
                    announce(shortCue(cue))
                }
            }
            if t >= duration {
                completeRep(now)
            }
        }

        // MARK: - Pagalbinės

        /// „Kelk pečius – …“ → „Kelk pečius“ (balsui – trumpai).
        private func shortCue(_ text: String) -> String {
            (text.split(separator: "–").first.map(String.init) ?? text).trimmingCharacters(in: .whitespaces)
        }

        /// 4 s įkvėpimas, 6 s iškvėpimas – ramus kvėpavimas tempimo metu.
        private func breathing(_ now: Double) -> String {
            let c = (now - stepStart).truncatingRemainder(dividingBy: 10)
            return c < 4 ? "Įkvėpk…" : "Lėtai iškvėpk ir atsipalaiduok"
        }

        private func setStage(_ next: RepStage, _ now: Double) {
            guard next != stage else { return }
            stage = next
            stageStart = now
        }

        private func warn(_ text: String, now: Double, seconds: Double = 2.2) {
            warning = text
            warnUntil = now + seconds
        }

        private func announce(_ text: String) {
            announcement = text
            announcementID += 1
        }
    }
}
