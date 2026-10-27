import Foundation

extension LaisvasKaklas {

    /// Kur trenerio delnas (izometrija, tempimas).
    enum HandPlacement: Equatable {
        case none, forehead, rightTemple, leftTemple, backOfHead
        /// Tempimas: delnas per galvą ant priešingo smilkinio (`side` – į kurią pusę lenkiama).
        case overHead(side: Int)
    }

    /// 3D trenerio poza. Kampai laipsniais, „veidrodžiu“ – kaip žaidėjas mato save veidrodyje:
    /// yaw > 0 – pasuka į dešinę, pitch > 0 – smakras žemyn, roll > 0 – dešinė ausis link peties.
    struct CoachPose: Equatable {
        var yaw = 0.0
        var pitch = 0.0
        var roll = 0.0
        /// Smakro įtraukimas atgal, 0…1.
        var chinBack = 0.0
        /// Pečių poslinkis: aukštyn (+) / žemyn (−) ir atgal (+) / pirmyn (−), apie −1…1.
        var shoulderUp = 0.0
        var shoulderBack = 0.0
        var hand: HandPlacement = .none
        /// 0 – ranka nuleista, 1 – delnas vietoje.
        var handReach = 0.0
        /// 0…1 – spaudimas (rodoma rodykle).
        var press = 0.0
    }

    /// Vienas žingsnis demonstracijoje (rodomas po figūra: „Pasuk · Išlaikyk · Grįžk“).
    struct CoachStep: Equatable {
        let title: String
        let symbol: String
    }

    /// Kaip treneris rodo pratimą: kilpinė demonstracija (įžangoje) ir gyvas vedimas (pratimo metu).
    enum CoachDemo {

        // MARK: - Pozos

        static func targetPose(_ ex: Exercise, side: Int) -> CoachPose {
            var p = CoachPose()
            let s = Double(side)
            switch ex.axis {
            case .yaw: p.yaw = 55 * s
            case .roll:
                p.roll = (ex.kind == .stretch ? 38 : 30) * s
                if ex.kind == .stretch {
                    p.hand = .overHead(side: side)
                    p.handReach = 1
                }
            case .pitch: p.pitch = side > 0 ? 35 : -15
            case .depth: p.chinBack = 1
            case .none: break
            }
            return p
        }

        static func blend(_ ex: Exercise, side: Int, amount: Double) -> CoachPose {
            let a = max(0, min(1.2, amount))
            let t = targetPose(ex, side: side)
            var p = CoachPose(yaw: t.yaw * a, pitch: t.pitch * a, roll: t.roll * a, chinBack: t.chinBack * a)
            if t.hand != .none {
                p.hand = t.hand
                p.handReach = min(1, a * 1.4)
            }
            return p
        }

        /// Tavo galvos poza figūrai: pagrindinė ašis – tuo pačiu masteliu kaip kontūras
        /// (taikinys = 1), kitos ašys – tikri kampai, kad matytum, jei galva „nuslysta“.
        static func userPose(_ ex: Exercise, valueNorm v: Double, yaw: Double, pitch: Double, roll: Double) -> CoachPose {
            var p = blend(ex, side: v >= 0 ? 1 : -1, amount: abs(v))
            let limit = { (x: Double) in max(-60, min(60, x)) }
            if ex.axis != .yaw { p.yaw = limit(yaw) }
            if ex.axis != .roll { p.roll = limit(roll) }
            if ex.axis != .pitch { p.pitch = limit(pitch) }
            return p
        }

        /// Tikra tavo galvos padėtis (įžangoje, kol taikinio dar nėra).
        static func mirrorPose(yaw: Double, pitch: Double, roll: Double, depthCm: Double) -> CoachPose {
            let limit = { (x: Double) in max(-60, min(60, x)) }
            return CoachPose(yaw: limit(yaw), pitch: limit(pitch), roll: limit(roll),
                             chinBack: max(0, min(1, depthCm / 1.5)))
        }

