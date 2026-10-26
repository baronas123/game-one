import CoreGraphics
import Foundation

extension Sankryza {

    struct Building {
        let rect: CGRect          // pėdsakas žemėje
        let lift: Double          // kiek stogas „pakeltas“ (pseudo-3D)
        let roof: Int             // stogo spalvos indeksas
        let windows: [CGRect]     // fasado langai
        let lit: [Int]            // 0 – tamsus, 1 – šiltas, 2 – šaltas (naktį)
        let units: [CGRect]       // kondicionieriai ant stogo
        let skylight: CGRect?

        var roofRect: CGRect { rect.offsetBy(dx: 0, dy: -lift) }
    }

    struct Tree {
        let x: Double, y: Double, r: Double
        let tone: Int
    }

    /// Statinis miestas aplink sankryžą (vienetais; 1 vienetas = juostos plotis).
    struct CityLayout {
        let unit: Double
        let wu: Double, hu: Double
        let cx: Double, cy: Double
        let r: Double, cw: Double, stopD: Double, sidewalk: Double
        let approaches: [Approach]
        let lights: [CGPoint]
        let board: CGRect
        let buildings: [Building]
        let parks: [CGRect]
        let trees: [Tree]
        let lamps: [CGPoint]

        static let empty = CityLayout(unit: 0, wu: 1, hu: 1, cx: 0.5, cy: 0.5, r: 1, cw: 0.75, stopD: 1.97, sidewalk: 0.62,
                                      approaches: (0..<4).map { _ in Approach(dx: 0, dy: 1, lx: 0, ly: 0, dist0: 1, far: 1, sStop: 0) },
                                      lights: Array(repeating: .zero, count: 4), board: .zero,
                                      buildings: [], parks: [], trees: [], lamps: [])

        static func make(size: CGSize, topInset: Double, bottomInset: Double) -> CityLayout {
            let w = Double(size.width), h = Double(size.height)
            let unit = min(58, max(26, min(w, h) / 11))
            let wu = w / unit, hu = h / unit, top = topInset / unit, bottom = bottomInset / unit
            let cx = wu / 2, cy = (hu + top - bottom) / 2
            let r = 1.0, cw = 0.75, stopD = r + 0.12 + cw + 0.1, sw = 0.62

            func edge(_ dx: Double, _ dy: Double) -> Double {
                if dx > 0 { return wu - cx }
                if dx < 0 { return cx }
                if dy > 0 { return hu - cy }
                return cy
            }
            let dirs: [(Double, Double)] = [(0, -1), (1, 0), (0, 1), (-1, 0)]
            let approaches = dirs.map { d -> Approach in
                let dist0 = edge(-d.0, -d.1) + 0.3
                return Approach(dx: d.0, dy: d.1, lx: -d.1 * 0.5, ly: d.0 * 0.5,
                                dist0: dist0, far: edge(d.0, d.1), sStop: dist0 - stopD)
            }
            let lights = [CGPoint(x: cx + r + 0.5, y: cy + stopD + 0.1), CGPoint(x: cx - stopD - 0.1, y: cy + r + 0.5),
                          CGPoint(x: cx - r - 0.5, y: cy - stopD - 0.1), CGPoint(x: cx + stopD + 0.1, y: cy - r - 0.5)]

            var rng = SplitMix64(seed: 4521)
            let m = 0.28
            let board = CGRect(x: cx + r + sw + 0.25, y: cy - r - sw - 0.25 - 1.5, width: 2.6, height: 1.5)
            var quads = [
                CGRect(x: m, y: m, width: cx - r - sw - 2 * m, height: cy - r - sw - 2 * m),
                CGRect(x: cx + r + sw + m, y: m, width: wu - (cx + r + sw + m) - m,
                       height: min(cy - r - sw - m, Double(board.minY) - 0.5) - m),
                CGRect(x: m, y: cy + r + sw + m + 0.7, width: cx - r - sw - 2 * m, height: hu - (cy + r + sw + m + 0.7) - m),
                CGRect(x: cx + r + sw + m, y: cy + r + sw + m + 0.7, width: wu - (cx + r + sw + m) - m,
                       height: hu - (cy + r + sw + m + 0.7) - m)
            ]
            let sideX = Double(board.maxX) + 0.4
            let sideW = wu - m - sideX, sideH = (cy - r - sw - m) - (Double(board.minY) - 0.1)
            if sideW > 0.5 && sideH > 0.5 {
                quads.append(CGRect(x: sideX, y: Double(board.minY) - 0.1, width: sideW, height: sideH))
            }
            // CGRect.width grąžina absoliučią reikšmę, todėl neigiamus kvartalus išmetame čia.
            quads = quads.filter { $0.origin.x + $0.size.width > $0.origin.x + 0.5 && $0.origin.y + $0.size.height > $0.origin.y + 0.5 }

            var buildings: [Building] = []
            var parks: [CGRect] = []
            var trees: [Tree] = []
            func rnd() -> Double { Double(rng.next() % 1_000_000) / 1_000_000 }

            for q in quads {
                var lots: [CGRect] = []
                split(q, depth: 0, rnd: rnd, into: &lots)
                for lot in lots {
                    if rnd() < 0.2 || Double(lot.width * lot.height) < 1.5 {
                        parks.append(lot)
                        let n = max(1, Int(Double(lot.width * lot.height) / 1.2))
                        for _ in 0..<n {
                            trees.append(Tree(x: Double(lot.minX) + 0.3 + rnd() * max(0.01, Double(lot.width) - 0.6),
                                              y: Double(lot.minY) + 0.3 + rnd() * max(0.01, Double(lot.height) - 0.6),
                                              r: 0.25 + rnd() * 0.15, tone: Int(rnd() * 4)))
                        }
                    } else {
                        buildings.append(building(lot, rnd: rnd))
                    }
                }
            }
            // Medžiai palei šaligatvius
            func along(_ fixed: Double, to end: Double, vertical: Bool) {
                var t = 0.8
                while t < end {
                    let off = vertical ? t - cy : t - cx
                    if abs(off) >= r + sw + 1.6 {
                        trees.append(Tree(x: vertical ? fixed : t, y: vertical ? t : fixed, r: 0.26, tone: Int(rnd() * 4)))
                    }
                    t += 1.7
                }
            }
            along(cx - r - sw * 0.55, to: hu, vertical: true)
            along(cx + r + sw * 0.55, to: hu, vertical: true)
            along(cy - r - sw * 0.55, to: wu, vertical: false)
            along(cy + r + sw * 0.55, to: wu, vertical: false)

            var lamps: [CGPoint] = [(-1.0, -1.0), (1, -1), (-1, 1), (1, 1)].map { CGPoint(x: cx + $0.0 * (r + 0.3), y: cy + $0.1 * (r + 0.3)) }
            var t = 3.5
            while t < max(wu, hu) {
                lamps += [CGPoint(x: cx + r + 0.25, y: cy + t), CGPoint(x: cx - r - 0.25, y: cy - t),
                          CGPoint(x: cx + t, y: cy - r - 0.25), CGPoint(x: cx - t, y: cy + r + 0.25)]
                t += 4
            }
            lamps = lamps.filter { $0.x > -1 && $0.y > -1 && Double($0.x) < wu + 1 && Double($0.y) < hu + 1 }

            return CityLayout(unit: unit, wu: wu, hu: hu, cx: cx, cy: cy, r: r, cw: cw, stopD: stopD, sidewalk: sw,
                              approaches: approaches, lights: lights, board: board,
                              buildings: buildings, parks: parks, trees: trees, lamps: lamps)
        }

