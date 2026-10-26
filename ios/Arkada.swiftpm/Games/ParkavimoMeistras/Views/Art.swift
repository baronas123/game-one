import SwiftUI

extension ParkavimoMeistras {

    static func rgb(_ hex: UInt32, shade f: Double = 0) -> Color {
        var r = Double((hex >> 16) & 0xFF) / 255
        var g = Double((hex >> 8) & 0xFF) / 255
        var b = Double(hex & 0xFF) / 255
        if f < 0 {
            r *= 1 + f; g *= 1 + f; b *= 1 + f
        } else {
            r += (1 - r) * f; g += (1 - g) * f; b += (1 - b) * f
        }
        return Color(red: r, green: g, blue: b)
    }

    static let playerColor: UInt32 = 0xFFC21A

    /// Lygio dekoracijos, sugeneruotos vieną kartą (kad kiekvieną kadrą nereiktų skaičiuoti).
    struct Scenery {
        var specksLight = Path()
        var specksDark = Path()
        var stones = Path()
        var joints = Path()
        var cracks = Path()
        var grassLight = Path()
        var grassDark = Path()
        var whitePaint = Path()
        var yellowPaint = Path()
        var dashedPaint = Path()
        var zebraStripes = Path()
        var stains: [Disc] = []
        var flowers: [(Disc, Int)] = []
        var canopies: [[Disc]] = []

