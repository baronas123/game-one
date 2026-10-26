import Foundation

extension ParkavimoMeistras {

    enum Gear: String { case neutral = "N", drive = "D", reverse = "R" }

    struct Pedestrian {
        var path: PedPath
        var t = 0.0
        var dir = 1.0
        var wait = 0.0
        var x: Double
        var y: Double
        var heading = 0.0
        var walking = true
        var colorIndex: Int
    }

    struct Mover {
        var path: MoverPath
        var t = 0.0
        var len: Double
        var a: Double
        var x: Double
        var y: Double
    }

    struct Spark { var x: Double; var y: Double; var vx: Double; var vy: Double; var life: Double }
    struct Skid { var x1: Double; var y1: Double; var x2: Double; var y2: Double }

    /// Tai, ką vaizdas stebi (`onChange`) – keičiasi retai, todėl tinka SwiftUI.
    struct Snapshot: Equatable {
        var scratches = 0
        var bumps = 0
        var beeps = 0
        var won = false
        var gear = Gear.neutral
        var tenths = 0
        var toast: String?
    }

    /// Žaidimo pasaulis. Paprasta klasė (ne @Observable): ją kas kadrą „suka“ TimelineView.
    final class Simulation {
        let index: Int
        let level: Level
        let colliders: Colliders
        var controls = Controls()

        private(set) var car: CarState
        private(set) var time = 0.0
        private(set) var started = false
        private(set) var scratches = 0
        private(set) var won = false
        private(set) var hold = 0.0
        private(set) var gear = Gear.neutral
        private(set) var peds: [Pedestrian]
        private(set) var movers: [Mover]
        private(set) var sparks: [Spark] = []
        private(set) var skids: [Skid] = []
        private(set) var shake = 0.0
        private(set) var clock = 0.0
        private(set) var rearDistance = 3.0
        private(set) var bumps = 0
        private(set) var beeps = 0
        private(set) var toast: String?

        private var cool = 0.0
        private var accumulator = 0.0
        private var lastDate: Date?
        private var beepTimer = 0.0
        private var toastUntil = 0.0
        private var lastRear: [(Double, Double)]?
        private var rng = SplitMix64(seed: 77)

        init(index: Int) {
            self.index = index
            let lv = Levels.all[index]
            level = lv
            colliders = Colliders(level: lv)
            car = CarState(x: lv.start.x, y: lv.start.y, a: lv.start.deg * .pi / 180)
            peds = lv.peds.enumerated().map { i, p in
                Pedestrian(path: p, x: p.x1, y: p.y1, colorIndex: i)
            }
            movers = lv.movers.map { m in
                Mover(path: m, len: hypot(m.x2 - m.x1, m.y2 - m.y1), a: atan2(m.y2 - m.y1, m.x2 - m.x1), x: m.x1, y: m.y1)
            }
        }

        var spotState: (inside: Bool, aligned: Bool) { Physics.spotCheck(level, car) }

        /// Pasuka pasaulį iki nurodyto laiko fiksuotais 1/120 s žingsniais.
        @discardableResult
        func advance(to date: Date) -> Snapshot {
            let dt = min(0.05, lastDate.map { date.timeIntervalSince($0) } ?? 0.016)
            lastDate = date
            if dt > 0 {
                clock += dt
                accumulator += dt
                var steps = 0
                while accumulator >= 1.0 / 120 && steps < 12 {
                    step(1.0 / 120)
                    accumulator -= 1.0 / 120
                    steps += 1
                }
                updateSensors(dt)
            }
            if toast != nil && clock > toastUntil { toast = nil }
            return Snapshot(scratches: scratches, bumps: bumps, beeps: beeps, won: won, gear: gear,
                            tenths: Int(time * 10), toast: toast)
        }

        /// Testams: padėti mašiną į bet kurią vietą.
        func place(x: Double, y: Double, a: Double) { car = CarState(x: x, y: y, a: a) }

        // MARK: - Vienas žingsnis

