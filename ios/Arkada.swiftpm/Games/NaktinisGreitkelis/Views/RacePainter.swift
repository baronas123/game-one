import SwiftUI

extension NaktinisGreitkelis {

    /// Piešia visą sceną į SwiftUI `Canvas` (pseudo-3D kelias, objektai, mašinos, efektai).
    enum RacePainter {
        static let drawDistance = 120

        private struct Projected {
            var x1: CGFloat, y1: CGFloat, w1: CGFloat, s1: CGFloat
            var x2: CGFloat, y2: CGFloat, w2: CGFloat, s2: CGFloat
            var clip: CGFloat
            var fog: Double
            var index: Int
            var visible: Bool
        }

        static func draw(_ e: RaceEngine, backdrop: Backdrop, in ctx: inout GraphicsContext, size: CGSize) {
            let p = e.proj
            let W = CGFloat(p.width), H = CGFloat(p.height), horizon = CGFloat(p.horizon), K = CGFloat(p.k)
            backdrop.prepare(size: size, horizon: horizon)

            var scene = ctx
            if e.shake > 0 {
                scene.translateBy(x: CGFloat.random(in: -7...7) * CGFloat(e.shake), y: CGFloat.random(in: -5...5) * CGFloat(e.shake))
            }
            scene.fill(Path(CGRect(x: -20, y: -20, width: W + 40, height: H + 40)), with: .color(Neon.night))
            backdrop.draw(in: &scene, farOffset: CGFloat(e.farOffset), cityOffset: CGFloat(e.cityOffset))

            // --- Kelias: projekcija iš arti į toli ---
            let road = e.road
            let segLen = Road.segmentLength
            let base = road.segment(at: e.position)
            let basePct = e.position.truncatingRemainder(dividingBy: segLen) / segLen
            let playerSeg = road.segment(at: e.position + p.playerZ)
            let playerPct = (e.position + p.playerZ).truncatingRemainder(dividingBy: segLen) / segLen
            let playerY = playerSeg.y1 + (playerSeg.y2 - playerSeg.y1) * playerPct
            let camX = e.playerX * Road.halfWidth
            let camY = playerY + p.cameraHeight
            let depth = Projection.cameraDepth

            var maxy = H
            var x: Double = 0
            var dx: Double = -(base.curve * basePct)
            var list: [Projected] = []
            list.reserveCapacity(drawDistance)

            var groundA = Path(), groundB = Path(), gridLines = Path()
            var rumbleA = Path(), rumbleB = Path(), roadA = Path(), roadB = Path(), lanes = Path()
            var fogBands: [(CGRect, Double)] = []

            func proj(_ worldY: Double, _ worldZ: Double, _ worldX: Double, _ camZ: Double) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
                let cz = worldZ - camZ
                let scale = depth / cz
                let sx = W / 2 + CGFloat(scale * (worldX - camX)) * K
                let sy = horizon - CGFloat(scale * (worldY - camY)) * K
                let sw = CGFloat(scale * Road.halfWidth) * K
                return (sx, sy, sw, CGFloat(scale))
            }