        static func steps(_ ex: Exercise) -> [CoachStep] {
            switch ex.kind {
            case .reach:
                return [CoachStep(title: moveVerb(ex), symbol: "arrow.right"),
                        CoachStep(title: "Išlaikyk", symbol: "pause.fill"),
                        CoachStep(title: "Grįžk", symbol: "arrow.uturn.backward")]
            case .stretch:
                return [CoachStep(title: "Lenk", symbol: "arrow.down.right"),
                        CoachStep(title: "Kvėpuok", symbol: "wind"),
                        CoachStep(title: "Grįžk", symbol: "arrow.uturn.backward")]
            case .isometric:
                return [CoachStep(title: "Delnas prie galvos", symbol: "hand.raised.fill"),
                        CoachStep(title: "Spausk", symbol: "arrow.right.to.line"),
                        CoachStep(title: "Atpalaiduok", symbol: "leaf.fill")]
            case .rhythm:
                let symbols = ex.id == "peciu-ratai"
                    ? ["arrow.up", "arrow.counterclockwise", "arrow.down"]
                    : ["arrow.down.backward", "pause.fill", "leaf.fill"]
                return ex.cues.enumerated().map { i, c in
                    CoachStep(title: shortCue(c), symbol: symbols[min(i, symbols.count - 1)])
                }
            }
        }

        private static func moveVerb(_ ex: Exercise) -> String {
            switch ex.axis {
            case .yaw: return "Pasuk"
            case .roll: return "Lenk"
            case .pitch: return "Linktelk"
            case .depth: return "Smakrą atgal"
            case .none: return "Judėk"
            }
        }

        private static func shortCue(_ cue: String) -> String {
            let first = cue.split(separator: "–").first.map(String.init) ?? cue
            return first.trimmingCharacters(in: .whitespaces)
        }

        // MARK: - Kilpinė demonstracija (įžanga)

        /// Vienos demonstracijos kilpos trukmė (s).
        static func loopSeconds(_ ex: Exercise) -> Double {
            switch ex.kind {
            case .reach, .stretch: return ex.alternateSides ? 11 : 6
            case .isometric: return 7
            case .rhythm: return max(3, ex.holdSeconds)
            }
        }

        /// Poza ir aktyvus žingsnis demonstracijoje laiku `t` (s nuo pradžios).
        static func loop(_ ex: Exercise, t: Double) -> (pose: CoachPose, step: Int) {
            let length = loopSeconds(ex)
            var local = max(0, t).truncatingRemainder(dividingBy: length)
            switch ex.kind {
            case .reach, .stretch:
                let r = loopReach(ex, t: t)
                return (blend(ex, side: r.side, amount: ease(r.amount)), r.step)
            case .isometric:
                let placement = isometricPlacement(ex, rep: Int(max(0, t) / length))
                if local < 1.6 { return isometric(placement, phase: 0, elapsed: local) }
                if local < 5.6 { return isometric(placement, phase: 1, elapsed: local - 1.6) }
                return isometric(placement, phase: 2, elapsed: local - 5.6)
            case .rhythm:
                return rhythm(ex, fraction: local / length)
            }
        }

        /// Judesio demonstracija: pusė, žingsnis (0 – link taikinio, 1 – išlaikyk, 2 – grįžk)
        /// ir žingsnio eiga 0…1 (`amount` – kiek nueita link taikinio).
        static func loopReach(_ ex: Exercise, t: Double) -> (side: Int, step: Int, progress: Double, amount: Double) {
            let length = loopSeconds(ex)
            var local = max(0, t).truncatingRemainder(dividingBy: length)
            var side = 1
            let half = ex.alternateSides ? length / 2 : length
            if local >= half {
                local -= half
                side = -1
            }
            let move = 1.9, back = 1.9
            let hold = half - move - back - 0.4
            if local < move {
                let k = local / move
                return (side, 0, k, k)
            } else if local < move + hold {
                return (side, 1, (local - move) / hold, 1)
            } else if local < move + hold + back {
                let k = (local - move - hold) / back
                return (side, 2, k, 1 - k)
            }
            return (side, 2, 1, 0)
        }