        private func step(_ dt: Double) {
            var inp = controls
            if won { inp.gas = false; inp.rev = false; inp.hand = true }
            if !started && (inp.gas || inp.rev) { started = true }
            if started && !won { time += dt }
            if inp.gas && !inp.rev {
                gear = .drive
            } else if inp.rev && !inp.gas && car.v <= 0.05 {
                gear = .reverse
            }
            cool = max(0, cool - dt)
            shake = max(0, shake - dt)

            let prev = car
            let next = Physics.step(prev, inp, dt: dt)
            let box = Physics.carBox(next)
            let dynamic = dynamicHit(box)
            if colliders.hits(box) || dynamic != nil {
                let impact = abs(prev.v)
                car = prev
                car.steer = next.steer
                car.v = -prev.v * 0.3
                car.braking = next.braking
                if impact > 0.35 { bump(pedestrian: dynamic == "ped", impact: impact) }
            } else {
                car = next
            }

            addSkids()
            movePeople(dt)
            moveTraffic(dt)

            for i in sparks.indices {
                sparks[i].x += sparks[i].vx * dt
                sparks[i].y += sparks[i].vy * dt
                sparks[i].vx *= 0.92
                sparks[i].vy *= 0.92
                sparks[i].life -= dt
            }
            sparks.removeAll { $0.life <= 0 }

            if !won {
                let s = spotState
                if s.inside && s.aligned && abs(car.v) < 0.25 {
                    hold += dt
                    if hold >= 0.7 { won = true }
                } else {
                    hold = max(0, hold - dt * 2)
                }
            }
        }

        private func dynamicHit(_ b: OBB) -> String? {
            for m in movers where Physics.hit(b, OBB(x: m.x, y: m.y, a: m.a, hl: CarSpec.length / 2, hw: CarSpec.width / 2)) {
                return "car"
            }
            for p in peds where Physics.hit(b, Disc(x: p.x, y: p.y, r: 0.32)) { return "ped" }
            return nil
        }

        private func bump(pedestrian: Bool, impact: Double) {
            guard cool <= 0 else { return }
            cool = 0.7
            scratches += pedestrian ? 2 : 1
            bumps += 1
            shake = min(0.35, 0.1 + impact * 0.08)
            toast = pedestrian ? "Atsargiai! Pėsčiasis!" : "Įbrėžimas!"
            toastUntil = clock + 1.2
            let dir: Double = car.v >= 0 ? -1 : 1   // greitis jau apverstas – smūgis buvo priešingoje pusėje
            let fx = car.x + cos(car.a) * dir * CarSpec.length / 2
            let fy = car.y + sin(car.a) * dir * CarSpec.length / 2
            for _ in 0..<14 {
                sparks.append(Spark(x: fx, y: fy,
                                    vx: (Double.random(in: 0...1, using: &rng) - 0.5) * 6,
                                    vy: (Double.random(in: 0...1, using: &rng) - 0.5) * 6,
                                    life: 0.4 + Double.random(in: 0...0.3, using: &rng)))
            }
        }

        private func addSkids() {
            let c = car
            let lateral = c.v * c.v * abs(tan(c.steer)) / CarSpec.wheelbase
            guard lateral > 3.2 || (c.braking && abs(c.v) > 2.5) else { lastRear = nil; return }
            let ca = cos(c.a), sa = sin(c.a)
            let rx = c.x - ca * CarSpec.wheelbase / 2, ry = c.y - sa * CarSpec.wheelbase / 2
            let pts = [(rx - sa * 0.8, ry + ca * 0.8), (rx + sa * 0.8, ry - ca * 0.8)]
            if let last = lastRear {
                for k in 0..<2 { skids.append(Skid(x1: last[k].0, y1: last[k].1, x2: pts[k].0, y2: pts[k].1)) }
                if skids.count > 1600 { skids.removeFirst(skids.count - 1600) }
            }
            lastRear = pts
        }