            for n in 0..<drawDistance {
                let seg = road.segments[(base.index + n) % road.segments.count]
                let looped = seg.index < base.index
                let camZ = e.position - (looped ? road.length : 0)
                let z1 = Double(seg.index) * segLen
                let a = proj(seg.y1, z1, x, camZ)
                let b = proj(seg.y2, z1 + segLen, x + dx, camZ)
                x += dx
                dx += seg.curve
                let fog = min(1, pow(Double(n) / Double(drawDistance), 1.6) * 1.15)
                let behind = z1 - camZ <= depth
                var item = Projected(x1: a.0, y1: a.1, w1: a.2, s1: a.3, x2: b.0, y2: b.1, w2: b.2, s2: b.3,
                                     clip: maxy, fog: fog, index: seg.index, visible: false)
                if !(behind || b.1 >= a.1 || b.1 >= maxy) {
                    item.visible = true
                    let light = (seg.index / 3) % 2 == 0
                    let y1 = ceil(a.1), y2 = floor(b.1)
                    let band = CGRect(x: 0, y: y2, width: W, height: y1 - y2 + 1)
                    if light { groundA.addRect(band) } else { groundB.addRect(band) }
                    if seg.index % 6 == 0 { gridLines.addRect(CGRect(x: 0, y: y2, width: W, height: max(1, (y1 - y2) * 0.12))) }
                    let r1 = a.2 / 6, r2 = b.2 / 6
                    func addRoad(_ rumble: inout Path, _ surface: inout Path) {
                        quad(&rumble, a.0 - a.2 - r1, y1, a.0 - a.2, y1, b.0 - b.2, y2, b.0 - b.2 - r2, y2)
                        quad(&rumble, a.0 + a.2 + r1, y1, a.0 + a.2, y1, b.0 + b.2, y2, b.0 + b.2 + r2, y2)
                        quad(&surface, a.0 - a.2, y1, a.0 + a.2, y1, b.0 + b.2, y2, b.0 - b.2, y2)
                    }
                    if light { addRoad(&rumbleA, &roadA) } else { addRoad(&rumbleB, &roadB) }
                    if light {
                        let l1 = a.2 / 32, l2 = b.2 / 32
                        for lane in 1..<Road.lanes {
                            let f = CGFloat(lane) * 2 / CGFloat(Road.lanes)
                            let lx1 = a.0 - a.2 + a.2 * f, lx2 = b.0 - b.2 + b.2 * f
                            quad(&lanes, lx1 - l1 / 2, y1, lx1 + l1 / 2, y1, lx2 + l2 / 2, y2, lx2 - l2 / 2, y2)
                        }
                    }
                    if fog > 0.05 { fogBands.append((band, fog)) }
                    maxy = a.1
                }
                list.append(item)
            }

            scene.fill(groundA, with: .color(Neon.groundA))
            scene.fill(groundB, with: .color(Neon.groundB))
            scene.fill(gridLines, with: .color(Neon.magenta.opacity(0.45)))
            scene.fill(rumbleA, with: .color(Neon.magenta))
            scene.fill(rumbleB, with: .color(Neon.rumbleB))
            scene.fill(roadA, with: .color(Neon.roadA))
            scene.fill(roadB, with: .color(Neon.roadB))
            scene.fill(lanes, with: .color(Neon.lane))
            // Rūkas – sugrupuotas į kelis permatomumo lygius
            for level in 1...5 {
                let lo = Double(level - 1) / 5, hi = Double(level) / 5
                var path = Path()
                for (rect, f) in fogBands where f > lo && f <= hi { path.addRect(rect) }
                if !path.isEmpty { scene.fill(path, with: .color(Neon.fog.opacity((lo + hi) / 2))) }
            }

            // --- Objektai: iš toli į arti ---
            var carsBySeg: [Int: [TrafficCar]] = [:]
            for car in e.cars { carsBySeg[road.index(at: car.z), default: []].append(car) }
            let gantrySeg = gantrySegmentIndex(e)

            for item in list.reversed() {
                guard item.s1 > 0, item.y1.isFinite else { continue }
                let seg = road.segments[item.index]
                let sc = item.s1 * K
                let alpha = 1 - item.fog * 0.85
                for sp in seg.sprites {
                    if sp.kind == .can && e.isCollected(segment: seg.index) { continue }
                    if item.y1 - 2 > item.clip { continue }
                    let sx = item.x1 + sc * CGFloat(sp.offset * Road.halfWidth)
                    var c = scene
                    c.opacity = alpha
                    if item.clip < H { c.clip(to: Path(CGRect(x: -50, y: -50, width: W + 100, height: item.clip + 50))) }
                    switch sp.kind {
                    case .lamp: drawLamp(&c, x: sx, y: item.y1, sc: sc, dir: sp.offset < 0 ? 1 : -1)
                    case .pine: drawPine(&c, x: sx, y: item.y1, sc: sc * CGFloat(sp.scale))
                    case .billboard: drawBillboard(&c, x: sx, y: item.y1, sc: sc, text: sp.text)
                    case .can: drawCan(&c, x: sx, y: item.y1, sc: sc, t: e.time)
                    }
                }
                if seg.index == gantrySeg { drawGantry(&scene, item: item, sc: sc, city: RaceEngine.cities[e.checkpoint % RaceEngine.cities.count]) }
                if let cars = carsBySeg[seg.index] {
                    for car in cars {
                        let pct = CGFloat(car.z.truncatingRemainder(dividingBy: segLen) / segLen)
                        let s = (item.s1 + (item.s2 - item.s1) * pct) * K
                        let cx = item.x1 + (item.x2 - item.x1) * pct + s * CGFloat(car.offset * Road.halfWidth)
                        let cy = item.y1 + (item.y2 - item.y1) * pct
                        let w = s * (car.isTruck ? 1050 : 900)
                        if w < 2 { continue }
                        var c = scene
                        c.opacity = alpha
                        if item.clip < H { c.clip(to: Path(CGRect(x: -50, y: -50, width: W + 100, height: item.clip + 50))) }
                        drawCar(&c, cx: cx, by: cy, w: w, rgb: Neon.cars[car.colorIndex % Neon.cars.count],
                                truck: car.isTruck, player: false, tilt: 0, nitro: false, braking: false)
                    }
                }
            }

