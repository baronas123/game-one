import SwiftUI

extension Sankryza {

    /// Spalva be SwiftUI priklausomybių skaičiavimams (maišymas, šešėliai).
    struct RGB {
        let r: Double, g: Double, b: Double

        init(_ hex: UInt32) {
            r = Double((hex >> 16) & 0xff) / 255
            g = Double((hex >> 8) & 0xff) / 255
            b = Double(hex & 0xff) / 255
        }

        init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

        func mix(_ o: RGB, _ t: Double) -> RGB {
            RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
        }

        func shade(_ amt: Double) -> RGB { amt < 0 ? mix(RGB(0x000000), -amt) : mix(RGB(0xffffff), amt) }

        var color: Color { Color(red: r, green: g, blue: b) }
        func color(_ opacity: Double) -> Color { Color(red: r, green: g, blue: b).opacity(opacity) }
    }

    enum Palette {
        static let roofs: [UInt32] = [0xe07a5f, 0x3d405b, 0x81b29a, 0xf2cc8f, 0x9a8c98, 0x6d8ea0, 0xc8553d, 0x5b7f6e]
        static let paints: [UInt32] = [0xd64545, 0x2f6fd6, 0xeef0f2, 0x2a2d33, 0x3aa66a, 0xe58e26, 0x8e5bd6, 0x9aa4b1, 0x1f9bb0, 0xb8323f]
        static let trees: [UInt32] = [0x3f7d3a, 0x4b8f3f, 0x356e3a, 0x5a9a46]
        static let red = RGB(0xff4b3e), amber = RGB(0xffb21f), green = RGB(0x2fd27a)

        static func carColor(_ c: Car) -> RGB {
            switch c.kind {
            case .taxi: return RGB(0xf4c430)
            case .police: return RGB(0xf4f6f8)
            case .bus: return RGB(0xe9eef5)
            default: return RGB(paints[c.paint % paints.count])
            }
        }
    }

    /// Visas sankryžos piešimas viename `Canvas`. Koordinatės – vienetais (1 = juostos plotis).
    enum Renderer {

        static func draw(_ ctx: GraphicsContext, sim: Simulation, time: Double, parallax: CGSize, reducedMotion: Bool) {
            let city = sim.city
            let u = city.unit
            guard u > 0 else { return }
            var shake = CGSize.zero
            if sim.shake > 0 && !reducedMotion {
                shake = CGSize(width: Double.random(in: -7...7) * sim.shake, height: Double.random(in: -7...7) * sim.shake)
            }
            let sky = sim.sky()
            let dk = sky.dark

            var world = ctx
            world.translateBy(x: shake.width, y: shake.height)
            world.scaleBy(x: u, y: u)

            drawGround(world, city)
            for lane in sim.lanes { for c in lane { drawCar(world, c, sim: sim, time: time, reducedMotion: reducedMotion) } }

            var cityCtx = ctx
            cityCtx.translateBy(x: shake.width + parallax.width, y: shake.height + parallax.height)
            cityCtx.scaleBy(x: u, y: u)
            drawCity(cityCtx, city)
            drawBoard(cityCtx, city, time: time, dark: dk)

            // Paros laikas: dauginamas atspalvis (diena → saulėlydis → naktis).
            let tint = RGB(0xffffff).mix(RGB(0xffb27d), sky.dusk * 0.8).mix(RGB(0x26336e), dk)
            if tint.r < 0.995 || tint.g < 0.995 || tint.b < 0.995 {
                var m = ctx
                m.blendMode = .multiply
                m.fill(Path(CGRect(origin: .zero, size: CGSize(width: city.wu * u + 40, height: city.hu * u + 40)).offsetBy(dx: -20, dy: -20)),
                       with: .color(tint.color))
            }

            var glow = world
            glow.blendMode = .plusLighter
            drawLights(glow, cityCtx: cityCtx, sim: sim, time: time, dark: dk, reducedMotion: reducedMotion)
            drawParticles(world, sim)

            var px = ctx
            px.translateBy(x: shake.width, y: shake.height)
            drawSignals(px, sim: sim, time: time, dark: dk)
            drawBubbles(px, sim: sim, time: time)
            drawPending(px, sim: sim)
            drawPopups(px, sim: sim)
        }

