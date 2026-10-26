import Foundation

extension PlanuMeistras {

    /// Vienas plano tinklelio langelis (1 langelis = 1,5 × 1,5 m).
    struct Cell: Hashable {
        var x: Int
        var y: Int

        static func + (a: Cell, b: Cell) -> Cell { Cell(x: a.x + b.x, y: a.y + b.y) }

        var neighbours: [Cell] {
            [Cell(x: x + 1, y: y), Cell(x: x - 1, y: y), Cell(x: x, y: y + 1), Cell(x: x, y: y - 1)]
        }
    }

    /// Vieno langelio plotas m² (1,5 m × 1,5 m).
    static let cellArea: Double = 2.25

    enum Poly {
        /// Perkelia figūrą taip, kad mažiausios koordinatės būtų 0.
        static func normalized(_ cells: [Cell]) -> [Cell] {
            guard let minX = cells.map(\.x).min(), let minY = cells.map(\.y).min() else { return cells }
            return cells
                .map { Cell(x: $0.x - minX, y: $0.y - minY) }
                .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        }

        /// Pasuka 90° pagal laikrodžio rodyklę.
        static func rotated(_ cells: [Cell]) -> [Cell] {
            let h = (cells.map(\.y).max() ?? 0) + 1
            return normalized(cells.map { Cell(x: h - 1 - $0.y, y: $0.x) })
        }

        static func size(_ cells: [Cell]) -> (w: Int, h: Int) {
            ((cells.map(\.x).max() ?? 0) + 1, (cells.map(\.y).max() ?? 0) + 1)
        }

        /// Langelis, kuriame geriausia rašyti kambario numerį – arčiausiai centroido.
        static func labelCell(_ cells: [Cell]) -> Cell {
            let n = Double(cells.count)
            let cx = cells.map { Double($0.x) }.reduce(0, +) / n
            let cy = cells.map { Double($0.y) }.reduce(0, +) / n
            return cells.min {
                let da = pow(Double($0.x) - cx, 2) + pow(Double($0.y) - cy, 2)
                let db = pow(Double($1.x) - cx, 2) + pow(Double($1.y) - cy, 2)
                return da < db
            } ?? cells[0]
        }
    }
}