        init(level: Level) {
            var rng = SplitMix64(seed: 4242 &+ UInt64(level.w * 13 + level.h))
            func r() -> Double { Double.random(in: 0..<1, using: &rng) }
            let w = level.w, h = level.h
            let speck = 0.06

            switch level.theme {
            case .cobble:
                var y = 0.0, row = 0
                while y < h {
                    joints.move(to: CGPoint(x: 0, y: y))
                    joints.addLine(to: CGPoint(x: w, y: y))
                    var x = row % 2 == 0 ? 0.0 : 0.17
                    while x < w {
                        joints.move(to: CGPoint(x: x, y: y))
                        joints.addLine(to: CGPoint(x: x, y: y + 0.32))
                        if r() < 0.35 {
                            stones.addRoundedRect(in: CGRect(x: x + 0.03, y: y + 0.03, width: 0.28, height: 0.26),
                                                  cornerSize: CGSize(width: 0.08, height: 0.08))
                        }
                        x += 0.34
                    }
                    y += 0.32
                    row += 1
                }
            case .asphalt, .garage:
                let density: Double = level.theme == .garage ? 4 : 7
                let count = Int(w * h * density)
                for _ in 0..<count {
                    specksLight.addRect(CGRect(x: r() * w, y: r() * h, width: speck, height: speck))
                    specksDark.addRect(CGRect(x: r() * w, y: r() * h, width: speck, height: speck))
                }
                for _ in 0..<(level.theme == .garage ? 7 : 5) {
                    stains.append(Disc(x: r() * w, y: level.theme == .garage ? 8 + r() * 12 : r() * h, r: 0.7 + r()))
                }
                if level.theme == .asphalt {
                    for _ in 0..<6 {
                        var x = r() * w, y = r() * h
                        cracks.move(to: CGPoint(x: x, y: y))
                        for _ in 0..<6 {
                            x += (r() - 0.5) * 1.2
                            y += (r() - 0.5) * 1.2
                            cracks.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
            }

            for wall in level.walls where wall.kind == .grass {
                for _ in 0..<Int(wall.w * wall.h * 25) {
                    grassLight.addRect(CGRect(x: wall.x + r() * wall.w, y: wall.y + r() * wall.h, width: 0.09, height: 0.09))
                    grassDark.addRect(CGRect(x: wall.x + r() * wall.w, y: wall.y + r() * wall.h, width: 0.09, height: 0.09))
                }
            }
            for wall in level.walls where wall.kind == .planter {
                for _ in 0..<Int(wall.w * 3) {
                    let d = Disc(x: wall.x + 0.3 + r() * (wall.w - 0.6), y: wall.y + 0.3 + r() * (wall.h - 0.6), r: 0.12 + r() * 0.18)
                    flowers.append((d, Int(r() * 4)))
                }
            }

            for p in level.paint {
                switch p.style {
                case .white:
                    whitePaint.move(to: CGPoint(x: p.x1, y: p.y1)); whitePaint.addLine(to: CGPoint(x: p.x2, y: p.y2))
                case .yellow:
                    yellowPaint.move(to: CGPoint(x: p.x1, y: p.y1)); yellowPaint.addLine(to: CGPoint(x: p.x2, y: p.y2))
                case .dashed:
                    dashedPaint.move(to: CGPoint(x: p.x1, y: p.y1)); dashedPaint.addLine(to: CGPoint(x: p.x2, y: p.y2))
                }
            }
            for b in level.bays {
                let a = b.deg * .pi / 180, c = cos(a), s = sin(a), bw = 1.35, bl = 2.7
                for side in [-1.0, 1.0] {
                    let ox = -s * bw * side, oy = c * bw * side
                    let from = CGPoint(x: b.x + ox - c * bl, y: b.y + oy - s * bl)
                    let to = CGPoint(x: b.x + ox + c * bl, y: b.y + oy + s * bl)
                    if level.theme == .garage {
                        yellowPaint.move(to: from); yellowPaint.addLine(to: to)
                    } else {
                        whitePaint.move(to: from); whitePaint.addLine(to: to)
                    }
                }
            }
            for z in level.zebras {
                var x = z.x + 0.3
                while x < z.x + z.w - 0.3 {
                    zebraStripes.addRect(CGRect(x: x, y: z.y, width: 0.5, height: z.h))
                    x += 1.0
                }
            }
            for (i, t) in level.trees.enumerated() {
                var tr = SplitMix64(seed: 99 &+ UInt64(i) &* 31)
                var blobs: [Disc] = []
                for k in 0..<7 {
                    let ang = Double(k) / 7 * 2 * .pi + Double.random(in: 0..<1, using: &tr)
                    let d = t.r * (0.35 + Double.random(in: 0..<0.25, using: &tr))
                    blobs.append(Disc(x: t.x + cos(ang) * d, y: t.y + sin(ang) * d,
                                      r: t.r * (0.45 + Double.random(in: 0..<0.2, using: &tr))))
                }
                canopies.append(blobs)
            }
        }
    }

    enum Art {

        // MARK: - Visas pasaulis

        static func world(_ ctx: GraphicsContext, sim: Simulation, scenery: Scenery, time: Double, hidePlayer: Bool = false) {
            let lv = sim.level
            ground(ctx, lv, scenery)
            skids(ctx, sim.skids)
            spot(ctx, sim: sim, time: time)
            for m in sim.movers { car(ctx, x: m.x, y: m.y, a: m.a, color: m.path.color) }
            for p in sim.peds { pedestrian(ctx, p, time: time) }
            if !hidePlayer {
                let c = sim.car
                car(ctx, x: c.x, y: c.y, a: c.a, color: ParkavimoMeistras.playerColor, steer: c.steer,
                    brake: c.braking, reverse: c.v < -0.05 || sim.gear == .reverse, player: true)
            }
            roofs(ctx, lv, scenery)
            for s in sim.sparks {
                ctx.fill(Path(CGRect(x: s.x - 0.05, y: s.y - 0.05, width: 0.1, height: 0.1)),
                         with: .color(Color(red: 1, green: 0.8, blue: 0.35).opacity(min(1, s.life * 2))))
            }
        }

        // MARK: - Žemė

        static func ground(_ ctx: GraphicsContext, _ lv: Level, _ sc: Scenery) {
            let rect = CGRect(x: 0, y: 0, width: lv.w, height: lv.h)
            switch lv.theme {
            case .asphalt:
                ctx.fill(Path(rect), with: .color(Color(red: 0.22, green: 0.235, blue: 0.26)))
                ctx.fill(sc.specksLight, with: .color(.white.opacity(0.07)))
                ctx.fill(sc.specksDark, with: .color(.black.opacity(0.16)))
                stains(ctx, sc.stains, opacity: 0.22)
                ctx.stroke(sc.cracks, with: .color(.black.opacity(0.25)), lineWidth: 0.03)
            case .garage:
                ctx.fill(Path(rect), with: .color(Color(red: 0.385, green: 0.4, blue: 0.425)))
                ctx.fill(sc.specksLight, with: .color(.white.opacity(0.05)))
                ctx.fill(sc.specksDark, with: .color(.black.opacity(0.08)))
                stains(ctx, sc.stains, opacity: 0.35)
            case .cobble:
                ctx.fill(Path(rect), with: .color(Color(red: 0.43, green: 0.39, blue: 0.345)))
                ctx.fill(sc.stones, with: .color(Color(red: 0.52, green: 0.48, blue: 0.42)))
                ctx.stroke(sc.joints, with: .color(Color(red: 0.25, green: 0.22, blue: 0.19)), lineWidth: 0.05)
            }
            ctx.fill(sc.zebraStripes, with: .color(Color(white: 0.95).opacity(0.85)))
            let paint = Color(red: 0.96, green: 0.95, blue: 0.92).opacity(0.82)
            let yellow = Color(red: 0.91, green: 0.73, blue: 0.14)
            ctx.stroke(sc.whitePaint, with: .color(paint), lineWidth: 0.12)
            ctx.stroke(sc.yellowPaint, with: .color(yellow), lineWidth: 0.12)
            ctx.stroke(sc.dashedPaint, with: .color(paint), style: StrokeStyle(lineWidth: 0.12, dash: [1.5, 1.5]))

            for w in lv.walls {
                let r = CGRect(x: w.x, y: w.y, width: w.w, height: w.h)
                switch w.kind {
                case .curb:
                    ctx.fill(Path(r), with: .color(Color(red: 0.62, green: 0.64, blue: 0.66)))
                    ctx.stroke(Path(r.insetBy(dx: 0.1, dy: 0.1)), with: .color(Color(red: 0.83, green: 0.84, blue: 0.85)), lineWidth: 0.2)
                case .grass:
                    ctx.fill(Path(r), with: .color(Color(red: 0.25, green: 0.48, blue: 0.21)))
                    ctx.stroke(Path(r.insetBy(dx: 0.09, dy: 0.09)), with: .color(Color(white: 0.65)), lineWidth: 0.18)
                case .planter:
                    ctx.fill(Path(r.offsetBy(dx: 0.2, dy: 0.25)), with: .color(.black.opacity(0.35)))
                    ctx.fill(Path(r), with: .color(Color(red: 0.48, green: 0.32, blue: 0.19)))
                    ctx.fill(Path(r.insetBy(dx: 0.15, dy: 0.15)), with: .color(Color(red: 0.29, green: 0.2, blue: 0.13)))
                case .pillar:
                    ctx.fill(Path(r.offsetBy(dx: 0.18, dy: 0.22)), with: .color(.black.opacity(0.45)))
                case .building, .roof:
                    ctx.fill(Path(r.offsetBy(dx: 0.5, dy: 0.7)), with: .color(.black.opacity(0.5)))
                case .wall:
                    break
                }
            }
            ctx.fill(sc.grassLight, with: .color(Color(red: 0.47, green: 0.7, blue: 0.31).opacity(0.35)))
            ctx.fill(sc.grassDark, with: .color(Color(red: 0.08, green: 0.24, blue: 0.08).opacity(0.35)))

            for c in lv.cars { car(ctx, x: c.x, y: c.y, a: c.deg * .pi / 180, color: c.color) }
            for t in lv.trees {
                ctx.fill(Path(ellipseIn: CGRect(x: t.x - 0.5, y: t.y - 0.5, width: 1, height: 1)), with: .color(.black.opacity(0.3)))
            }
        }

        private static func stains(_ ctx: GraphicsContext, _ list: [Disc], opacity: Double) {
            for s in list {
                ctx.fill(Path(ellipseIn: CGRect(x: s.x - s.r, y: s.y - s.r, width: s.r * 2, height: s.r * 2)),
                         with: .radialGradient(Gradient(colors: [.black.opacity(opacity), .black.opacity(0)]),
                                               center: CGPoint(x: s.x, y: s.y), startRadius: 0, endRadius: s.r))
            }
        }

        static func skids(_ ctx: GraphicsContext, _ list: [Skid]) {
            guard !list.isEmpty else { return }
            var p = Path()
            for s in list {
                p.move(to: CGPoint(x: s.x1, y: s.y1))
                p.addLine(to: CGPoint(x: s.x2, y: s.y2))
            }
            ctx.stroke(p, with: .color(Color(white: 0.05).opacity(0.28)), style: StrokeStyle(lineWidth: 0.22, lineCap: .round))
        }

        // MARK: - Viršutinis sluoksnis (stogai, kolonos, medžiai)

        static func roofs(_ ctx: GraphicsContext, _ lv: Level, _ sc: Scenery) {
            for w in lv.walls {
                let r = CGRect(x: w.x, y: w.y, width: w.w, height: w.h)
                switch w.kind {
                case .pillar:
                    ctx.fill(Path(r), with: .color(Color(red: 0.66, green: 0.68, blue: 0.7)))
                    ctx.fill(Path(CGRect(x: w.x, y: w.y, width: w.w, height: 0.12)), with: .color(Color(red: 0.91, green: 0.73, blue: 0.14)))
                    ctx.fill(Path(CGRect(x: w.x, y: w.y + w.h - 0.12, width: w.w, height: 0.12)), with: .color(Color(red: 0.91, green: 0.73, blue: 0.14)))
                case .wall:
                    ctx.fill(Path(r), with: .color(Color(red: 0.235, green: 0.25, blue: 0.275)))
                case .building:
                    ctx.fill(Path(r), with: .color(Color(red: 0.3, green: 0.325, blue: 0.36)))
                    var gx = w.x + 0.6
                    while gx < w.x + w.w - 1 {
                        ctx.fill(Path(CGRect(x: gx, y: w.y + 0.5, width: 1.6, height: max(0.2, w.h - 1))), with: .color(.white.opacity(0.06)))
                        gx += 3
                    }
                    ctx.fill(Path(CGRect(x: w.x, y: w.y + w.h - 0.18, width: w.w, height: 0.18)), with: .color(Color(red: 0.42, green: 0.45, blue: 0.49)))
                case .roof:
                    ctx.fill(Path(r), with: .color(Color(red: 0.6, green: 0.29, blue: 0.2)))
                    var tiles = Path()
                    let vertical = w.h > w.w
                    var k = 0.0
                    while k < (vertical ? w.h : w.w) {
                        if vertical {
                            tiles.move(to: CGPoint(x: w.x, y: w.y + k)); tiles.addLine(to: CGPoint(x: w.x + w.w, y: w.y + k))
                        } else {
                            tiles.move(to: CGPoint(x: w.x + k, y: w.y)); tiles.addLine(to: CGPoint(x: w.x + k, y: w.y + w.h))
                        }
                        k += 0.35
                    }
                    ctx.stroke(tiles, with: .color(.black.opacity(0.2)), lineWidth: 0.04)
                    var ridge = Path()
                    if vertical {
                        ridge.move(to: CGPoint(x: w.x + w.w / 2, y: w.y)); ridge.addLine(to: CGPoint(x: w.x + w.w / 2, y: w.y + w.h))
                    } else {
                        ridge.move(to: CGPoint(x: w.x, y: w.y + w.h / 2)); ridge.addLine(to: CGPoint(x: w.x + w.w, y: w.y + w.h / 2))
                    }
                    ctx.stroke(ridge, with: .color(Color(red: 0.43, green: 0.19, blue: 0.13)), lineWidth: 0.14)
                default:
                    break
                }
            }
            let flowerColors: [Color] = [Color(red: 0.37, green: 0.62, blue: 0.27), Color(red: 0.47, green: 0.7, blue: 0.34),
                                         Color(red: 0.88, green: 0.35, blue: 0.48), Color(red: 0.94, green: 0.76, blue: 0.29)]
            for (d, ci) in sc.flowers {
                ctx.fill(Path(ellipseIn: CGRect(x: d.x - d.r, y: d.y - d.r, width: d.r * 2, height: d.r * 2)), with: .color(flowerColors[ci % 4]))
            }
            for (i, t) in lv.trees.enumerated() where i < sc.canopies.count {
                tree(ctx, t, blobs: sc.canopies[i])
            }
        }

        static func tree(_ ctx: GraphicsContext, _ t: Tree, blobs: [Disc]) {
            let r = t.r
            ctx.fill(Path(ellipseIn: CGRect(x: t.x + r * 0.35 - r, y: t.y + r * 0.45 - r, width: r * 2, height: r * 2)),
                     with: .color(.black.opacity(0.35)))
            let leaf = Gradient(colors: [Color(red: 0.44, green: 0.68, blue: 0.3), Color(red: 0.18, green: 0.37, blue: 0.16)])
            for b in blobs {
                ctx.fill(Path(ellipseIn: CGRect(x: b.x - b.r, y: b.y - b.r, width: b.r * 2, height: b.r * 2)),
                         with: .radialGradient(leaf, center: CGPoint(x: b.x - b.r * 0.3, y: b.y - b.r * 0.3),
                                               startRadius: b.r * 0.1, endRadius: b.r))
            }
            let top = Gradient(colors: [Color(red: 0.55, green: 0.78, blue: 0.39), Color(red: 0.24, green: 0.48, blue: 0.2)])
            ctx.fill(Path(ellipseIn: CGRect(x: t.x - r * 0.62, y: t.y - r * 0.62, width: r * 1.24, height: r * 1.24)),
                     with: .radialGradient(top, center: CGPoint(x: t.x - r * 0.3, y: t.y - r * 0.35),
                                           startRadius: r * 0.1, endRadius: r * 0.7))
        }

        // MARK: - Tikslas

        static func spot(_ base: GraphicsContext, sim: Simulation, time: Double) {
            let s = sim.level.spot
            let state = sim.spotState
            let good = state.inside && state.aligned
            var ctx = base
            ctx.translateBy(x: s.x, y: s.y)
            ctx.rotate(by: .radians(s.deg * .pi / 180))
            let pulse = 0.5 + 0.5 * sin(time * 4)
            let tint = good ? Color(red: 0.24, green: 0.86, blue: 0.52) : Color(red: 0.3, green: 0.76, blue: 1)
            let rect = CGRect(x: -s.l / 2, y: -s.w / 2, width: s.l, height: s.w)
            ctx.fill(Path(rect), with: .color(tint.opacity(0.1 + 0.12 * pulse)))
            ctx.stroke(Path(rect), with: .color(tint.opacity(0.25)), lineWidth: 0.45)   // švytėjimas
            ctx.stroke(Path(rect), with: .color(tint),
                       style: StrokeStyle(lineWidth: 0.14, dash: [0.6, 0.35], dashPhase: -time * 1.2))
            if s.anyDirection {
                var t = ctx
                t.rotate(by: .radians(-s.deg * .pi / 180))
                t.draw(Text("P").font(.system(size: 1.4, weight: .bold, design: .rounded)).foregroundColor(tint),
                       at: .zero, anchor: .center)
            } else {
                var arrow = Path()
                arrow.move(to: CGPoint(x: -0.3, y: -0.6)); arrow.addLine(to: CGPoint(x: 0.5, y: 0)); arrow.addLine(to: CGPoint(x: -0.3, y: 0.6))
                arrow.move(to: CGPoint(x: -1.1, y: -0.6)); arrow.addLine(to: CGPoint(x: -0.3, y: 0)); arrow.addLine(to: CGPoint(x: -1.1, y: 0.6))
                ctx.stroke(arrow, with: .color(tint.opacity(0.9)), style: StrokeStyle(lineWidth: 0.18, lineCap: .round, lineJoin: .round))
            }
            if sim.hold > 0 && !sim.won {
                let f = min(1, sim.hold / 0.7)
                var ring = Path()
                ring.addArc(center: .zero, radius: 0.9, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * f), clockwise: false)
                ctx.stroke(ring, with: .color(Color(red: 0.24, green: 0.86, blue: 0.52)), lineWidth: 0.16)
            }
        }

        // MARK: - Mašina (vietinės koordinatės: +x – priekis, metrai)

        static func car(_ base: GraphicsContext, x: Double, y: Double, a: Double, color: UInt32,
                        steer: Double = 0, brake: Bool = false, reverse: Bool = false, player: Bool = false) {
            let L = CarSpec.length, W = CarSpec.width
            var ctx = base
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: .radians(a))
            let bodyRect = CGRect(x: -L / 2, y: -W / 2, width: L, height: W)
            // šešėlis
            ctx.fill(Path(roundedRect: bodyRect.offsetBy(dx: 0.14, dy: 0.2), cornerRadius: 0.55), with: .color(.black.opacity(0.42)))
            ctx.fill(Path(roundedRect: bodyRect.insetBy(dx: -0.08, dy: -0.08).offsetBy(dx: 0.14, dy: 0.24), cornerRadius: 0.6),
                     with: .color(.black.opacity(0.15)))
            // ratai
            for sx in [-CarSpec.wheelbase / 2, CarSpec.wheelbase / 2] {
                for sy in [-1.0, 1.0] {
                    var wctx = ctx
                    wctx.translateBy(x: sx, y: sy * (W / 2 - 0.08))
                    if sx > 0 { wctx.rotate(by: .radians(steer)) }
                    wctx.fill(Path(roundedRect: CGRect(x: -0.36, y: -0.13, width: 0.72, height: 0.26), cornerRadius: 0.08),
                              with: .color(Color(white: 0.05)))
                }
            }
            // kėbulas
            let body = Gradient(stops: [
                .init(color: ParkavimoMeistras.rgb(color, shade: -0.35), location: 0),
                .init(color: ParkavimoMeistras.rgb(color), location: 0.22),
                .init(color: ParkavimoMeistras.rgb(color, shade: 0.12), location: 0.5),
                .init(color: ParkavimoMeistras.rgb(color), location: 0.78),
                .init(color: ParkavimoMeistras.rgb(color, shade: -0.35), location: 1)
            ])
            let bodyPath = Path(roundedRect: bodyRect, cornerRadius: 0.55)
            ctx.fill(bodyPath, with: .linearGradient(body, startPoint: CGPoint(x: 0, y: -W / 2), endPoint: CGPoint(x: 0, y: W / 2)))
            ctx.stroke(bodyPath, with: .color(.black.opacity(0.35)), lineWidth: 0.04)
            // variklio dangtis
            var hood = Path()
            hood.move(to: CGPoint(x: 1.3, y: -W / 2 + 0.25))
            hood.addQuadCurve(to: CGPoint(x: 1.3, y: W / 2 - 0.25), control: CGPoint(x: 2.05, y: 0))
            ctx.stroke(hood, with: .color(.black.opacity(0.18)), lineWidth: 0.03)
            // priekinis stiklas
            var shield = Path()
            shield.move(to: CGPoint(x: 0.45, y: -W / 2 + 0.16))
            shield.addLine(to: CGPoint(x: 1.25, y: -W / 2 + 0.3))
            shield.addQuadCurve(to: CGPoint(x: 1.25, y: W / 2 - 0.3), control: CGPoint(x: 1.38, y: 0))
            shield.addLine(to: CGPoint(x: 0.45, y: W / 2 - 0.16))
            shield.closeSubpath()
            ctx.fill(shield, with: .linearGradient(Gradient(colors: [Color(red: 0.1, green: 0.13, blue: 0.19), Color(red: 0.29, green: 0.38, blue: 0.5)]),
                                                   startPoint: CGPoint(x: 0.5, y: 0), endPoint: CGPoint(x: 1.3, y: 0)))
            // galinis stiklas
            var rear = Path()
            rear.move(to: CGPoint(x: -1.15, y: -W / 2 + 0.18))
            rear.addLine(to: CGPoint(x: -1.6, y: -W / 2 + 0.3))
            rear.addQuadCurve(to: CGPoint(x: -1.6, y: W / 2 - 0.3), control: CGPoint(x: -1.7, y: 0))
            rear.addLine(to: CGPoint(x: -1.15, y: W / 2 - 0.18))
            rear.closeSubpath()
            ctx.fill(rear, with: .color(Color(red: 0.12, green: 0.15, blue: 0.2)))
            // stogas
            let roof = Gradient(stops: [
                .init(color: ParkavimoMeistras.rgb(color, shade: -0.15), location: 0),
                .init(color: ParkavimoMeistras.rgb(color, shade: 0.28), location: 0.45),
                .init(color: ParkavimoMeistras.rgb(color, shade: -0.2), location: 1)
            ])
            ctx.fill(Path(roundedRect: CGRect(x: -1.15, y: -W / 2 + 0.2, width: 1.6, height: W - 0.4), cornerRadius: 0.25),
                     with: .linearGradient(roof, startPoint: CGPoint(x: 0, y: -W / 2), endPoint: CGPoint(x: 0, y: W / 2)))
            let glass = Color(red: 0.08, green: 0.11, blue: 0.16).opacity(0.85)
            ctx.fill(Path(roundedRect: CGRect(x: -1.1, y: -W / 2 + 0.08, width: 1.5, height: 0.13), cornerRadius: 0.05), with: .color(glass))
            ctx.fill(Path(roundedRect: CGRect(x: -1.1, y: W / 2 - 0.21, width: 1.5, height: 0.13), cornerRadius: 0.05), with: .color(glass))
            ctx.fill(Path(roundedRect: CGRect(x: -0.9, y: -W / 2 + 0.32, width: 1.1, height: 0.2), cornerRadius: 0.1), with: .color(.white.opacity(0.18)))
            // veidrodėliai
            let mirror = ParkavimoMeistras.rgb(color, shade: -0.25)
            ctx.fill(Path(roundedRect: CGRect(x: 0.55, y: -W / 2 - 0.14, width: 0.22, height: 0.16), cornerRadius: 0.05), with: .color(mirror))
            ctx.fill(Path(roundedRect: CGRect(x: 0.55, y: W / 2 - 0.02, width: 0.22, height: 0.16), cornerRadius: 0.05), with: .color(mirror))
            // žibintai
            let head = Color(red: 1, green: 0.97, blue: 0.84)
            ctx.fill(Path(roundedRect: CGRect(x: L / 2 - 0.16, y: -W / 2 + 0.15, width: 0.12, height: 0.38), cornerRadius: 0.05), with: .color(head))
            ctx.fill(Path(roundedRect: CGRect(x: L / 2 - 0.16, y: W / 2 - 0.53, width: 0.12, height: 0.38), cornerRadius: 0.05), with: .color(head))
            let tail: Color = brake ? Color(red: 1, green: 0.16, blue: 0.16) : Color(red: 0.56, green: 0.07, blue: 0.07)
            ctx.fill(Path(roundedRect: CGRect(x: -L / 2 + 0.04, y: -W / 2 + 0.14, width: 0.12, height: 0.4), cornerRadius: 0.05), with: .color(tail))
            ctx.fill(Path(roundedRect: CGRect(x: -L / 2 + 0.04, y: W / 2 - 0.54, width: 0.12, height: 0.4), cornerRadius: 0.05), with: .color(tail))
            if reverse {
                ctx.fill(Path(roundedRect: CGRect(x: -L / 2 + 0.04, y: -0.15, width: 0.1, height: 0.3), cornerRadius: 0.04), with: .color(.white))
            }
            if brake || reverse {
                var glow = ctx
                glow.blendMode = .plusLighter
                let col: Color = brake ? Color(red: 1, green: 0.16, blue: 0.16).opacity(0.55) : Color.white.opacity(0.35)
                for sy in [-W / 2 + 0.34, W / 2 - 0.34] {
                    glow.fill(Path(ellipseIn: CGRect(x: -L / 2 - 1.1, y: sy - 1.1, width: 2.2, height: 2.2)),
                              with: .radialGradient(Gradient(colors: [col, col.opacity(0)]), center: CGPoint(x: -L / 2, y: sy),
                                                    startRadius: 0, endRadius: 1.1))
                }
            }
            if player {
                var checks = Path()
                for i in 0..<6 { checks.addRect(CGRect(x: -1.0 + Double(i) * 0.26, y: -0.06, width: 0.13, height: 0.12)) }
                ctx.fill(checks, with: .color(Color(red: 0.1, green: 0.08, blue: 0.02)))
            }
        }

        // MARK: - Pėsčiasis

        static func pedestrian(_ base: GraphicsContext, _ p: Pedestrian, time: Double) {
            var ctx = base
            ctx.translateBy(x: p.x, y: p.y)
            ctx.rotate(by: .radians(p.heading))
            ctx.scaleBy(x: 1.45, y: 1.45)
            let swing = p.walking ? sin(time * 9 + Double(p.colorIndex)) * 0.22 : 0
            let jackets: [Color] = [Color(red: 0.18, green: 0.44, blue: 0.86), Color(red: 0.76, green: 0.23, blue: 0.42), Color(red: 0.18, green: 0.61, blue: 0.42)]
            ctx.fill(Path(ellipseIn: CGRect(x: 0.08 - 0.32, y: 0.1 - 0.4, width: 0.64, height: 0.8)), with: .color(.black.opacity(0.35)))
            ctx.fill(Path(ellipseIn: CGRect(x: swing - 0.14, y: -0.13 - 0.08, width: 0.28, height: 0.16)), with: .color(Color(white: 0.13)))
            ctx.fill(Path(ellipseIn: CGRect(x: -swing - 0.14, y: 0.13 - 0.08, width: 0.28, height: 0.16)), with: .color(Color(white: 0.13)))
            ctx.fill(Path(ellipseIn: CGRect(x: -0.17, y: -0.3, width: 0.34, height: 0.6)), with: .color(jackets[p.colorIndex % 3]))
            ctx.fill(Path(ellipseIn: CGRect(x: 0.02 - 0.13, y: -0.13, width: 0.26, height: 0.26)), with: .color(Color(red: 0.91, green: 0.76, blue: 0.62)))
            var hair = Path()
            hair.addArc(center: CGPoint(x: -0.02, y: 0), radius: 0.12, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
            ctx.fill(hair, with: .color(Color(red: 0.29, green: 0.18, blue: 0.11)))
        }
    }
}