        // MARK: - Gyvas vedimas (pratimo metu)

        /// Ką treneris rodo dabar, kai tavo galva nesekama (laikmačio režimas ar dingo veidas).
        static func live(_ e: SessionEngine, now: Double) -> (pose: CoachPose, step: Int) {
            guard let ex = e.current else { return (CoachPose(), 0) }
            let elapsed = max(0, now - e.stageStart)
            let side = e.demoSide
            switch e.stage {
            case .approach:
                if e.guided { return (blend(ex, side: side, amount: abs(e.valueNorm)), 0) }
                return (blend(ex, side: side, amount: ease(elapsed / max(1.5, ex.minMoveSeconds))), 0)
            case .hold:
                return (blend(ex, side: side, amount: 1), 1)
            case .returning:
                if e.guided { return (blend(ex, side: side, amount: abs(e.valueNorm)), 2) }
                return (blend(ex, side: side, amount: 1 - ease(elapsed / 1.6)), 2)
            case .prepare:
                return isometric(isometricPlacement(ex, rep: e.repIndex), phase: 0, elapsed: elapsed)
            case .press:
                return isometric(isometricPlacement(ex, rep: e.repIndex), phase: 1, elapsed: elapsed)
            case .rest:
                return isometric(isometricPlacement(ex, rep: e.repIndex), phase: 2, elapsed: elapsed)
            case .rhythm:
                return rhythm(ex, fraction: e.holdProgress)
            }
        }

        // MARK: - Pagalbinės

        /// Izometrijos kryptys eina ta pačia tvarka kaip `Exercise.cues`.
        static func isometricPlacement(_ ex: Exercise, rep: Int) -> HandPlacement {
            let order: [HandPlacement] = [.forehead, .rightTemple, .leftTemple, .backOfHead]
            let n = max(1, min(order.count, ex.cues.count))
            return order[((rep % n) + n) % n]
        }

        private static func isometric(_ placement: HandPlacement, phase: Int, elapsed: Double) -> (pose: CoachPose, step: Int) {
            var p = CoachPose()
            p.hand = placement
            switch phase {
            case 0:
                p.handReach = ease(elapsed / 1.4)
            case 1:
                p.handReach = 1
                // Spaudimas „pulsuoja“: dirba ranka, o galva lieka vietoje.
                p.press = 0.55 + 0.45 * sin(elapsed * 2.2)
            default:
                p.handReach = 1 - ease(elapsed / 1.2)
            }
            return (p, phase)
        }

        private static func rhythm(_ ex: Exercise, fraction: Double) -> (pose: CoachPose, step: Int) {
            let f = max(0, min(1, fraction))
            var p = CoachPose()
            if ex.id == "peciu-ratai" {
                // Ratas atgal: aukštyn per priekį, atgal ir žemyn.
                let a = f * 2 * .pi
                p.shoulderUp = (1 - cos(a)) / 2
                p.shoulderBack = -0.7 * sin(a)
            } else {
                // Mentės: atgal ir žemyn, išlaikyti, atpalaiduoti.
                let k: Double
                if f < 0.3 { k = ease(f / 0.3) } else if f < 0.75 { k = 1 } else { k = 1 - ease((f - 0.75) / 0.25) }
                p.shoulderBack = k
                p.shoulderUp = -0.4 * k
            }
            let count = max(1, ex.cues.count)
            return (p, min(count - 1, Int(f * Double(count))))
        }

        static func ease(_ x: Double) -> Double {
            let k = max(0, min(1, x))
            return k * k * (3 - 2 * k)
        }
    }
}