            if e.nitroOn { speedLines(&scene, W: W, H: H, horizon: horizon, t: e.time, reduced: e.reducedMotion) }

            // --- Žaidėjas ---
            let pw = CGFloat(Road.halfWidth) * K / CGFloat(p.cameraHeight) * (900 / CGFloat(Road.halfWidth)) * 1.28
            let bounce = e.speed > 0 ? CGFloat(sin(e.time * 30) * 1.2 * (e.speed / RaceEngine.maxSpeed)) : 0
            drawCar(&scene, cx: W / 2 + CGFloat(e.steerVisual) * 4, by: horizon + K + bounce, w: pw,
                    rgb: (1.0, 0.24, 0.65), truck: false, player: true, tilt: CGFloat(e.steerVisual),
                    nitro: e.nitroOn, braking: e.crashFlash > 0 || e.braking)

            // --- Efektai ---
            if e.crashFlash > 0 { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.red.opacity(e.crashFlash))) }
            if e.pickupFlash > 0 { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Neon.cyan.opacity(e.pickupFlash * 0.4))) }
            let edge: Color = e.nitroOn ? Neon.cyan.opacity(0.28) : Color.black.opacity(0.45)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                Gradient(colors: [Color.clear, edge]), center: CGPoint(x: W / 2, y: H * 0.55),
                startRadius: min(W, H) * 0.35, endRadius: max(W, H) * 0.8))
        }

        // MARK: - Pagalbinės

        private static func quad(_ path: inout Path, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat,
                                 _ x3: CGFloat, _ y3: CGFloat, _ x4: CGFloat, _ y4: CGFloat) {
            path.move(to: CGPoint(x: x1, y: y1))
            path.addLine(to: CGPoint(x: x2, y: y2))
            path.addLine(to: CGPoint(x: x3, y: y3))
            path.addLine(to: CGPoint(x: x4, y: y4))
            path.closeSubpath()
        }

        /// Segmentas, ties kuriuo stovi kito miesto žalia kryptis (arba -1).
        private static func gantrySegmentIndex(_ e: RaceEngine) -> Int {
            let ahead = Double(e.checkpoint + 1) * RaceEngine.checkpointGap - e.distance
            guard ahead >= 0, ahead <= Double(drawDistance) * Road.segmentLength else { return -1 }
            return e.road.index(at: e.position + e.proj.playerZ + ahead)
        }

        private static func glow(_ c: inout GraphicsContext, at p: CGPoint, radius: CGFloat, color: Color, strength: Double) {
            c.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                   with: .radialGradient(Gradient(colors: [color.opacity(strength), color.opacity(strength * 0.45), color.opacity(0)]),
                                         center: p, startRadius: 0, endRadius: radius))
        }

        private static func drawLamp(_ c: inout GraphicsContext, x: CGFloat, y: CGFloat, sc: CGFloat, dir: CGFloat) {
            let h = 3200 * sc, arm = 600 * sc, w = max(1, 50 * sc)
            guard h >= 3 else { return }
            let pole = Color(red: 0.23, green: 0.19, blue: 0.31)
            c.fill(Path(CGRect(x: x - w / 2, y: y - h, width: w, height: h)), with: .color(pole))
            var a = Path()
            a.move(to: CGPoint(x: x, y: y - h))
            a.addLine(to: CGPoint(x: x + dir * arm, y: y - h - 80 * sc))
            c.stroke(a, with: .color(pole), lineWidth: w)
            glow(&c, at: CGPoint(x: x + dir * arm, y: y - h - 60 * sc), radius: max(3, 520 * sc),
                 color: Color(red: 1, green: 0.78, blue: 0.5), strength: 0.9)
        }

        private static func drawPine(_ c: inout GraphicsContext, x: CGFloat, y: CGFloat, sc: CGFloat) {
            let h = 4200 * sc, w = 1500 * sc
            guard h >= 3 else { return }
            var p = Path()
            for i in 0..<3 {
                let fi = CGFloat(i)
                let ty = y - h * (0.35 + fi * 0.3), by = y - h * (0.05 + fi * 0.27), bw = w * (1 - fi * 0.25) / 2
                p.move(to: CGPoint(x: x, y: ty - h * 0.12))
                p.addLine(to: CGPoint(x: x + bw, y: by))
                p.addLine(to: CGPoint(x: x - bw, y: by))
                p.closeSubpath()
            }
            p.addRect(CGRect(x: x - w * 0.04, y: y - h * 0.1, width: w * 0.08, height: h * 0.1))
            c.fill(p, with: .color(Neon.pine))
        }

        private static func drawBillboard(_ c: inout GraphicsContext, x: CGFloat, y: CGFloat, sc: CGFloat, text: String) {
            let w = 3200 * sc, h = 1300 * sc, top = y - 3400 * sc
            guard w >= 6 else { return }
            let post = Color(red: 0.16, green: 0.13, blue: 0.25)
            c.fill(Path(CGRect(x: x - w * 0.3, y: top + h, width: w * 0.04, height: y - top - h)), with: .color(post))
            c.fill(Path(CGRect(x: x + w * 0.26, y: top + h, width: w * 0.04, height: y - top - h)), with: .color(post))
            let board = CGRect(x: x - w / 2, y: top, width: w, height: h)
            c.fill(Path(board), with: .color(Color(red: 0.05, green: 0.02, blue: 0.13)))
            c.stroke(Path(board), with: .color(Neon.cyan), lineWidth: max(1, 60 * sc))
            if h > 6 {
                c.draw(Text(text).font(.system(size: h * 0.42, weight: .bold, design: .rounded)).foregroundColor(Neon.magenta),
                       at: CGPoint(x: x, y: top + h / 2))
            }
        }

        private static func drawCan(_ c: inout GraphicsContext, x: CGFloat, y: CGFloat, sc: CGFloat, t: Double) {
            let w = 260 * sc, h = 520 * sc
            guard w >= 2 else { return }
            let top = y - h - 200 * sc + CGFloat(sin(t * 5)) * 80 * sc
            glow(&c, at: CGPoint(x: x, y: top + h / 2), radius: w * 2.2, color: Neon.cyan, strength: 0.55)
            c.fill(Path(roundedRect: CGRect(x: x - w / 2, y: top, width: w, height: h), cornerRadius: w * 0.35), with: .color(Neon.cyan))
            c.fill(Path(CGRect(x: x - w * 0.15, y: top - h * 0.12, width: w * 0.3, height: h * 0.14)), with: .color(.white))
            if w > 10 {
                c.draw(Text("N₂O").font(.system(size: w * 0.38, weight: .bold)).foregroundColor(Neon.night),
                       at: CGPoint(x: x, y: top + h * 0.55))
            }
        }

        /// Žalia LT magistralės kryptis virš kelio su kito miesto pavadinimu.
        private static func drawGantry(_ ctx: inout GraphicsContext, item: Projected, sc: CGFloat, city: String) {
            let w = item.w1 * 2.5, h = 1100 * sc, top = item.y1 - 4600 * sc
            guard w >= 8 else { return }
            var c = ctx
            c.opacity = 1 - item.fog * 0.8
            if item.clip < item.y1 + 2000 { c.clip(to: Path(CGRect(x: -50, y: -50, width: 10_000, height: item.clip + 50))) }
            let steel = Color(red: 0.29, green: 0.27, blue: 0.38)
            let pw = max(2, 90 * sc)
            c.fill(Path(CGRect(x: item.x1 - item.w1 * 1.2 - pw, y: top, width: pw, height: item.y1 - top)), with: .color(steel))
            c.fill(Path(CGRect(x: item.x1 + item.w1 * 1.2, y: top, width: pw, height: item.y1 - top)), with: .color(steel))
            c.fill(Path(CGRect(x: item.x1 - item.w1 * 1.2, y: top + h * 0.2, width: item.w1 * 2.4, height: pw)), with: .color(steel))
            let board = Path(roundedRect: CGRect(x: item.x1 - w * 0.36, y: top - h * 0.1, width: w * 0.72, height: h), cornerRadius: h * 0.08)
            c.fill(board, with: .color(Neon.sign))
            c.stroke(board, with: .color(.white), lineWidth: max(1, 40 * sc))
            c.draw(Text(city.uppercased()).font(.system(size: max(4, h * 0.46), weight: .bold)).foregroundColor(.white),
                   at: CGPoint(x: item.x1, y: top + h * 0.4))
        }

        /// Mašina iš galo: kėbulas, galinis stiklas, žibintai, numeris, nitro liepsnos.
        static func drawCar(_ ctx: inout GraphicsContext, cx: CGFloat, by: CGFloat, w: CGFloat, rgb: (Double, Double, Double),
                            truck: Bool, player: Bool, tilt: CGFloat, nitro: Bool, braking: Bool) {
            var c = ctx
            c.translateBy(x: cx, y: by)
            c.rotate(by: .radians(Double(tilt) * 0.035))
            let h = w * (truck ? 0.95 : 0.52)
            let body = Color(red: rgb.0, green: rgb.1, blue: rgb.2)
            func shade(_ a: Double) -> Color { Color(red: rgb.0 * (1 + a), green: rgb.1 * (1 + a), blue: rgb.2 * (1 + a)) }

            c.fill(Path(ellipseIn: CGRect(x: -w * 0.55, y: -w * 0.07, width: w * 1.1, height: w * 0.14)), with: .color(.black.opacity(0.45)))
            let tyre = Color(red: 0.02, green: 0.01, blue: 0.04)
            c.fill(Path(CGRect(x: -w * 0.46, y: -h * 0.2, width: w * 0.17, height: h * 0.22)), with: .color(tyre))
            c.fill(Path(CGRect(x: w * 0.29, y: -h * 0.2, width: w * 0.17, height: h * 0.22)), with: .color(tyre))

            if truck {
                c.fill(Path(roundedRect: CGRect(x: -w / 2, y: -h, width: w, height: h * 0.86), cornerRadius: w * 0.03),
                       with: .color(Color(red: 0.85, green: 0.84, blue: 0.90)))
                c.fill(Path(CGRect(x: -w / 2, y: -h * 0.22, width: w, height: h * 0.08)), with: .color(Color(red: 0.72, green: 0.70, blue: 0.79)))
                c.fill(Path(CGRect(x: -w / 2, y: -h * 0.98, width: w, height: h * 0.06)), with: .color(body))
            } else {
                var shell = Path()
                shell.move(to: CGPoint(x: -w * 0.5, y: -h * 0.12))
                shell.addLine(to: CGPoint(x: -w * 0.5, y: -h * 0.5))
                shell.addQuadCurve(to: CGPoint(x: -w * 0.4, y: -h * 0.64), control: CGPoint(x: -w * 0.48, y: -h * 0.62))
                shell.addLine(to: CGPoint(x: -w * 0.3, y: -h * 0.98))
                shell.addQuadCurve(to: CGPoint(x: w * 0.3, y: -h * 0.98), control: CGPoint(x: 0, y: -h * 1.04))
                shell.addLine(to: CGPoint(x: w * 0.4, y: -h * 0.64))
                shell.addQuadCurve(to: CGPoint(x: w * 0.5, y: -h * 0.5), control: CGPoint(x: w * 0.48, y: -h * 0.62))
                shell.addLine(to: CGPoint(x: w * 0.5, y: -h * 0.12))
                shell.closeSubpath()
                c.fill(shell, with: .linearGradient(Gradient(stops: [
                    .init(color: shade(-0.25), location: 0), .init(color: body, location: 0.45), .init(color: shade(-0.55), location: 1)
                ]), startPoint: CGPoint(x: 0, y: -h), endPoint: .zero))
                var glass = Path()
                glass.move(to: CGPoint(x: -w * 0.34, y: -h * 0.66))
                glass.addLine(to: CGPoint(x: -w * 0.26, y: -h * 0.93))
                glass.addLine(to: CGPoint(x: w * 0.26, y: -h * 0.93))
                glass.addLine(to: CGPoint(x: w * 0.34, y: -h * 0.66))
                glass.closeSubpath()
                c.fill(glass, with: .linearGradient(Gradient(colors: [Color(red: 0.16, green: 0.13, blue: 0.25), Color(red: 0.04, green: 0.03, blue: 0.09)]),
                                                    startPoint: CGPoint(x: 0, y: -h * 0.95), endPoint: CGPoint(x: 0, y: -h * 0.65)))
                c.fill(Path(CGRect(x: -w * 0.5, y: -h * 0.22, width: w, height: h * 0.1)), with: .color(shade(-0.65)))
            }

            // galiniai žibintai
            let lw = w * 0.24, lh = max(1.5, h * (truck ? 0.06 : 0.1)), ly = -h * (truck ? 0.3 : 0.47)
            if w > 6 {
                let strength: Double = player ? (braking ? 0.35 : 0.2) : 0.2
                glow(&c, at: CGPoint(x: 0, y: ly), radius: w * 0.75, color: Color(red: 1, green: 0.12, blue: 0.24), strength: strength)
            }
            let tail = Color(red: 1, green: 0.14, blue: 0.28)
            c.fill(Path(CGRect(x: -w * 0.47, y: ly, width: lw, height: lh)), with: .color(tail))
            c.fill(Path(CGRect(x: w * 0.47 - lw, y: ly, width: lw, height: lh)), with: .color(tail))
            let core = Color(red: 1, green: 0.86, blue: 0.9).opacity(0.9)
            c.fill(Path(CGRect(x: -w * 0.45, y: ly + lh * 0.3, width: lw * 0.35, height: lh * 0.4)), with: .color(core))
            c.fill(Path(CGRect(x: w * 0.45 - lw * 0.35, y: ly + lh * 0.3, width: lw * 0.35, height: lh * 0.4)), with: .color(core))

            // numeris
            if w > 30 {
                let nw = w * 0.2, nh = w * 0.055, ny = -h * (truck ? 0.2 : 0.33)
                c.fill(Path(CGRect(x: -nw / 2, y: ny, width: nw, height: nh)), with: .color(Color(white: 0.95)))
                c.fill(Path(CGRect(x: -nw / 2, y: ny, width: nw * 0.16, height: nh)), with: .color(Color(red: 0.11, green: 0.25, blue: 0.66)))
                if w > 70 {
                    c.draw(Text(player ? "NGR 001" : "LT").font(.system(size: nh * 0.72, weight: .bold)).foregroundColor(.black),
                           at: CGPoint(x: nw * 0.08, y: ny + nh / 2))
                }
            }

            // nitro liepsnos
            if player && nitro {
                for sx in [-0.28, 0.28] {
                    let fl = w * CGFloat(0.25 + Double.random(in: 0..<0.2))
                    let fx = w * CGFloat(sx), fy = -h * 0.14
                    let rect = CGRect(x: fx - w * 0.07, y: fy + fl * 0.25 - fl * 0.5, width: w * 0.14, height: fl)
                    c.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(colors: [.white.opacity(0.95), Neon.cyan.opacity(0.85), Color(red: 0.7, green: 0.3, blue: 1).opacity(0.4), .clear]),
                        center: CGPoint(x: fx, y: fy), startRadius: 0, endRadius: fl))
                }
            }
        }

        private static func speedLines(_ c: inout GraphicsContext, W: CGFloat, H: CGFloat, horizon: CGFloat, t: Double, reduced: Bool) {
            let R = hypot(W, H)
            var p = Path()
            let count = reduced ? 8 : 40
            for i in 0..<count {
                let a = Double(i) * 2.399 + Double(i % 7)
                let phase = (t * 1.6 + Double(i) * 0.137).truncatingRemainder(dividingBy: 1)
                let r1 = CGFloat(0.15 + phase * 0.85) * R * 0.6
                let r2 = r1 + CGFloat(0.1 + Double(i % 5) * 0.05) * R * 0.4
                p.move(to: CGPoint(x: W / 2 + CGFloat(cos(a)) * r1, y: horizon + CGFloat(sin(a)) * r1 * 0.7))
                p.addLine(to: CGPoint(x: W / 2 + CGFloat(cos(a)) * r2, y: horizon + CGFloat(sin(a)) * r2 * 0.7))
            }
            c.stroke(p, with: .color(Color(red: 0.78, green: 0.96, blue: 1).opacity(0.35)), lineWidth: 1.5)
        }
    }
}