        private static func split(_ r: CGRect, depth: Int, rnd: () -> Double, into out: inout [CGRect]) {
            let w = Double(r.width), h = Double(r.height)
            if w < 1.1 || h < 1.1 { return }
            if (w > 3.4 || h > 3.4) && depth < 6 {
                let gap = 0.32
                if w >= h {
                    let m = Double(r.minX) + w * (0.38 + rnd() * 0.24)
                    split(CGRect(x: Double(r.minX), y: Double(r.minY), width: m - gap / 2 - Double(r.minX), height: h), depth: depth + 1, rnd: rnd, into: &out)
                    split(CGRect(x: m + gap / 2, y: Double(r.minY), width: Double(r.maxX) - m - gap / 2, height: h), depth: depth + 1, rnd: rnd, into: &out)
                } else {
                    let m = Double(r.minY) + h * (0.38 + rnd() * 0.24)
                    split(CGRect(x: Double(r.minX), y: Double(r.minY), width: w, height: m - gap / 2 - Double(r.minY)), depth: depth + 1, rnd: rnd, into: &out)
                    split(CGRect(x: Double(r.minX), y: m + gap / 2, width: w, height: Double(r.maxY) - m - gap / 2), depth: depth + 1, rnd: rnd, into: &out)
                }
                return
            }
            out.append(r)
        }

        private static func building(_ r: CGRect, rnd: () -> Double) -> Building {
            let h = 0.35 + rnd() * 0.75, lift = h * 0.55
            let roof = Int(rnd() * 8) % 8
            let roofRect = r.offsetBy(dx: 0, dy: -lift)
            var windows: [CGRect] = []
            var lit: [Int] = []
            if lift > 0.22 {
                let rows = max(1, Int(lift / 0.26))
                for iy in 0..<rows {
                    var x = Double(r.minX) + 0.14
                    while x < Double(r.maxX) - 0.2 {
                        windows.append(CGRect(x: x, y: Double(roofRect.maxY) + 0.07 + Double(iy) * 0.26, width: 0.14, height: 0.13))
                        lit.append(rnd() < 0.6 ? (rnd() < 0.8 ? 1 : 2) : 0)
                        x += 0.3
                    }
                }
            }
            var units: [CGRect] = []
            let n = 1 + Int(rnd() * 3)
            for _ in 0..<n {
                let s = 0.22 + rnd() * 0.2
                units.append(CGRect(x: Double(r.minX) + 0.25 + rnd() * max(0.01, Double(r.width) - 0.5 - s),
                                    y: Double(roofRect.minY) + 0.25 + rnd() * max(0.01, Double(r.height) - 0.5 - s),
                                    width: s, height: s))
            }
            var skylight: CGRect?
            if r.width > 1.6 && rnd() < 0.5 {
                skylight = CGRect(x: Double(r.minX) + Double(r.width) * 0.55, y: Double(roofRect.minY) + Double(r.height) * 0.3,
                                  width: Double(r.width) * 0.25, height: Double(r.height) * 0.3)
            }
            return Building(rect: r, lift: lift, roof: roof, windows: windows, lit: lit, units: units, skylight: skylight)
        }
    }
}
