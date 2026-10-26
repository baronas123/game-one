import Foundation

extension ParkavimoMeistras {

    // MARK: - Lygio aprašas (užpildomas Levels.swift)

    enum Theme { case asphalt, cobble, garage }
    enum WallKind { case curb, grass, planter, pillar, wall, building, roof }
    enum PaintStyle { case white, yellow, dashed }

    struct Pose { var x: Double; var y: Double; var deg: Double }
    /// Tikslo vieta. `deg` – kur turi žiūrėti mašinos priekis; `anyDirection` – tinka ir priešinga kryptis.
    struct Spot { var x: Double; var y: Double; var deg: Double; var w: Double; var l: Double; var anyDirection: Bool }
    struct Wall { var x: Double; var y: Double; var w: Double; var h: Double; var kind: WallKind }
    struct ParkedCar { var x: Double; var y: Double; var deg: Double; var color: UInt32 }
    struct Tree { var x: Double; var y: Double; var r: Double }
    struct Bay { var x: Double; var y: Double; var deg: Double }
    struct Paint { var x1: Double; var y1: Double; var x2: Double; var y2: Double; var style: PaintStyle }
    struct Zebra { var x: Double; var y: Double; var w: Double; var h: Double }
    struct PedPath { var x1: Double; var y1: Double; var x2: Double; var y2: Double; var speed: Double }
    struct MoverPath { var x1: Double; var y1: Double; var x2: Double; var y2: Double; var speed: Double; var color: UInt32 }

    struct Level {
        var name: String
        var place: String
        var tip: String
        var theme: Theme
        var w: Double
        var h: Double
        var par: Double
        var start: Pose
        var spot: Spot
        var walls: [Wall]
        var cars: [ParkedCar]
        var trees: [Tree]
        var bays: [Bay]
        var paint: [Paint]
        var zebras: [Zebra]
        var peds: [PedPath]
        var movers: [MoverPath]
    }

    // MARK: - Mašina

    enum CarSpec {
        static let length = 4.4
        static let width = 1.8
        static let wheelbase = 2.7
        static let maxSteer = 0.62
        static let accel = 3.2
        static let brake = 8.5
        static let maxForward = 6.5
        static let maxReverse = 3.2
        static let drag = 1.6
    }

    /// (x, y) – mašinos centras, `a` – kryptis radianais, `v` – greitis m/s (neigiamas – atbulai).
    struct CarState {
        var x: Double
        var y: Double
        var a: Double
        var v: Double = 0
        var steer: Double = 0
        var braking = false
    }

    struct Controls {
        /// -1 (kairėn) … 1 (dešinėn)
        var steer: Double = 0
        /// true – vairas valdomas tiesiogiai (lietimu ar polinkiu), sukasi greičiau
        var direct = false
        var gas = false
        var rev = false
        var hand = false
    }

    /// Pasuktas stačiakampis: `hl` – pusė ilgio išilgai krypties, `hw` – pusė pločio.
    struct OBB { var x: Double; var y: Double; var a: Double; var hl: Double; var hw: Double }
    struct Disc { var x: Double; var y: Double; var r: Double }

    enum Physics {
        static func angNorm(_ a: Double) -> Double {
            var r = (a + .pi).truncatingRemainder(dividingBy: 2 * .pi)
            if r < 0 { r += 2 * .pi }
            return r - .pi
        }

        static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }

        /// Dviračio modelis: mašina sukasi apie galinę ašį – kaip tikra.
        static func step(_ c: CarState, _ inp: Controls, dt: Double) -> CarState {
            var n = c
            let target = clamp(inp.steer, -1, 1) * CarSpec.maxSteer
            let rate = inp.direct ? 4.2 : 2.6
            n.steer += clamp(target - n.steer, -rate * dt, rate * dt)

            let speed = abs(n.v)
            let sign: Double = n.v > 0 ? 1 : (n.v < 0 ? -1 : 0)
            let acc: Double
            if inp.hand {
                acc = -sign * min(CarSpec.brake * 1.3, speed / dt)
            } else if inp.gas && !inp.rev {
                acc = n.v < -0.05 ? CarSpec.brake : CarSpec.accel
            } else if inp.rev && !inp.gas {
                acc = n.v > 0.05 ? -CarSpec.brake : -CarSpec.accel
            } else {
                acc = -sign * min(CarSpec.drag, speed / dt)
            }
            let before = n.v
            n.v = clamp(n.v + acc * dt, -CarSpec.maxReverse, CarSpec.maxForward)
            if (inp.gas && before < -0.05 && n.v > 0) || (inp.rev && before > 0.05 && n.v < 0) { n.v = 0 }
            n.braking = (inp.rev && before > 0.05) || (inp.gas && before < -0.05) || inp.hand

            let half = CarSpec.wheelbase / 2
            var rx = n.x - cos(n.a) * half
            var ry = n.y - sin(n.a) * half
            rx += n.v * cos(n.a) * dt
            ry += n.v * sin(n.a) * dt
            n.a = angNorm(n.a + n.v / CarSpec.wheelbase * tan(n.steer) * dt)
            n.x = rx + cos(n.a) * half
            n.y = ry + sin(n.a) * half
            return n
        }

