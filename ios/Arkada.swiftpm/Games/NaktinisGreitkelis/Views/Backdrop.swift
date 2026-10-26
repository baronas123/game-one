import SwiftUI

extension NaktinisGreitkelis {

    enum Neon {
        static let night = Color(red: 0.03, green: 0.01, blue: 0.10)
        static let magenta = Color(red: 1.0, green: 0.24, blue: 0.65)
        static let cyan = Color(red: 0.18, green: 0.89, blue: 1.0)
        static let amber = Color(red: 1.0, green: 0.70, blue: 0.28)
        static let fog = Color(red: 0.23, green: 0.06, blue: 0.32)
        static let groundA = Color(red: 0.07, green: 0.02, blue: 0.15)
        static let groundB = Color(red: 0.09, green: 0.03, blue: 0.19)
        static let roadA = Color(red: 0.11, green: 0.09, blue: 0.19)
        static let roadB = Color(red: 0.13, green: 0.11, blue: 0.22)
        static let rumbleB = Color(red: 0.96, green: 0.94, blue: 1.0)
        static let lane = Color(red: 0.91, green: 0.90, blue: 1.0)
        static let sign = Color(red: 0.05, green: 0.48, blue: 0.31)
        static let pine = Color(red: 0.04, green: 0.01, blue: 0.09)

        /// Eismo mašinų spalvos (r, g, b).
        static let cars: [(Double, Double, Double)] = [
            (1.0, 0.24, 0.65), (0.18, 0.89, 1.0), (1.0, 0.83, 0.30), (0.49, 1.0, 0.42),
            (0.70, 0.53, 1.0), (1.0, 0.48, 0.35), (0.91, 0.91, 0.94)
        ]
    }

    /// Fono kontūrai (žvaigždės, saulė, kalnai, miestas) – sukuriami vieną kartą tam ekrano dydžiui.
    final class Backdrop {
        private(set) var size: CGSize = .zero
        private(set) var horizon: CGFloat = 0
        private(set) var stars = Path()
        private(set) var sunCenter: CGPoint = .zero
        private(set) var sunRadius: CGFloat = 0
        private(set) var mountains = Path()
        private(set) var mountainRim = Path()
        private(set) var buildings = Path()
        private(set) var windowsWarm = Path()
        private(set) var windowsCool = Path()
        private(set) var layerWidth: CGFloat = 0

        func prepare(size: CGSize, horizon: CGFloat) {
            guard size != self.size || horizon != self.horizon else { return }
            self.size = size
            self.horizon = horizon
            var rng = SplitMix64(seed: 7)
            func r() -> CGFloat { CGFloat(Double.random(in: 0..<1, using: &rng)) }

            var s = Path()
            for _ in 0..<140 {
                let d: CGFloat = r() < 0.1 ? 2 : 1
                s.addRect(CGRect(x: r() * size.width, y: r() * horizon * 0.6, width: d, height: d))
            }
            stars = s
            sunRadius = min(size.width, size.height) * 0.22
            sunCenter = CGPoint(x: size.width / 2, y: horizon - sunRadius * 0.35)

            layerWidth = max(size.width, 600) * 2
            var m = Path(), rim = Path()
            var x: CGFloat = 0
            var pts: [CGPoint] = []
            var rm = SplitMix64(seed: 11)
            while x <= layerWidth {
                let h = horizon * 0.28 * (0.25 + CGFloat(Double.random(in: 0..<1, using: &rm)) * 0.75)
                pts.append(CGPoint(x: x, y: horizon - h))
                x += 30 + CGFloat(Double.random(in: 0..<1, using: &rm)) * 70
            }
            pts[pts.count - 1] = CGPoint(x: layerWidth, y: pts[0].y)
            m.move(to: CGPoint(x: 0, y: horizon + 2))
            for p in pts { m.addLine(to: p) }
            m.addLine(to: CGPoint(x: layerWidth, y: horizon + 2))
            m.closeSubpath()
            rim.addLines(pts)
            mountains = m
            mountainRim = rim

            var b = Path(), warm = Path(), cool = Path()
            var rc = SplitMix64(seed: 23)
            func rr() -> CGFloat { CGFloat(Double.random(in: 0..<1, using: &rc)) }
            var bx: CGFloat = 0
            while bx < layerWidth {
                let bw = 14 + rr() * 34
                let bh = horizon * (0.04 + rr() * (rr() < 0.15 ? 0.22 : 0.1))
                if rr() < 0.75 {
                    b.addRect(CGRect(x: bx, y: horizon - bh, width: bw, height: bh + 2))
                    var wy = horizon - bh + 4
                    while wy < horizon - 3 {
                        var wx = bx + 3
                        while wx < bx + bw - 3 {
                            if rr() < 0.22 {
                                let rect = CGRect(x: wx, y: wy, width: 2, height: 2)
                                if rr() < 0.7 { warm.addRect(rect) } else { cool.addRect(rect) }
                            }
                            wx += 5
                        }
                        wy += 5
                    }
                }
                bx += bw + rr() * 8
            }
            buildings = b
            windowsWarm = warm
            windowsCool = cool
        }