        private func movePeople(_ dt: Double) {
            let guardBox = Physics.carBox(car, grow: 0.35)
            for i in peds.indices {
                var p = peds[i]
                let len = hypot(p.path.x2 - p.path.x1, p.path.y2 - p.path.y1)
                if p.wait > 0 {
                    p.wait -= dt
                    p.walking = false
                    peds[i] = p
                    continue
                }
                let nt = p.t + p.dir * p.path.speed * dt
                let f = Physics.clamp(nt / len, 0, 1)
                let nx = p.path.x1 + (p.path.x2 - p.path.x1) * f
                let ny = p.path.y1 + (p.path.y2 - p.path.y1) * f
                if Physics.hit(guardBox, Disc(x: nx, y: ny, r: 0.32)) {
                    p.walking = false   // pėsčiasis palaukia, kol pravažiuosi
                    peds[i] = p
                    continue
                }
                p.walking = true
                p.t = nt
                p.x = nx
                p.y = ny
                p.heading = atan2(p.path.y2 - p.path.y1, p.path.x2 - p.path.x1) + (p.dir < 0 ? Double.pi : 0)
                if p.t >= len {
                    p.t = len; p.dir = -1; p.wait = 1.5
                } else if p.t <= 0 {
                    p.t = 0; p.dir = 1; p.wait = 1.5
                }
                peds[i] = p
            }
        }

        private func moveTraffic(_ dt: Double) {
            let guardBox = Physics.carBox(car, grow: 0.2)
            for i in movers.indices {
                var m = movers[i]
                let nt = m.t + m.path.speed * dt
                let nx = m.path.x1 + (m.path.x2 - m.path.x1) * (nt / m.len)
                let ny = m.path.y1 + (m.path.y2 - m.path.y1) * (nt / m.len)
                let ahead = OBB(x: nx + cos(m.a) * 1.2, y: ny + sin(m.a) * 1.2, a: m.a,
                                hl: CarSpec.length / 2 + 1.2, hw: CarSpec.width / 2)
                if Physics.hit(ahead, guardBox) { continue }   // palaukia
                m.t = nt >= m.len ? 0 : nt
                m.x = m.path.x1 + (m.path.x2 - m.path.x1) * (m.t / m.len)
                m.y = m.path.y1 + (m.path.y2 - m.path.y1) * (m.t / m.len)
                movers[i] = m
            }
        }

        // MARK: - Parkavimo davikliai

        private func updateSensors(_ dt: Double) {
            guard gear == .reverse, !won else { rearDistance = 3; beepTimer = 0; return }
            rearDistance = measureRear()
            guard rearDistance < 2.5, car.v < -0.02 else { return }
            beepTimer -= dt
            if beepTimer <= 0 {
                beeps += 1
                beepTimer = rearDistance < 0.3 ? 0.09 : 0.1 + rearDistance * 0.28
            }
        }

        /// Kiek metrų laisva už galinio buferio (iki 3 m).
        private func measureRear() -> Double {
            let ca = cos(car.a), sa = sin(car.a)
            let rx = car.x - ca * CarSpec.length / 2, ry = car.y - sa * CarSpec.length / 2
            var d = 0.1
            while d <= 3.0 {
                let b = OBB(x: rx - ca * d / 2, y: ry - sa * d / 2, a: car.a, hl: d / 2, hw: CarSpec.width / 2)
                if colliders.hits(b) || dynamicHit(b) != nil { return d - 0.1 }
                d += 0.1
            }
            return 3
        }

        /// Galinės kameros kreipiamosios linijos: kairio ir dešinio galinio kampo kelias atbulai su dabartiniu vairu.
        func guidePath(side: Double, steps: Int = 30) -> [(Double, Double)] {
            var x = car.x, y = car.y, a = car.a
            let steer = car.steer, half = CarSpec.wheelbase / 2
            var pts: [(Double, Double)] = []
            for _ in 0...steps {
                let ca = cos(a), sa = sin(a)
                let bx = x - ca * CarSpec.length / 2, by = y - sa * CarSpec.length / 2
                pts.append((bx - sa * side * CarSpec.width / 2, by + ca * side * CarSpec.width / 2))
                let qx = x - ca * half - ca * 0.1, qy = y - sa * half - sa * 0.1
                let na = a - 0.1 / CarSpec.wheelbase * tan(steer)
                x = qx + cos(na) * half
                y = qy + sin(na) * half
                a = na
            }
            return pts
        }
    }
}
