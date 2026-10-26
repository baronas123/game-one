import CoreGraphics
import Foundation

extension Sankryza {

    // MARK: - Transportas

    enum VehicleKind {
        case hatch, taxi, bus, truck, police

        var length: Double {
            switch self {
            case .hatch: return 1.45
            case .taxi: return 1.5
            case .bus: return 2.7
            case .truck: return 2.9
            case .police: return 1.6
            }
        }
        var width: Double {
            switch self {
            case .hatch: return 0.74
            case .taxi, .police: return 0.77
            case .bus, .truck: return 0.86
            }
        }
        var maxSpeed: Double {
            switch self {
            case .hatch: return 4.2
            case .taxi: return 4.6
            case .bus: return 3.3
            case .truck: return 2.7
            case .police: return 5.2
            }
        }
        var acceleration: Double {
            switch self {
            case .hatch: return 5.2
            case .taxi: return 5.5
            case .bus: return 3.2
            case .truck: return 2.4
            case .police: return 6.5
            }
        }
        var points: Int {
            switch self {
            case .hatch, .taxi: return 1
            case .bus, .truck: return 2
            case .police: return 3
            }
        }
    }

    enum Signal { case green, yellow, red }

    struct TrafficLight {
        var state: Signal
        var t: Double = 0
    }

    struct Car {
        let id: Int
        let approach: Int
        let kind: VehicleKind
        let paint: Int            // spalvos indeksas (taxi/police/bus turi savo)
        var s: Double = 0         // priekio padėtis kelyje (vienetais)
        var v: Double
        var wait: Double = 0
        var passed = false
        var committed = false
        var braking = false
        var angry: Double = 0
        var rot: Double = 0
        var spin: Double = 0
        var crashed = false

        var len: Double { kind.length }
        var wid: Double { kind.width }
    }

    /// Viena įvažiavimo kryptis: 0 – iš pietų į šiaurę, 1 – iš vakarų, 2 – iš šiaurės, 3 – iš rytų.
    struct Approach {
        let dx: Double, dy: Double
        let lx: Double, ly: Double
        let dist0: Double
        let far: Double
        let sStop: Double
    }

    struct Particle {
        var x: Double, y: Double, vx: Double, vy: Double
        var life: Double
        let maxLife: Double
        let spark: Bool
    }

    struct Popup {
        let x: Double, y: Double
        let text: String
        var t: Double = 0
        let tint: Int   // 0 balta, 1 auksinė, 2 raudona
    }

    struct Ripple { let x: Double, y: Double; var t: Double = 0 }

    struct BannerInfo: Equatable {
        let id: Int
        let title: String
        let subtitle: String
        let warn: Bool
    }

    enum Phase { case attract, play, crash, over }
    enum Cause { case crash, patience, jam }

    enum Event { case click, pass, heart, crash, stage, estop }

    static let cities = ["Vilnius – Konstitucijos pr.", "Kaunas – Laisvės al.", "Klaipėda – Taikos pr.",
                         "Šiauliai – Tilžės g.", "Panevėžys – Respublikos g.", "Alytus – Naujoji g.",
                         "Vilnius – Gedimino pr."]

    // MARK: - Simuliacija

    /// Visa žaidimo logika (be UI). Vienetas = vienos eismo juostos plotis.
    final class Simulation {
        static let gap = 0.38, comfortBrake = 7.5, yellowTime = 0.75, dayCycle = 150.0, perStage = 20

        private(set) var city = CityLayout.empty
        private(set) var size: CGSize = .zero

        var phase: Phase = .attract
        var t = 0.0
        var playT = 0.0
        var lanes: [[Car]] = [[], [], [], []]
        var pending = [0, 0, 0, 0]
        var lights: [TrafficLight] = []
        var spawnT = 1.2
        var score = 0
        var passed = 0
        var hearts = 3
        var combo = 0
        var comboT = 0.0
        var maxCombo = 0
        var stage = 0
        var timeScale = 1.0
        var crashPoint = CGPoint.zero
        var crashT = 0.0
        var shake = 0.0
        var particles: [Particle] = []
        var popups: [Popup] = []
        var ripples: [Ripple] = []
        var estopReady = true
        var cause: Cause = .crash
        var banner: BannerInfo?
        var bannerT = 0.0
        private var bannerCounter = 0
        private var nextID = 1
        private var autoPhase = 0
        private var autoT = 0.0