        // MARK: Žemė ir keliai

        private static func drawGround(_ g: GraphicsContext, _ c: CityLayout) {
            let r = c.r, sw = c.sidewalk, cx = c.cx, cy = c.cy, wu = c.wu, hu = c.hu
            g.fill(Path(CGRect(x: -1, y: -1, width: wu + 2, height: hu + 2)), with: .color(RGB(0xc9c1ae).color))
            let walk = RGB(0xe2dccd).color
            g.fill(Path(CGRect(x: cx - r - sw, y: -1, width: 2 * (r + sw), height: hu + 2)), with: .color(walk))
            g.fill(Path(CGRect(x: -1, y: cy - r - sw, width: wu + 2, height: 2 * (r + sw))), with: .color(walk))
            let asphalt = RGB(0x353943).color
            g.fill(Path(CGRect(x: cx - r, y: -1, width: 2 * r, height: hu + 2)), with: .color(asphalt))
            g.fill(Path(CGRect(x: -1, y: cy - r, width: wu + 2, height: 2 * r)), with: .color(asphalt))

            var curb = Path()
            curb.move(to: CGPoint(x: cx - r, y: 0)); curb.addLine(to: CGPoint(x: cx - r, y: cy - r)); curb.addLine(to: CGPoint(x: 0, y: cy - r))
            curb.move(to: CGPoint(x: cx + r, y: 0)); curb.addLine(to: CGPoint(x: cx + r, y: cy - r)); curb.addLine(to: CGPoint(x: wu, y: cy - r))
            curb.move(to: CGPoint(x: cx - r, y: hu)); curb.addLine(to: CGPoint(x: cx - r, y: cy + r)); curb.addLine(to: CGPoint(x: 0, y: cy + r))
            curb.move(to: CGPoint(x: cx + r, y: hu)); curb.addLine(to: CGPoint(x: cx + r, y: cy + r)); curb.addLine(to: CGPoint(x: wu, y: cy + r))
            g.stroke(curb, with: .color(RGB(0x8f897b).color), lineWidth: 0.07)

            let paint = Color(red: 0.965, green: 0.95, blue: 0.906)
            let sd = c.stopD
            func line(_ a: CGPoint, _ b: CGPoint, dashed: Bool) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                g.stroke(p, with: .color(paint.opacity(0.85)),
                         style: StrokeStyle(lineWidth: 0.07, dash: dashed ? [0.6, 0.5] : []))
            }
            line(CGPoint(x: cx, y: 0), CGPoint(x: cx, y: cy - sd - 2.2), dashed: true)
            line(CGPoint(x: cx, y: cy - sd - 2.2), CGPoint(x: cx, y: cy - sd), dashed: false)
            line(CGPoint(x: cx, y: hu), CGPoint(x: cx, y: cy + sd + 2.2), dashed: true)
            line(CGPoint(x: cx, y: cy + sd + 2.2), CGPoint(x: cx, y: cy + sd), dashed: false)
            line(CGPoint(x: 0, y: cy), CGPoint(x: cx - sd - 2.2, y: cy), dashed: true)
            line(CGPoint(x: cx - sd - 2.2, y: cy), CGPoint(x: cx - sd, y: cy), dashed: false)
            line(CGPoint(x: wu, y: cy), CGPoint(x: cx + sd + 2.2, y: cy), dashed: true)
            line(CGPoint(x: cx + sd + 2.2, y: cy), CGPoint(x: cx + sd, y: cy), dashed: false)

            var marks = Path()
            marks.addRect(CGRect(x: cx, y: cy + sd - 0.14, width: r, height: 0.14))
            marks.addRect(CGRect(x: cx - r, y: cy - sd, width: r, height: 0.14))
            marks.addRect(CGRect(x: cx - sd, y: cy, width: 0.14, height: r))
            marks.addRect(CGRect(x: cx + sd - 0.14, y: cy - r, width: 0.14, height: r))
            let z0 = r + 0.12
            var x = cx - r + 0.1
            while x < cx + r - 0.05 {
                marks.addRect(CGRect(x: x, y: cy + z0, width: 0.17, height: c.cw))
                marks.addRect(CGRect(x: x, y: cy - z0 - c.cw, width: 0.17, height: c.cw))
                x += 0.34
            }
            var y = cy - r + 0.1
            while y < cy + r - 0.05 {
                marks.addRect(CGRect(x: cx + z0, y: y, width: c.cw, height: 0.17))
                marks.addRect(CGRect(x: cx - z0 - c.cw, y: y, width: c.cw, height: 0.17))
                y += 0.34
            }
            g.fill(marks, with: .color(paint.opacity(0.92)))