        static func carBox(_ c: CarState, grow: Double = 0) -> OBB {
            OBB(x: c.x, y: c.y, a: c.a, hl: CarSpec.length / 2 + grow, hw: CarSpec.width / 2 + grow)
        }

        private static func project(_ b: OBB, _ ax: Double, _ ay: Double) -> (Double, Double) {
            let c = cos(b.a), s = sin(b.a)
            let m = b.x * ax + b.y * ay
            let r = b.hl * abs(c * ax + s * ay) + b.hw * abs(-s * ax + c * ay)
            return (m - r, m + r)
        }

        /// Atskiriančiosios ašies teorema dviem pasuktiems stačiakampiams.
        static func hit(_ a: OBB, _ b: OBB) -> Bool {
            let axes: [(Double, Double)] = [
                (cos(a.a), sin(a.a)), (-sin(a.a), cos(a.a)),
                (cos(b.a), sin(b.a)), (-sin(b.a), cos(b.a))
            ]
            for (ax, ay) in axes {
                let p = project(a, ax, ay), q = project(b, ax, ay)
                if p.1 <= q.0 || q.1 <= p.0 { return false }
            }
            return true
        }

        static func hit(_ b: OBB, _ circle: Disc) -> Bool {
            let c = cos(b.a), s = sin(b.a)
            let dx = circle.x - b.x, dy = circle.y - b.y
            let lx = dx * c + dy * s, ly = -dx * s + dy * c
            let qx = clamp(lx, -b.hl, b.hl), qy = clamp(ly, -b.hw, b.hw)
            let ex = lx - qx, ey = ly - qy
            return ex * ex + ey * ey < circle.r * circle.r
        }

        static func spotCheck(_ level: Level, _ c: CarState) -> (inside: Bool, aligned: Bool) {
            let s = level.spot
            let sa = s.deg * .pi / 180, cs = cos(sa), sn = sin(sa)
            let ca = cos(c.a), sA = sin(c.a)
            var inside = true
            for (u, v) in [(1.0, 1.0), (1.0, -1.0), (-1.0, 1.0), (-1.0, -1.0)] {
                let px = c.x + ca * u * CarSpec.length / 2 - sA * v * CarSpec.width / 2
                let py = c.y + sA * u * CarSpec.length / 2 + ca * v * CarSpec.width / 2
                let dx = px - s.x, dy = py - s.y
                let lx = dx * cs + dy * sn, ly = -dx * sn + dy * cs
                if abs(lx) > s.l / 2 || abs(ly) > s.w / 2 { inside = false; break }
            }
            var diff = abs(angNorm(c.a - sa))
            if s.anyDirection { diff = min(diff, .pi - diff) }
            return (inside, diff < 12 * .pi / 180)
        }

        static func stars(time: Double, scratches: Int, par: Double) -> Int {
            var s = 3
            if scratches > 0 { s -= 1 }
            if scratches > 2 { s -= 1 }
            if time > par { s -= 1 }
            return max(1, s)
        }
    }

    /// Visos nejudančios kliūtys (sienos, stovinčios mašinos, medžių kamienai, pasaulio kraštai).
    struct Colliders {
        var boxes: [OBB] = []
        var circles: [Disc] = []

        init(level: Level) {
            for w in level.walls {
                boxes.append(OBB(x: w.x + w.w / 2, y: w.y + w.h / 2, a: 0, hl: w.w / 2, hw: w.h / 2))
            }
            for c in level.cars {
                boxes.append(OBB(x: c.x, y: c.y, a: c.deg * .pi / 180, hl: CarSpec.length / 2, hw: CarSpec.width / 2))
            }
            let w = level.w, h = level.h
            boxes.append(OBB(x: w / 2, y: -5, a: 0, hl: w, hw: 5))
            boxes.append(OBB(x: w / 2, y: h + 5, a: 0, hl: w, hw: 5))
            boxes.append(OBB(x: -5, y: h / 2, a: 0, hl: 5, hw: h))
            boxes.append(OBB(x: w + 5, y: h / 2, a: 0, hl: 5, hw: h))
            circles = level.trees.map { Disc(x: $0.x, y: $0.y, r: 0.45) }
        }

        func hits(_ b: OBB) -> Bool {
            for o in boxes where Physics.hit(b, o) { return true }
            for c in circles where Physics.hit(b, c) { return true }
            return false
        }
    }
}