        /// Garsų / vibracijos įvykiai vaizdui.
        var onEvent: ((Event) -> Void)?

        init() { reset(.attract) }

        var unit: Double { city.unit }

        // MARK: Paruošimas

        private var insets = (top: 0.0, bottom: 0.0)

        /// `topInset` – kiek viršuje užima HUD (ir „notch“), taškais.
        func configure(size: CGSize, topInset: Double, bottomInset: Double) {
            guard size.width > 10, size.height > 10 else { return }
            guard size != self.size || topInset != insets.top || bottomInset != insets.bottom else { return }
            self.size = size
            insets = (topInset, bottomInset)
            city = CityLayout.make(size: size, topInset: topInset, bottomInset: bottomInset)
            if phase == .attract { reset(.attract); warmUp() }
        }

        func reset(_ phase: Phase) {
            self.phase = phase
            t = 0; playT = 0
            lanes = [[], [], [], []]; pending = [0, 0, 0, 0]
            lights = (0..<4).map { TrafficLight(state: $0 % 2 == 0 ? .green : .red) }
            spawnT = 1.2; score = 0; passed = 0; hearts = 3
            combo = 0; comboT = 0; maxCombo = 0; stage = 0
            timeScale = 1; crashT = 0; shake = 0
            particles = []; popups = []; ripples = []
            estopReady = true; cause = .crash
            banner = nil; bannerT = 0
            autoPhase = 0; autoT = 0
        }

        func warmUp() {
            for _ in 0..<240 { update(1.0 / 30.0) }
        }

        func startGame() {
            reset(.play)
            showBanner(Sankryza.cities[0], "1 etapas · Bakstelėk šviesoforą", warn: false)
        }

        // MARK: Valdymas

        func toggle(_ a: Int) {
            guard phase == .play else { return }
            switch lights[a].state {
            case .red, .yellow: setLight(a, .green)
            case .green: setLight(a, .yellow)
            }
            let p = city.lights[a]
            ripples.append(Ripple(x: Double(p.x), y: Double(p.y)))
            onEvent?(.click)
        }

        /// Bakstelėjimas ekrano taškuose.
        func tap(at point: CGPoint) {
            guard phase == .play, unit > 0 else { return }
            var best = -1
            var bestD = 34.0
            for (a, p) in city.lights.enumerated() {
                let d = hypot(Double(p.x) * unit - Double(point.x), Double(p.y) * unit - Double(point.y))
                if d < bestD { bestD = d; best = a }
            }
            if best < 0 {
                let x = Double(point.x) / unit - city.cx, y = Double(point.y) / unit - city.cy
                let r = city.r, band = r + 1.6
                if y > r && abs(x) < band { best = 0 }
                else if y < -r && abs(x) < band { best = 2 }
                else if x < -r && abs(y) < band { best = 1 }
                else if x > r && abs(y) < band { best = 3 }
            }
            if best >= 0 { toggle(best) }
        }

        func emergencyStop() {
            guard phase == .play, estopReady else { return }
            estopReady = false
            for a in 0..<4 {
                lights[a] = TrafficLight(state: .red)
                commitUnstoppable(a, brake: 11)
            }
            showBanner("AVARINIS STABDYMAS", "Visi šviesoforai – raudoni", warn: true)
            onEvent?(.estop)
        }

        func setLight(_ a: Int, _ state: Signal) {
            guard lights[a].state != state else { return }
            lights[a] = TrafficLight(state: state)
            if state == .green {
                for i in lanes[a].indices { lanes[a][i].committed = false }
            } else {
                commitUnstoppable(a, brake: 9)
            }
        }

        private func commitUnstoppable(_ a: Int, brake: Double) {
            let ap = city.approaches[a]
            for i in lanes[a].indices {
                let c = lanes[a][i]
                let d = ap.sStop - c.s
                if d >= -0.02 && d < c.v * c.v / (2 * brake) { lanes[a][i].committed = true }
            }
        }

        // MARK: Pagalbinės