        func draw(in ctx: inout GraphicsContext, farOffset: CGFloat, cityOffset: CGFloat) {
            let w = size.width
            let sky = Gradient(stops: [
                .init(color: Color(red: 0.02, green: 0.0, blue: 0.06), location: 0),
                .init(color: Color(red: 0.11, green: 0.04, blue: 0.24), location: 0.45),
                .init(color: Color(red: 0.42, green: 0.10, blue: 0.43), location: 0.78),
                .init(color: Color(red: 1.0, green: 0.24, blue: 0.53), location: 0.93),
                .init(color: Color(red: 1.0, green: 0.70, blue: 0.28), location: 1)
            ])
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon + 2)),
                     with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
            ctx.fill(stars, with: .color(.white.opacity(0.6)))

            // Saulė su juostomis
            let r = sunRadius
            let sunRect = CGRect(x: sunCenter.x - r, y: sunCenter.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: sunRect.insetBy(dx: -r * 0.5, dy: -r * 0.5)),
                     with: .radialGradient(Gradient(colors: [Neon.magenta.opacity(0.45), Neon.magenta.opacity(0)]),
                                           center: sunCenter, startRadius: r * 0.8, endRadius: r * 1.5))
            ctx.drawLayer { l in
                l.clip(to: Path(ellipseIn: sunRect))
                var cut = Path(sunRect)
                for i in 0..<7 {
                    let y = sunRect.minY + r * (1.0 + CGFloat(i) * 0.14)
                    cut.addRect(CGRect(x: sunRect.minX, y: y, width: r * 2, height: 1.5 + CGFloat(i) * 1.6))
                }
                l.fill(cut, with: .linearGradient(
                    Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.66), Neon.amber, Color(red: 1, green: 0.18, blue: 0.56)]),
                    startPoint: CGPoint(x: 0, y: sunRect.minY), endPoint: CGPoint(x: 0, y: sunRect.maxY)),
                       style: FillStyle(eoFill: true))
            }

            // Kalnai ir miestas – kartojami horizontaliai
            for (offset, isCity) in [(farOffset, false), (cityOffset, true)] {
                let lw = layerWidth
                var ox = offset.truncatingRemainder(dividingBy: lw)
                if ox < 0 { ox += lw }
                for shift in [-ox, lw - ox] {
                    var c = ctx
                    c.translateBy(x: shift, y: 0)
                    if isCity {
                        c.fill(buildings, with: .color(Color(red: 0.07, green: 0.02, blue: 0.16)))
                        c.fill(windowsWarm, with: .color(Color(red: 1, green: 0.78, blue: 0.47).opacity(0.8)))
                        c.fill(windowsCool, with: .color(Neon.cyan.opacity(0.8)))
                    } else {
                        c.fill(mountains, with: .color(Color(red: 0.16, green: 0.05, blue: 0.29)))
                        c.stroke(mountainRim, with: .color(Neon.magenta.opacity(0.55)), lineWidth: 1.5)
                    }
                }
            }
        }
    }
}
