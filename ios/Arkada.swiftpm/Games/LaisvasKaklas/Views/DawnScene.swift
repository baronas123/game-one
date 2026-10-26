import SwiftUI

extension LaisvasKaklas {

    enum Palette {
        static let ink = Color(red: 0.12, green: 0.10, blue: 0.22)
        static let night = Color(red: 0.10, green: 0.10, blue: 0.26)
        static let peach = Color(red: 1.0, green: 0.76, blue: 0.56)
        static let gold = Color(red: 1.0, green: 0.84, blue: 0.48)
        static let lantern = Color(red: 0.99, green: 0.58, blue: 0.33)
        static let calm = Color(red: 0.45, green: 0.86, blue: 0.78)
        static let warn = Color(red: 1.0, green: 0.62, blue: 0.35)
        static let stop = Color(red: 0.86, green: 0.22, blue: 0.27)

        static func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ f: Double) -> Color {
            let k = max(0, min(1, f))
            return Color(red: a.0 + (b.0 - a.0) * k, green: a.1 + (b.1 - a.1) * k, blue: a.2 + (b.2 - a.2) * k)
        }
    }

    /// Ramus aušros peizažas: popierinis žibintas juda kartu su galva link švytinčių taikinių.
    /// Kuo toliau sesija, tuo labiau išaušta.
    struct DawnScene: View {
        let engine: SessionEngine

        var body: some View {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    DawnPainter.draw(&ctx, size: size,
                                     t: timeline.date.timeIntervalSinceReferenceDate, engine: engine)
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }

    enum DawnPainter {

        static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double, engine e: SessionEngine) {
            let w = size.width, h = size.height
            let p = e.sessionProgress

            drawSky(&ctx, w: w, h: h, p: p, t: t)
            drawHills(&ctx, w: w, h: h, p: p, t: t)

            let center = CGPoint(x: w / 2, y: h * 0.42)
            let axis = e.currentAxis
            let kind = e.current?.kind ?? .reach

            if e.phase == .active {
                if kind == .isometric {
                    drawStillnessRing(&ctx, center: center, deviation: e.stillDeviation,
                                      holding: e.isHolding, progress: e.holdProgress, t: t)
                } else {
                    for side in e.targetSides {
                        drawTarget(&ctx, at: targetPoint(axis: axis, side: side, center: center, w: w, h: h),
                                   axis: axis, t: t, active: e.isHolding)
                    }
                }
            }

            // Žibinto padėtis pagal galvą.
            let v = max(-1.4, min(1.4, e.valueNorm))
            var pos = center
            var scale: CGFloat = 1
            var angle = Angle.zero
            switch axis {
            case .yaw:
                pos.x += CGFloat(v) * w * 0.30
            case .roll:
                pos.x += CGFloat(v) * w * 0.30
                angle = .degrees(v * 18)
            case .pitch:
                pos.y += CGFloat(v) * h * 0.14
            case .depth:
                let k = max(0, min(1.4, v))
                scale = 1 - 0.32 * CGFloat(k)
                pos.y -= CGFloat(k) * h * 0.05
            case .none:
                if kind == .isometric {
                    let jitter = min(12, e.stillDeviation * 1.6)
                    pos.x += CGFloat(sin(t * 23) * jitter)
                } else {
                    pos.y -= CGFloat(v) * h * 0.06
                }
            }
            if e.phase == .intro {
                pos.y += CGFloat(sin(t * 1.3) * 6)
            }

            if e.isHolding && kind != .isometric {
                drawHoldRing(&ctx, at: pos, radius: 58 * scale, progress: e.holdProgress)
            }
            drawLantern(&ctx, at: pos, scale: scale, angle: angle,
                        glow: e.isHolding ? 1 : 0.6, t: t)
            drawBursts(&ctx, engine: e, center: center, w: w, h: h, t: t)
        }

        static func targetPoint(axis: TrackedAxis, side: Int, center: CGPoint, w: CGFloat, h: CGFloat) -> CGPoint {
            switch axis {
            case .yaw, .roll: return CGPoint(x: center.x + CGFloat(side) * w * 0.30, y: center.y)
            case .pitch: return CGPoint(x: center.x, y: center.y + CGFloat(side) * h * 0.14)
            case .depth: return CGPoint(x: center.x, y: center.y - h * 0.05)
            case .none: return center
            }
        }

        // MARK: - Dangus ir kalvos

        private static func drawSky(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, p: Double, t: Double) {
            let top = Palette.mix((0.09, 0.09, 0.24), (0.38, 0.58, 0.86), p)
            let mid = Palette.mix((0.30, 0.20, 0.45), (0.80, 0.70, 0.86), p)
            let horizon = Palette.mix((0.55, 0.32, 0.50), (1.0, 0.78, 0.56), p)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                     with: .linearGradient(Gradient(stops: [
                        .init(color: top, location: 0),
                        .init(color: mid, location: 0.45),
                        .init(color: horizon, location: 0.72)
                     ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

            // Žvaigždės blėsta aušrai artėjant.
            let starAlpha = max(0, 1 - p * 1.7)
            if starAlpha > 0.02 {
                for i in 0..<46 {
                    let fx = (sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let fy = (sin(Double(i) * 78.233) * 12345.678).truncatingRemainder(dividingBy: 1)
                    let x = CGFloat(abs(fx)) * w
                    let y = CGFloat(abs(fy)) * h * 0.55
                    let tw = 0.5 + 0.5 * sin(t * (1 + Double(i % 5) * 0.3) + Double(i))
                    let r: CGFloat = i % 7 == 0 ? 1.6 : 1
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(starAlpha * (0.35 + 0.55 * tw))))
                }
            }

            // Saulė kyla kartu su sesijos progresu.
            let sun = CGPoint(x: w * 0.5, y: h * (0.74 - 0.20 * p))
            let sr = w * 0.13
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - w * 0.7, y: sun.y - w * 0.7, width: w * 1.4, height: w * 1.4)),
                     with: .radialGradient(Gradient(colors: [Palette.peach.opacity(0.45 + 0.2 * p), .clear]),
                                           center: sun, startRadius: sr * 0.6, endRadius: w * 0.7))
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - sr, y: sun.y - sr, width: sr * 2, height: sr * 2)),
                     with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.75),
                                                             Color(red: 1, green: 0.66, blue: 0.42)]),
                                           startPoint: CGPoint(x: sun.x, y: sun.y - sr),
                                           endPoint: CGPoint(x: sun.x, y: sun.y + sr)))
        }

        private static func drawHills(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, p: Double, t: Double) {
            let layers: [(base: CGFloat, amp: CGFloat, freq: CGFloat, phase: CGFloat,
                          night: (Double, Double, Double), day: (Double, Double, Double))] = [
                (0.70, 16, 1.6, 0.4, (0.24, 0.16, 0.36), (0.62, 0.52, 0.70)),
                (0.78, 22, 2.3, 1.7, (0.17, 0.12, 0.28), (0.44, 0.40, 0.60)),
                (0.88, 14, 3.1, 2.9, (0.10, 0.08, 0.18), (0.26, 0.25, 0.42))
            ]
            for (i, layer) in layers.enumerated() {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: h))
                let steps = 48
                for s in 0...steps {
                    let x = w * CGFloat(s) / CGFloat(steps)
                    let y = h * layer.base
                        + layer.amp * CGFloat(sin(Double(x / w * layer.freq * 2 * .pi + layer.phase)))
                        + layer.amp * 0.4 * CGFloat(sin(Double(x / w * layer.freq * 5 * .pi + layer.phase * 2)))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()
                ctx.fill(path, with: .color(Palette.mix(layer.night, layer.day, p)))

                // Rūkas tarp sluoksnių, lėtai slenkantis.
                if i < 2 {
                    let drift = CGFloat(sin(t * 0.07 + Double(i))) * 30
                    let band = CGRect(x: -40 + drift, y: h * layer.base - 10, width: w + 80, height: 46)
                    ctx.fill(Path(roundedRect: band, cornerRadius: 23),
                             with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.10 + 0.06 * p), .clear]),
                                                   startPoint: CGPoint(x: 0, y: band.minY),
                                                   endPoint: CGPoint(x: 0, y: band.maxY)))
                }
            }
        }

        // MARK: - Taikiniai

        private static func drawTarget(_ ctx: inout GraphicsContext, at pt: CGPoint, axis: TrackedAxis, t: Double, active: Bool) {
            let pulse = 1 + 0.08 * CGFloat(sin(t * 2.4))
            if axis == .depth {
                // Gylis: punktyrinis žiedas „toliau“ – žibintas turi sumažėti iki jo.
                let r: CGFloat = 40 * pulse
                let ring = Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
                ctx.stroke(ring, with: .color(Palette.calm.opacity(active ? 0.95 : 0.7)),
                           style: StrokeStyle(lineWidth: 2.5, dash: [6, 6]))
                return
            }
            let r: CGFloat = 26 * pulse
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r * 2.6, y: pt.y - r * 2.6, width: r * 5.2, height: r * 5.2)),
                     with: .radialGradient(Gradient(colors: [Palette.calm.opacity(active ? 0.55 : 0.32), .clear]),
                                           center: pt, startRadius: 0, endRadius: r * 2.6))
            ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                       with: .color(Palette.calm.opacity(0.9)), lineWidth: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)),
                     with: .color(.white.opacity(0.9)))
        }

        private static func drawStillnessRing(_ ctx: inout GraphicsContext, center: CGPoint, deviation: Double,
                                              holding: Bool, progress: Double, t: Double) {
            let r: CGFloat = 70
            let calm = deviation <= 5
            let color = calm ? Palette.calm : Palette.warn
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                       with: .color(color.opacity(0.35)), lineWidth: 6)
            if holding {
                var arc = Path()
                arc.addArc(center: center, radius: r, startAngle: .degrees(-90),
                           endAngle: .degrees(-90 + 360 * progress), clockwise: false)
                ctx.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
        }

        private static func drawHoldRing(_ ctx: inout GraphicsContext, at pos: CGPoint, radius: CGFloat, progress: Double) {
            ctx.stroke(Path(ellipseIn: CGRect(x: pos.x - radius, y: pos.y - radius, width: radius * 2, height: radius * 2)),
                       with: .color(.white.opacity(0.18)), lineWidth: 5)
            var arc = Path()
            arc.addArc(center: pos, radius: radius, startAngle: .degrees(-90),
                       endAngle: .degrees(-90 + 360 * max(0, min(1, progress))), clockwise: false)
            ctx.stroke(arc, with: .color(Palette.gold), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }

        // MARK: - Žibintas

        private static func drawLantern(_ ctx: inout GraphicsContext, at pos: CGPoint, scale: CGFloat,
                                        angle: Angle, glow: Double, t: Double) {
            var c = ctx
            c.translateBy(x: pos.x, y: pos.y)
            c.rotate(by: angle)
            c.scaleBy(x: scale, y: scale)

            let flicker = 0.9 + 0.1 * sin(t * 9) * sin(t * 5.3)
            c.fill(Path(ellipseIn: CGRect(x: -95, y: -95, width: 190, height: 190)),
                   with: .radialGradient(Gradient(colors: [Palette.lantern.opacity(0.45 * glow * flicker), .clear]),
                                         center: .zero, startRadius: 10, endRadius: 95))

            // Virvutė
            var string = Path()
            string.move(to: CGPoint(x: 0, y: -34))
            string.addLine(to: CGPoint(x: 0, y: -70))
            c.stroke(string, with: .color(.white.opacity(0.35)), lineWidth: 1)

            // Kūnas
            let body = Path(roundedRect: CGRect(x: -24, y: -30, width: 48, height: 60), cornerRadius: 20)
            c.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.86, blue: 0.58),
                                                                 Palette.lantern,
                                                                 Color(red: 0.88, green: 0.36, blue: 0.24)]),
                                               startPoint: CGPoint(x: 0, y: -30), endPoint: CGPoint(x: 0, y: 30)))
            // Šonkauliai
            for x in [-12.0, 0.0, 12.0] {
                var rib = Path()
                rib.move(to: CGPoint(x: x * 0.6, y: -28))
                rib.addQuadCurve(to: CGPoint(x: x * 0.6, y: 28), control: CGPoint(x: x * 1.5, y: 0))
                c.stroke(rib, with: .color(Color(red: 0.75, green: 0.30, blue: 0.20).opacity(0.45)), lineWidth: 1)
            }
            // Vidinė liepsna
            c.fill(Path(ellipseIn: CGRect(x: -9, y: -9, width: 18, height: 18)),
                   with: .radialGradient(Gradient(colors: [Color.white.opacity(0.95 * flicker), Palette.gold.opacity(0)]),
                                         center: .zero, startRadius: 0, endRadius: 9))
            // Dangteliai
            let capColor = Color(red: 0.24, green: 0.14, blue: 0.20)
            c.fill(Path(roundedRect: CGRect(x: -15, y: -36, width: 30, height: 7), cornerRadius: 3), with: .color(capColor))
            c.fill(Path(roundedRect: CGRect(x: -13, y: 29, width: 26, height: 6), cornerRadius: 3), with: .color(capColor))
            // Kutas
            var tassel = Path()
            tassel.move(to: CGPoint(x: 0, y: 35))
            tassel.addLine(to: CGPoint(x: CGFloat(sin(t * 1.7)) * 3, y: 50))
            c.stroke(tassel, with: .color(Palette.stop.opacity(0.8)), lineWidth: 2)
        }

        // MARK: - Žiežirbos

        private static func drawBursts(_ ctx: inout GraphicsContext, engine e: SessionEngine, center: CGPoint,
                                       w: CGFloat, h: CGFloat, t: Double) {
            let life = 1.4
            for b in e.bursts {
                let age = t - b.time
                guard age >= 0, age < life else { continue }
                let origin = b.side == 0 ? center : targetPoint(axis: e.currentAxis, side: b.side, center: center, w: w, h: h)
                let fade = 1 - age / life
                for i in 0..<18 {
                    let a = Double(i) / 18 * 2 * .pi + b.time
                    let speed = 70 + Double(i % 4) * 22
                    let d = speed * age * (1 - age * 0.3)
                    let x = origin.x + CGFloat(cos(a) * d)
                    let y = origin.y + CGFloat(sin(a) * d - 26 * age)
                    let r = CGFloat(3.2 * fade)
                    let color = i % 3 == 0 ? Palette.calm : Palette.gold
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(color.opacity(fade)))
                }
            }
        }
    }

    // MARK: - Galvos avataras

    /// Stilizuota galva, kuri atkartoja žaidėjo galvos padėtį (veidrodžiu – kaip žiūrint į veidrodį).
    struct HeadAvatar: View {
        let yaw: Double
        let pitch: Double
        let roll: Double
        var tracking: Bool = true

        var body: some View {
            Canvas { ctx, size in
                let s = min(size.width, size.height)
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                var g = ctx
                g.translateBy(x: c.x, y: c.y)
                // Veidrodis: žaidėjas lenkia dešinę ausį → avataras ekrane linksta į dešinę (kaip veidrodyje).
                g.rotate(by: .degrees(max(-40, min(40, roll))))
                let r = s * 0.36
                let yawK = CGFloat(max(-1, min(1, yaw / 60)))
                let pitchK = CGFloat(max(-1, min(1, pitch / 45)))

                // Kaklas
                g.fill(Path(roundedRect: CGRect(x: -r * 0.32, y: r * 0.7, width: r * 0.64, height: r * 0.7), cornerRadius: r * 0.2),
                       with: .color(Color(red: 0.93, green: 0.74, blue: 0.62).opacity(0.85)))
                // Ausys
                let earShift = yawK * r * 0.25
                for side in [-1.0, 1.0] {
                    let ex = CGFloat(side) * r * 0.98 - earShift
                    g.fill(Path(ellipseIn: CGRect(x: ex - r * 0.14, y: -r * 0.18, width: r * 0.28, height: r * 0.4)),
                           with: .color(Color(red: 0.90, green: 0.68, blue: 0.56)))
                }
                // Veidas
                g.fill(Path(ellipseIn: CGRect(x: -r, y: -r * 1.08, width: r * 2, height: r * 2.1)),
                       with: .linearGradient(Gradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.72),
                                                               Color(red: 0.94, green: 0.72, blue: 0.60)]),
                                             startPoint: CGPoint(x: 0, y: -r), endPoint: CGPoint(x: 0, y: r)))
                // Plaukai
                var hair = Path()
                hair.addArc(center: CGPoint(x: -yawK * r * 0.1, y: -r * 0.2), radius: r * 1.02,
                            startAngle: .degrees(195), endAngle: .degrees(345), clockwise: false)
                hair.closeSubpath()
                g.fill(hair, with: .color(Color(red: 0.28, green: 0.20, blue: 0.24)))
                // Akys ir nosis pasislenka pagal pasukimą / linktelėjimą
                let fx = yawK * r * 0.42
                let fy = pitchK * r * 0.30
                for side in [-1.0, 1.0] {
                    let ex = CGFloat(side) * r * 0.36 + fx
                    g.fill(Path(ellipseIn: CGRect(x: ex - r * 0.09, y: -r * 0.12 + fy, width: r * 0.18, height: r * 0.2)),
                           with: .color(Palette.ink))
                }
                var nose = Path()
                nose.move(to: CGPoint(x: fx, y: r * 0.02 + fy))
                nose.addQuadCurve(to: CGPoint(x: fx + yawK * r * 0.12, y: r * 0.28 + fy),
                                  control: CGPoint(x: fx + yawK * r * 0.22 + 2, y: r * 0.2 + fy))
                g.stroke(nose, with: .color(Color(red: 0.75, green: 0.50, blue: 0.42)), lineWidth: 2)
                var mouth = Path()
                mouth.move(to: CGPoint(x: fx - r * 0.2, y: r * 0.5 + fy))
                mouth.addQuadCurve(to: CGPoint(x: fx + r * 0.2, y: r * 0.5 + fy),
                                   control: CGPoint(x: fx, y: r * 0.62 + fy))
                g.stroke(mouth, with: .color(Color(red: 0.70, green: 0.36, blue: 0.36)), lineWidth: 2)
            }
            .opacity(tracking ? 1 : 0.45)
            .accessibilityLabel(tracking ? "Galvos padėtis sekama" : "Veidas nematomas")
        }
    }

    // MARK: - Skausmo tendencija

    /// Paskutinių 14 sesijų skausmas prieš (pilka) ir po (šilta) mankštos, skalė 0–10.
    struct PainTrendChart: View {
        let records: [SessionRecord]

        var body: some View {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let left: CGFloat = 18, bottom: CGFloat = 6, top: CGFloat = 6
                let plotH = h - top - bottom
                func y(_ v: Int) -> CGFloat { top + plotH * (1 - CGFloat(v) / 10) }
                for v in [0, 5, 10] {
                    var line = Path()
                    line.move(to: CGPoint(x: left, y: y(v)))
                    line.addLine(to: CGPoint(x: w, y: y(v)))
                    ctx.stroke(line, with: .color(.white.opacity(0.12)), lineWidth: 1)
                    ctx.draw(Text("\(v)").font(.system(size: 9, design: .rounded)).foregroundStyle(.white.opacity(0.5)),
                             at: CGPoint(x: 7, y: y(v)))
                }
                guard !records.isEmpty else { return }
                let n = records.count
                func x(_ i: Int) -> CGFloat {
                    n == 1 ? (left + w) / 2 : left + 8 + (w - left - 16) * CGFloat(i) / CGFloat(n - 1)
                }
                var pre = Path(), post = Path()
                for (i, r) in records.enumerated() {
                    let p1 = CGPoint(x: x(i), y: y(r.prePain))
                    let p2 = CGPoint(x: x(i), y: y(r.postPain ?? r.prePain))
                    if i == 0 { pre.move(to: p1); post.move(to: p2) } else { pre.addLine(to: p1); post.addLine(to: p2) }
                }
                ctx.stroke(pre, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                ctx.stroke(post, with: .color(Palette.peach), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                for (i, r) in records.enumerated() {
                    let p2 = CGPoint(x: x(i), y: y(r.postPain ?? r.prePain))
                    ctx.fill(Path(ellipseIn: CGRect(x: p2.x - 3, y: p2.y - 3, width: 6, height: 6)), with: .color(Palette.peach))
                }
            }
            .accessibilityLabel(accessibilityText)
        }

        private var accessibilityText: String {
            guard let last = records.last else { return "Dar nėra įvertinimų" }
            return "Paskutinė mankšta: skausmas prieš \(last.prePain), po \(last.postPain ?? last.prePain) iš 10"
        }
    }
}