        var rate: Double { min(1.75, 0.42 + 0.14 * Double(stage) + 0.0025 * playT) }
        var patience: Double { max(5.5, 9.5 - 0.6 * Double(stage)) }
        func patience(for c: Car) -> Double { c.kind == .police ? 4.5 : patience }
        var multiplier: Int { min(5, 1 + combo / 8) }
        var cityName: String { Sankryza.cities[stage % Sankryza.cities.count] }

        func front(_ c: Car) -> CGPoint {
            let ap = city.approaches[c.approach]
            let q = c.s - ap.dist0
            return CGPoint(x: city.cx + ap.lx + ap.dx * q, y: city.cy + ap.ly + ap.dy * q)
        }

        func sky() -> (dark: Double, dusk: Double) {
            let time = phase == .attract ? t + 40 : playT
            let p = (time / Simulation.dayCycle + 0.03).truncatingRemainder(dividingBy: 1)
            var dk = 0.0
            if p < 0.38 { dk = 0 } else if p < 0.5 { dk = (p - 0.38) / 0.12 } else if p < 0.85 { dk = 1 }
            else if p < 0.97 { dk = 1 - (p - 0.85) / 0.12 }
            let dusk = max(0, 1 - abs(p - 0.44) / 0.08) + max(0, 1 - abs(p - 0.91) / 0.06) * 0.7
            return (dk * dk * (3 - 2 * dk), min(1, dusk))
        }

        private func laneFree(_ a: Int) -> Bool {
            guard let c = lanes[a].last else { return true }
            return c.s - c.len > Simulation.gap + 0.25
        }

        private func pickKind() -> VehicleKind {
            let r = Double.random(in: 0..<1), st = Double(stage)
            let pol = stage >= 1 ? 0.06 : 0, bus = min(0.16, 0.08 + 0.02 * st), tr = min(0.14, 0.05 + 0.02 * st)
            if r < pol { return .police }
            if r < pol + bus { return .bus }
            if r < pol + bus + tr { return .truck }
            if r < pol + bus + tr + 0.14 { return .taxi }
            return .hatch
        }

        private func spawn(_ a: Int) {
            let kind = pickKind()
            var v = kind.maxSpeed * 0.85
            if let ld = lanes[a].last {
                v = min(v, (max(0, 2 * Simulation.comfortBrake * (ld.s - ld.len - Simulation.gap))).squareRoot())
            }
            lanes[a].append(Car(id: nextID, approach: a, kind: kind, paint: Int.random(in: 0..<10), v: v))
            nextID += 1
        }

        func showBanner(_ title: String, _ subtitle: String, warn: Bool) {
            bannerCounter += 1
            banner = BannerInfo(id: bannerCounter, title: title, subtitle: subtitle, warn: warn)
            bannerT = 2.2
        }

        // MARK: Žingsnis

        /// Realaus laiko žingsnis (sekundėmis). Grąžina true, jei žaidimas ką tik baigėsi.
        @discardableResult
        func step(_ realDt: Double) -> Bool {
            guard city.unit > 0 else { return false }
            let dt = min(0.05, max(0, realDt))
            if bannerT > 0 { bannerT -= dt; if bannerT <= 0 { banner = nil } }
            switch phase {
            case .crash:
                crashT += dt
                timeScale += (0.15 - timeScale) * 0.12
                shake = max(0, shake - dt * 1.2)
                update(dt * timeScale)
                if crashT > 1.7 { finish(); return true }
            case .over:
                shake = 0
            case .attract, .play:
                timeScale = 1
                shake = max(0, shake - dt * 2)
                update(dt)
                if phase == .play && hearts <= 0 { finish(); return true }
            }
            return false
        }

        private func finish() {
            phase = .over
        }