            for (pt, ang) in [(CGPoint(x: cx + 0.5, y: cy + sd + 1.3), 0.0), (CGPoint(x: cx - 0.5, y: cy - sd - 1.3), Double.pi),
                              (CGPoint(x: cx - sd - 1.3, y: cy + 0.5), Double.pi / 2), (CGPoint(x: cx + sd + 1.3, y: cy - 0.5), -Double.pi / 2)] {
                var a = g
                a.translateBy(x: pt.x, y: pt.y)
                a.rotate(by: .radians(ang))
                var p = Path()
                p.move(to: CGPoint(x: 0, y: -0.45)); p.addLine(to: CGPoint(x: 0.2, y: -0.15)); p.addLine(to: CGPoint(x: 0.07, y: -0.15))
                p.addLine(to: CGPoint(x: 0.07, y: 0.4)); p.addLine(to: CGPoint(x: -0.07, y: 0.4)); p.addLine(to: CGPoint(x: -0.07, y: -0.15))
                p.addLine(to: CGPoint(x: -0.2, y: -0.15)); p.closeSubpath()
                a.fill(p, with: .color(paint.opacity(0.92)))
            }
        }

        // MARK: Miestas

        private static func circle(_ x: Double, _ y: Double, _ r: Double) -> Path {
            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }

        private static func drawTree(_ g: GraphicsContext, _ t: Tree) {
            let base = RGB(Palette.trees[t.tone % Palette.trees.count])
            g.fill(circle(t.x + t.r * 0.35, t.y + t.r * 0.3, t.r), with: .color(Color(red: 0.08, green: 0.12, blue: 0.06).opacity(0.28)))
            g.fill(circle(t.x, t.y, t.r), with: .color(base.color))
            g.fill(circle(t.x - t.r * 0.28, t.y - t.r * 0.3, t.r * 0.55), with: .color(base.shade(0.18).color))
            g.fill(circle(t.x + t.r * 0.35, t.y + t.r * 0.35, t.r * 0.35), with: .color(base.shade(-0.25).color))
        }

        private static func drawCity(_ g: GraphicsContext, _ c: CityLayout) {
            for p in c.parks {
                g.fill(Path(roundedRect: p, cornerRadius: 0.2), with: .color(RGB(0x8dbd6b).color))
                var path = Path(); path.move(to: CGPoint(x: p.minX, y: p.minY)); path.addLine(to: CGPoint(x: p.maxX, y: p.maxY))
                g.stroke(path, with: .color(Color(red: 0.94, green: 0.9, blue: 0.78).opacity(0.7)), lineWidth: 0.12)
            }
            for b in c.buildings {
                let col = RGB(Palette.roofs[b.roof % Palette.roofs.count])
                let rr = b.roofRect
                g.fill(Path(b.rect.offsetBy(dx: b.lift / 0.55 * 0.35, dy: 0.05)), with: .color(Color(red: 0.1, green: 0.08, blue: 0.06).opacity(0.25)))
                g.fill(Path(CGRect(x: rr.minX, y: rr.maxY, width: rr.width, height: b.lift)), with: .color(col.shade(-0.38).color))
                for w in b.windows { g.fill(Path(w), with: .color(Color(red: 0.06, green: 0.09, blue: 0.14).opacity(0.65))) }
                g.fill(Path(rr), with: .color(col.color))
                g.stroke(Path(rr.insetBy(dx: 0.035, dy: 0.035)), with: .color(col.shade(-0.18).color), lineWidth: 0.07)
                if rr.width > 0.4 && rr.height > 0.4 {
                    g.stroke(Path(rr.insetBy(dx: 0.14, dy: 0.14)), with: .color(col.shade(0.18).color), lineWidth: 0.03)
                }
                for unit in b.units {
                    g.fill(Path(unit.offsetBy(dx: 0.05, dy: 0.05)), with: .color(.black.opacity(0.22)))
                    g.fill(Path(unit), with: .color(RGB(0xd9dde2).color))
                    let s = Double(unit.width)
                    g.stroke(circle(Double(unit.midX), Double(unit.midY), s * 0.3), with: .color(RGB(0x9aa1a9).color), lineWidth: 0.025)
                }
                if let sky = b.skylight { g.fill(Path(sky), with: .color(Color(red: 0.63, green: 0.82, blue: 1).opacity(0.55))) }
            }
            for t in c.trees { drawTree(g, t) }
            for l in c.lamps {
                g.fill(circle(Double(l.x), Double(l.y), 0.09), with: .color(RGB(0x2a2d33).color))
                g.fill(circle(Double(l.x), Double(l.y), 0.05), with: .color(RGB(0xfff2c4).color))
            }
            let b = c.board
            g.fill(Path(b.offsetBy(dx: 0.3, dy: 0.2)), with: .color(.black.opacity(0.3)))
            g.fill(Path(CGRect(x: b.midX - 0.08, y: b.maxY, width: 0.16, height: 0.45)), with: .color(RGB(0x4a4f58).color))
            g.fill(Path(roundedRect: b.insetBy(dx: -0.1, dy: -0.1), cornerRadius: 0.12), with: .color(RGB(0x16181d).color))
        }