        func update(_ dt: Double) {
            t += dt
            if phase == .play { playT += dt }
            for i in lights.indices {
                lights[i].t += dt
                if lights[i].state == .yellow && lights[i].t >= Simulation.yellowTime { lights[i] = TrafficLight(state: .red) }
            }
            if phase == .attract { autopilot(dt) }
            if phase == .play || phase == .attract {
                spawnT -= dt
                if spawnT <= 0 {
                    spawnT = (0.55 + Double.random(in: 0..<0.9)) / (phase == .attract ? 0.7 : rate)
                    let a = Int.random(in: 0..<4)
                    if laneFree(a) && pending[a] == 0 { spawn(a) } else { pending[a] += 1 }
                }
            }
            for a in 0..<4 {
                updateLane(a, dt)
                if pending[a] > 0 && laneFree(a) { spawn(a); pending[a] -= 1 }
                if pending[a] >= 4 {
                    if phase == .play {
                        pending[a] = 2
                        let ap = city.approaches[a]
                        loseHeart(.jam, x: city.cx + ap.lx - ap.dx * (ap.dist0 - 1.2), y: city.cy + ap.ly - ap.dy * (ap.dist0 - 1.2))
                        if phase == .play { showBanner("KAMŠTIS!", "Atlaisvink užsikimšusią kryptį", warn: true) }
                    } else {
                        pending[a] = 3
                    }
                }
            }
            if phase == .play || phase == .attract { collisions() }
            if comboT > 0 { comboT -= dt; if comboT <= 0 { combo = 0 } }
            let friction = pow(0.08, dt)
            for i in particles.indices {
                particles[i].x += particles[i].vx * dt
                particles[i].y += particles[i].vy * dt
                particles[i].vx *= friction
                particles[i].vy *= friction
                particles[i].life -= dt
            }
            particles.removeAll { $0.life <= 0 }
            for i in popups.indices { popups[i].t += dt }
            popups.removeAll { $0.t >= 1.1 }
            for i in ripples.indices { ripples[i].t += dt }
            ripples.removeAll { $0.t >= 0.5 }
        }

        private func updateLane(_ a: Int, _ dt: Double) {
            let ap = city.approaches[a]
            let red = lights[a].state != .green
            var headFound = false
            for i in lanes[a].indices {
                var c = lanes[a][i]
                if c.crashed {
                    c.v = 0
                    c.rot += c.spin * dt
                    c.spin *= pow(0.25, dt)
                    lanes[a][i] = c
                    continue
                }
                var limit = Double.infinity
                var atLight = false
                if i > 0 {
                    let ld = lanes[a][i - 1]
                    limit = ld.s - ld.len - Simulation.gap
                }
                if red && !c.committed && c.s <= ap.sStop + 0.02 {
                    limit = min(limit, ap.sStop)
                    if !headFound { atLight = true; headFound = true }
                }
                let room = limit - c.s
                let allowed: Double = room == .infinity
                    ? c.kind.maxSpeed
                    : min(c.kind.maxSpeed, (max(0, 2 * Simulation.comfortBrake * room)).squareRoot())
                let pv = c.v
                c.v = allowed > c.v ? min(allowed, c.v + c.kind.acceleration * dt) : allowed
                c.s += c.v * dt
                if c.s > limit { c.s = limit; c.v = 0 }
                c.braking = c.v < pv - 0.001 || (c.v < 0.3 && limit != .infinity)
                let stopped = c.v < 0.25
                if stopped && !c.passed && (atLight || c.kind == .police) { c.wait += dt } else if c.v > 0.8 { c.wait = 0 }
                if c.angry > 0 { c.angry -= dt }
                if phase == .play && c.wait >= patience(for: c) {
                    c.wait = 0
                    c.angry = 1.2
                    lanes[a][i] = c
                    let f = front(c)
                    loseHeart(.patience, x: Double(f.x), y: Double(f.y))
                }
                if !c.passed && c.s - ap.dist0 - c.len > city.r {
                    c.passed = true
                    lanes[a][i] = c
                    scorePass(c)
                }
                lanes[a][i] = c
            }
            while let first = lanes[a].first, first.s - first.len > ap.dist0 + ap.far + 0.4 {
                lanes[a].removeFirst()
            }
        }

        private func loseHeart(_ why: Cause, x: Double, y: Double) {
            guard phase == .play else { return }
            hearts -= 1
            combo = 0
            cause = why
            popups.append(Popup(x: x, y: y, text: why == .jam ? "KAMŠTIS!" : "PYP-PYP!", tint: 2))
            onEvent?(.heart)
        }

        private func scorePass(_ c: Car) {
            guard phase == .play else { return }
            combo += 1
            comboT = 4.5
            maxCombo = max(maxCombo, combo)
            let pts = c.kind.points * multiplier
            score += pts
            passed += 1
            let f = front(c)
            popups.append(Popup(x: Double(f.x), y: Double(f.y), text: "+\(pts)", tint: multiplier > 1 ? 1 : 0))
            onEvent?(.pass)
            let st = passed / Simulation.perStage
            if st > stage {
                stage = st
                estopReady = true
                let bonus = hearts < 3
                if bonus { hearts += 1 }
                showBanner(cityName, "\(st + 1) etapas" + (bonus ? " · +1 širdelė" : "") + " · STOP paruoštas", warn: false)
                onEvent?(.stage)
            }
        }

        private func box(_ c: Car) -> CGRect {
            let ap = city.approaches[c.approach]
            let f = front(c)
            let rx = Double(f.x) - ap.dx * c.len, ry = Double(f.y) - ap.dy * c.len, hw = c.wid / 2
            if ap.dx == 0 {
                return CGRect(x: Double(f.x) - hw, y: min(Double(f.y), ry), width: c.wid, height: abs(Double(f.y) - ry))
            }
            return CGRect(x: min(Double(f.x), rx), y: Double(f.y) - hw, width: abs(Double(f.x) - rx), height: c.wid)
        }

        private func collisions() {
            var inBox: [(a: Int, i: Int)] = []
            for a in 0..<4 {
                let ap = city.approaches[a]
                for (i, c) in lanes[a].enumerated() {
                    let q = c.s - ap.dist0
                    if q > -city.r - 0.1 && q - c.len < city.r + 0.1 { inBox.append((a, i)) }
                }
            }
            guard inBox.count > 1 else { return }
            for m in 0..<(inBox.count - 1) {
                for n in (m + 1)..<inBox.count {
                    let p = inBox[m], q = inBox[n]
                    let A = lanes[p.a][p.i], B = lanes[q.a][q.i]
                    if p.a % 2 == q.a % 2 || (A.crashed && B.crashed) { continue }
                    let ra = box(A).insetBy(dx: 0.06, dy: 0.06), rb = box(B).insetBy(dx: 0.06, dy: 0.06)
                    if ra.intersects(rb) {
                        let hit = ra.intersection(rb)
                        crash(p, q, at: CGPoint(x: hit.midX, y: hit.midY))
                        return
                    }
                }
            }
        }

        private func crash(_ p: (a: Int, i: Int), _ q: (a: Int, i: Int), at point: CGPoint) {
            for k in [p, q] {
                lanes[k.a][k.i].crashed = true
                lanes[k.a][k.i].spin = (Bool.random() ? -1 : 1) * Double.random(in: 2...4)
            }
            for i in 0..<60 {
                let ang = Double.random(in: 0..<(2 * .pi)), sp = Double.random(in: 2...11)
                let life = Double.random(in: 0.5...1.4)
                particles.append(Particle(x: Double(point.x), y: Double(point.y), vx: cos(ang) * sp, vy: sin(ang) * sp,
                                          life: life, maxLife: 1.4, spark: i < 44))
            }
            if phase == .attract {
                // Demonstracijoje tiesiog pradedame iš naujo.
                reset(.attract)
                return
            }
            phase = .crash
            crashPoint = point
            crashT = 0
            cause = .crash
            shake = 1
            onEvent?(.crash)
        }

        /// Demonstracinis režimas: saugus automatinis reguliavimas.
        private func autopilot(_ dt: Double) {
            autoT += dt
            let axis = autoPhase < 2 ? 0 : 1
            if autoPhase % 2 == 0 {
                if autoT > 4.5 {
                    setLight(axis, .yellow); setLight(axis + 2, .yellow)
                    autoPhase += 1; autoT = 0
                }
            } else if autoT > 1.4 && !axisBusy(axis) {
                let nx = 1 - axis
                setLight(nx, .green); setLight(nx + 2, .green)
                autoPhase = (autoPhase + 1) % 4; autoT = 0
            }
        }

        private func axisBusy(_ axis: Int) -> Bool {
            for a in [axis, axis + 2] {
                let ap = city.approaches[a]
                for c in lanes[a] {
                    let q = c.s - ap.dist0
                    if q > -city.r - 0.2 && q - c.len < city.r + 0.2 { return true }
                }
            }
            return false
        }
    }
}