        /// LED ekranas. Kai įjungta kamera, ant jo uždedamas gyvas vaizdas (atskiras vaizdas virš drobės).
        private static func drawBoard(_ g: GraphicsContext, _ c: CityLayout, time: Double, dark: Double) {
            let b = c.board
            let hue = (time * 25).truncatingRemainder(dividingBy: 360) / 360
            let grad = Gradient(colors: [Color(hue: hue, saturation: 0.7, brightness: 0.5),
                                         Color(hue: (hue + 1.0 / 6).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.38)])
            g.fill(Path(roundedRect: b, cornerRadius: 0.06),
                   with: .linearGradient(grad, startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)))
            let msgs = ["SAUGAUS EISMO!", "SEGĖKITĖS DIRŽUS", "PRALEISK PĖSČIĄJĮ", "SKUBĖK LĖTAI"]
            let msg = msgs[Int(time / 3) % msgs.count]
            var t = g
            t.translateBy(x: b.midX, y: b.midY)
            t.scaleBy(x: 1 / c.unit, y: 1 / c.unit)
            t.draw(Text(msg).font(.system(size: 0.24 * c.unit, weight: .black, design: .rounded)).foregroundColor(.white),
                   at: .zero)
            var lines = Path()
            var y = Double(b.minY)
            while y < Double(b.maxY) { lines.addRect(CGRect(x: b.minX, y: y, width: b.width, height: 0.025)); y += 0.09 }
            g.fill(lines, with: .color(.black.opacity(0.28)))
        }

        // MARK: Automobiliai

        private static func drawCar(_ g: GraphicsContext, _ c: Car, sim: Simulation, time: Double, reducedMotion: Bool) {
            let ap = sim.city.approaches[c.approach]
            let f = sim.front(c)
            let cx = Double(f.x) - ap.dx * c.len / 2, cy = Double(f.y) - ap.dy * c.len / 2
            let angles = [0.0, Double.pi / 2, Double.pi, -Double.pi / 2]
            let ang = angles[c.approach] + c.rot
            let len = c.len, wd = c.wid, y0 = -len / 2, x0 = -wd / 2
            let col = Palette.carColor(c)

            var sh = g
            sh.translateBy(x: cx + 0.08, y: cy + 0.12)
            sh.rotate(by: .radians(ang))
            sh.fill(Path(roundedRect: CGRect(x: x0, y: y0, width: wd, height: len), cornerRadius: 0.2), with: .color(.black.opacity(0.32)))

            var b = g
            b.translateBy(x: cx, y: cy)
            b.rotate(by: .radians(ang))
            let glass = Color(red: 0.08, green: 0.105, blue: 0.145)
            switch c.kind {
            case .truck:
                let cab = 0.85
                b.fill(Path(roundedRect: CGRect(x: x0, y: y0 + cab + 0.08, width: wd, height: len - cab - 0.08), cornerRadius: 0.08),
                       with: .color(RGB(0xd7d9dc).color))
                var ribs = Path()
                var y = y0 + cab + 0.3
                while y < len / 2 - 0.1 { ribs.move(to: CGPoint(x: x0 + 0.06, y: y)); ribs.addLine(to: CGPoint(x: -x0 - 0.06, y: y)); y += 0.26 }
                b.stroke(ribs, with: .color(.black.opacity(0.14)), lineWidth: 0.03)
                b.fill(Path(roundedRect: CGRect(x: x0 + 0.03, y: y0, width: wd - 0.06, height: cab), cornerRadius: 0.16), with: .color(col.color))
                b.fill(Path(roundedRect: CGRect(x: x0 + 0.1, y: y0 + 0.1, width: wd - 0.2, height: 0.22), cornerRadius: 0.06), with: .color(glass))
                b.fill(Path(roundedRect: CGRect(x: x0 + 0.1, y: y0 + 0.38, width: wd - 0.2, height: 0.38), cornerRadius: 0.06), with: .color(col.shade(0.15).color))
            case .bus:
                b.fill(Path(roundedRect: CGRect(x: x0, y: y0, width: wd, height: len), cornerRadius: 0.18), with: .color(col.color))
                let stripe = RGB(0x2a64c5).color
                b.fill(Path(CGRect(x: x0, y: y0 + 0.5, width: 0.1, height: len - 0.7)), with: .color(stripe))
                b.fill(Path(CGRect(x: -x0 - 0.1, y: y0 + 0.5, width: 0.1, height: len - 0.7)), with: .color(stripe))
                b.fill(Path(roundedRect: CGRect(x: x0 + 0.08, y: y0 + 0.06, width: wd - 0.16, height: 0.3), cornerRadius: 0.08), with: .color(glass))
                let ac = RGB(0xc3ccd6).color
                b.fill(Path(roundedRect: CGRect(x: x0 + 0.2, y: y0 + 0.7, width: wd - 0.4, height: 0.5), cornerRadius: 0.05), with: .color(ac))
                b.fill(Path(roundedRect: CGRect(x: x0 + 0.2, y: y0 + 1.5, width: wd - 0.4, height: 0.5), cornerRadius: 0.05), with: .color(ac))
                b.fill(Path(CGRect(x: x0 + 0.15, y: len / 2 - 0.35, width: wd - 0.3, height: 0.2)), with: .color(.black.opacity(0.15)))
            case .hatch, .taxi, .police:
                b.fill(Path(roundedRect: CGRect(x: x0, y: y0, width: wd, height: len), cornerRadius: 0.22), with: .color(col.color))
                b.fill(Path(roundedRect: CGRect(x: x0 + 0.06, y: y0 + 0.2, width: wd * 0.22, height: len - 0.4), cornerRadius: 0.08),
                       with: .color(.white.opacity(0.2)))
                var ws = Path()
                ws.move(to: CGPoint(x: x0 + 0.1, y: y0 + 0.58)); ws.addLine(to: CGPoint(x: x0 + 0.16, y: y0 + 0.3))
                ws.addLine(to: CGPoint(x: -x0 - 0.16, y: y0 + 0.3)); ws.addLine(to: CGPoint(x: -x0 - 0.1, y: y0 + 0.58)); ws.closeSubpath()
                b.fill(ws, with: .linearGradient(Gradient(colors: [Color(red: 0.17, green: 0.23, blue: 0.3), glass]),
                                                 startPoint: CGPoint(x: 0, y: y0 + 0.28), endPoint: CGPoint(x: 0, y: y0 + 0.58)))
                let roof: Color = c.kind == .police ? RGB(0xf4f6f8).color : col.shade(0.1).color
                b.fill(Path(roundedRect: CGRect(x: x0 + 0.1, y: y0 + 0.6, width: wd - 0.2, height: len * 0.36), cornerRadius: 0.1), with: .color(roof))
                b.fill(Path(roundedRect: CGRect(x: x0 + 0.13, y: len / 2 - 0.42, width: wd - 0.26, height: 0.2), cornerRadius: 0.06), with: .color(glass))
                let mirror = col.shade(-0.3).color
                b.fill(Path(CGRect(x: x0 - 0.05, y: y0 + 0.5, width: 0.07, height: 0.1)), with: .color(mirror))
                b.fill(Path(CGRect(x: -x0 - 0.02, y: y0 + 0.5, width: 0.07, height: 0.1)), with: .color(mirror))
                if c.kind == .police {
                    b.fill(Path(CGRect(x: x0, y: y0 + 0.7, width: wd, height: 0.18)), with: .color(RGB(0x1f4fbf).color))
                    let on = Int(time * (reducedMotion ? 2 : 8)) % 2 == 0
                    b.fill(Path(CGRect(x: x0 + 0.12, y: y0 + 0.78, width: wd / 2 - 0.12, height: 0.14)),
                           with: .color(on ? RGB(0xff2a2a).color : RGB(0x5a1010).color))
                    b.fill(Path(CGRect(x: 0, y: y0 + 0.78, width: wd / 2 - 0.12, height: 0.14)),
                           with: .color(on ? RGB(0x123070).color : RGB(0x2f7bff).color))
                }
                if c.kind == .taxi {
                    b.fill(Path(CGRect(x: -0.2, y: y0 + 0.78, width: 0.4, height: 0.16)), with: .color(RGB(0x111111).color))
                    var checks = Path()
                    for i in 0..<4 { checks.addRect(CGRect(x: -0.2 + Double(i) * 0.1, y: y0 + 0.78 + Double(i % 2) * 0.08, width: 0.05, height: 0.08)) }
                    b.fill(checks, with: .color(.white))
                }
            }
            var heads = Path()
            heads.addRect(CGRect(x: x0 + 0.08, y: y0 + 0.02, width: 0.16, height: 0.07))
            heads.addRect(CGRect(x: -x0 - 0.24, y: y0 + 0.02, width: 0.16, height: 0.07))
            b.fill(heads, with: .color(RGB(0xfff6d0).color))
            var tails = Path()
            tails.addRect(CGRect(x: x0 + 0.08, y: len / 2 - 0.08, width: 0.16, height: 0.06))
            tails.addRect(CGRect(x: -x0 - 0.24, y: len / 2 - 0.08, width: 0.16, height: 0.06))
            b.fill(tails, with: .color(c.braking ? RGB(0xff3040).color : RGB(0x9c1424).color))
        }

        // MARK: Šviesos (naktis)

        private static func glowCircle(_ g: GraphicsContext, _ x: Double, _ y: Double, _ r: Double, _ col: RGB, _ a: Double) {
            let grad = Gradient(colors: [col.color(a), col.color(0)])
            g.fill(circle(x, y, r), with: .radialGradient(grad, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
        }

        private static func drawLights(_ g: GraphicsContext, cityCtx: GraphicsContext, sim: Simulation, time: Double, dark dk: Double, reducedMotion: Bool) {
            let city = sim.city
            if dk > 0.02 {
                var w = cityCtx
                w.blendMode = .plusLighter
                for b in city.buildings {
                    for (i, rect) in b.windows.enumerated() where b.lit[i] > 0 {
                        let col: Color = b.lit[i] == 1 ? RGB(0xffcf73).color(dk * 0.95) : RGB(0xbfe3ff).color(dk * 0.95)
                        w.fill(Path(rect), with: .color(col))
                    }
                }
                for l in city.lamps { glowCircle(g, Double(l.x), Double(l.y), 1.7, RGB(0xffcd78), 0.42 * dk) }
            }
            for lane in sim.lanes {
                for c in lane {
                    let ap = city.approaches[c.approach]
                    let f = sim.front(c)
                    let fx = Double(f.x), fy = Double(f.y)
                    let rx = fx - ap.dx * c.len, ry = fy - ap.dy * c.len
                    let sx = ap.lx * 0.6, sy = ap.ly * 0.6
                    if dk > 0.05 && !c.crashed {
                        let ex = fx + ap.dx * 2.8, ey = fy + ap.dy * 2.8
                        var cone = Path()
                        cone.move(to: CGPoint(x: fx + sx, y: fy + sy)); cone.addLine(to: CGPoint(x: fx - sx, y: fy - sy))
                        cone.addLine(to: CGPoint(x: ex - sx * 2.6, y: ey - sy * 2.6)); cone.addLine(to: CGPoint(x: ex + sx * 2.6, y: ey + sy * 2.6))
                        cone.closeSubpath()
                        let beam = RGB(0xfff0c8)
                        g.fill(cone, with: .linearGradient(Gradient(colors: [beam.color(0.38 * dk), beam.color(0)]),
                                                           startPoint: CGPoint(x: fx, y: fy), endPoint: CGPoint(x: ex, y: ey)))
                    }
                    let ta = (c.braking ? 0.55 : 0.18) * (0.35 + 0.65 * dk)
                    for k in [-1.0, 1.0] { glowCircle(g, rx + sx * k, ry + sy * k, 0.45, RGB(0xff2832), ta) }
                    if c.kind == .police {
                        let on = Int(time * (reducedMotion ? 2 : 8)) % 2 == 0
                        glowCircle(g, (fx + rx) / 2, (fy + ry) / 2, 1.6, on ? RGB(0xff2828) : RGB(0x326eff), 0.35 + 0.35 * dk)
                    }
                }
            }
        }

        private static func drawParticles(_ g: GraphicsContext, _ sim: Simulation) {
            for p in sim.particles {
                let a = max(0, min(1, p.life / p.maxLife))
                if p.spark {
                    var path = Path()
                    path.move(to: CGPoint(x: p.x, y: p.y)); path.addLine(to: CGPoint(x: p.x - p.vx * 0.04, y: p.y - p.vy * 0.04))
                    g.stroke(path, with: .color(Color(red: 1, green: (180 + 60 * a) / 255, blue: 0.31).opacity(a)), lineWidth: 0.06)
                } else {
                    g.fill(circle(p.x, p.y, 0.3 + (1 - a) * 0.9), with: .color(Color(red: 0.24, green: 0.24, blue: 0.25).opacity(a * 0.45)))
                }
            }
        }

        // MARK: Šviesoforai ir užrašai (taškais)

        private static func signalColor(_ s: Signal) -> RGB {
            switch s {
            case .red: return Palette.red
            case .yellow: return Palette.amber
            case .green: return Palette.green
            }
        }

        private static func drawSignals(_ g: GraphicsContext, sim: Simulation, time: Double, dark dk: Double) {
            let u = sim.city.unit
            for a in 0..<4 {
                let p = sim.city.lights[a]
                let light = sim.lights[a]
                let x = Double(p.x) * u, y = Double(p.y) * u
                let col = signalColor(light.state)
                glowCircle(g, x, y, 30, col, dk > 0.3 ? 0.53 : 0.33)
                let housing = CGRect(x: x - 8, y: y - 20, width: 16, height: 40)
                g.fill(Path(roundedRect: housing.offsetBy(dx: 3, dy: 4), cornerRadius: 5), with: .color(.black.opacity(0.35)))
                g.fill(Path(roundedRect: housing, cornerRadius: 5), with: .color(RGB(0x16181d).color))
                var urgent = 0.0
                if let head = sim.lanes[a].first(where: { !$0.passed && !$0.committed && $0.wait > 0 }) {
                    urgent = head.wait / sim.patience(for: head)
                }
                if urgent > 0.35 {
                    let pulse = 0.6 + 0.4 * sin(time * 12)
                    g.stroke(Path(roundedRect: housing, cornerRadius: 5),
                             with: .color(Color(red: 1, green: (200 - 160 * min(1, urgent)) / 255, blue: 0.24).opacity(pulse)), lineWidth: 2.5)
                } else {
                    g.stroke(Path(roundedRect: housing, cornerRadius: 5), with: .color(.white.opacity(0.35)), lineWidth: 1)
                }
                let states: [Signal] = [.red, .yellow, .green]
                for (i, s) in states.enumerated() {
                    let ly = y - 12 + Double(i) * 12
                    if s == light.state {
                        glowCircle(g, x, ly, 9, signalColor(s), 0.8)
                        g.fill(circle(x, ly, 4.6), with: .color(signalColor(s).color))
                    } else {
                        g.fill(circle(x, ly, 4.6), with: .color(.white.opacity(0.1)))
                    }
                }
            }
            for r in sim.ripples {
                let x = r.x * u, y = r.y * u
                g.stroke(circle(x, y, 18 + r.t * 60), with: .color(.white.opacity(max(0, 1 - r.t / 0.5))), lineWidth: 2)
            }
        }

        private static func drawBubbles(_ g: GraphicsContext, sim: Simulation, time: Double) {
            guard sim.phase == .play else { return }
            let u = sim.city.unit
            for lane in sim.lanes {
                for c in lane where !c.crashed {
                    let frac = c.wait / sim.patience(for: c)
                    if frac < 0.35 && c.angry <= 0 { continue }
                    let ap = sim.city.approaches[c.approach]
                    let f = sim.front(c)
                    let bx = (Double(f.x) - ap.dx * c.len * 0.5 + ap.lx * 2.2) * u
                    let by = (Double(f.y) - ap.dy * c.len * 0.5 + ap.ly * 2.2) * u - 6
                    let pulse = c.angry > 0 ? 1 + 0.15 * sin(time * 30) : 1
                    var b = g
                    b.translateBy(x: bx, y: by)
                    b.scaleBy(x: pulse, y: pulse)
                    let r = 15.0
                    b.fill(circle(1, 2, r), with: .color(.black.opacity(0.25)))
                    b.fill(circle(0, 0, r), with: .color(c.angry > 0 ? Palette.red.color : .white))
                    b.stroke(circle(0, 0, r - 3), with: .color(.black.opacity(0.12)), lineWidth: 3.5)
                    let ring: Color = frac > 0.7 ? Palette.red.color : (frac > 0.5 ? Palette.amber.color : Palette.green.color)
                    var rot = b
                    rot.rotate(by: .degrees(-90))
                    rot.stroke(circle(0, 0, r - 3).trimmedPath(from: 0, to: max(0, min(1, 1 - frac))), with: .color(ring),
                               style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    let label: Color = c.angry > 0 ? .white : (c.kind == .police ? RGB(0x1f4fbf).color : RGB(0x1a1c22).color)
                    b.draw(Text(c.kind == .police ? "!!!" : "PYP").font(.system(size: 9, weight: .heavy)).foregroundColor(label), at: .zero)
                }
            }
        }

        private static func drawPending(_ g: GraphicsContext, sim: Simulation) {
            guard sim.phase == .play else { return }
            let c = sim.city, u = c.unit
            for a in 0..<4 where sim.pending[a] > 0 {
                let n = sim.pending[a], ap = c.approaches[a]
                let ex = (c.cx + ap.lx - ap.dx * (ap.dist0 - 0.9)) * u, ey = (c.cy + ap.ly - ap.dy * (ap.dist0 - 0.9)) * u
                let x = min(c.wu * u - 30, max(30, ex)), y = min(c.hu * u - 30, max(90, ey))
                let pill = CGRect(x: x - 20, y: y - 12, width: 40, height: 24)
                g.fill(Path(roundedRect: pill, cornerRadius: 12), with: .color(n >= 3 ? Palette.red.color : Palette.amber.color))
                g.draw(Text("+\(n)").font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(RGB(0x1a1406).color),
                       at: CGPoint(x: x, y: y))
            }
        }

        private static func drawPopups(_ g: GraphicsContext, sim: Simulation) {
            let u = sim.city.unit
            for p in sim.popups {
                let a = max(0, min(1, (1 - p.t / 1.1) * 1.4))
                let col: Color = p.tint == 1 ? Palette.amber.color : (p.tint == 2 ? RGB(0xff6b5e).color : .white)
                let pt = CGPoint(x: p.x * u, y: p.y * u - p.t * 34)
                let size: CGFloat = p.text.count > 3 ? 14 : 18
                var o = g
                o.opacity = a
                o.draw(Text(p.text).font(.system(size: size, weight: .black, design: .rounded)).foregroundColor(.black.opacity(0.55)),
                       at: CGPoint(x: pt.x + 1.5, y: pt.y + 1.5))
                o.draw(Text(p.text).font(.system(size: size, weight: .black, design: .rounded)).foregroundColor(col), at: pt)
            }
        }
    }
}
