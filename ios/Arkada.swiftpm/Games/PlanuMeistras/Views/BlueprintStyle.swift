import SwiftUI

extension PlanuMeistras {

    enum Palette {
        static let paper = Color(red: 0.05, green: 0.20, blue: 0.45)
        static let paperDeep = Color(red: 0.03, green: 0.12, blue: 0.30)
        static let ink = Color.white
        static let stamp = Color(red: 0.86, green: 0.12, blue: 0.16)

        static func room(_ hue: Double) -> Color {
            Color(hue: 0.08 + hue * 0.85, saturation: 0.45, brightness: 1)
        }
    }

    /// Mėlyno brėžinio (blueprint) fonas su tinkleliu.
    struct BlueprintBackground: View {
        var spacing: CGFloat = 22

        var body: some View {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Palette.paper, Palette.paperDeep]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                var minor = Path()
                var x: CGFloat = 0
                while x < size.width { minor.move(to: CGPoint(x: x, y: 0)); minor.addLine(to: CGPoint(x: x, y: size.height)); x += spacing }
                var y: CGFloat = 0
                while y < size.height { minor.move(to: CGPoint(x: 0, y: y)); minor.addLine(to: CGPoint(x: size.width, y: y)); y += spacing }
                ctx.stroke(minor, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
            }
            .ignoresSafeArea()
        }
    }

    /// Užpildas: langelių sąjunga.
    struct CellsShape: Shape {
        let cells: [Cell]
        let cell: CGFloat

        func path(in rect: CGRect) -> Path {
            var p = Path()
            for c in cells {
                p.addRect(CGRect(x: CGFloat(c.x) * cell, y: CGFloat(c.y) * cell, width: cell, height: cell))
            }
            return p
        }
    }

    /// Kontūras: tik išorinės figūros kraštinės (kaip sienos brėžinyje).
    struct EdgesShape: Shape {
        let cells: [Cell]
        let cell: CGFloat

        func path(in rect: CGRect) -> Path {
            let set = Set(cells)
            var p = Path()
            for c in cells {
                let x0 = CGFloat(c.x) * cell, y0 = CGFloat(c.y) * cell
                let x1 = x0 + cell, y1 = y0 + cell
                if !set.contains(Cell(x: c.x, y: c.y - 1)) { p.move(to: CGPoint(x: x0, y: y0)); p.addLine(to: CGPoint(x: x1, y: y0)) }
                if !set.contains(Cell(x: c.x, y: c.y + 1)) { p.move(to: CGPoint(x: x0, y: y1)); p.addLine(to: CGPoint(x: x1, y: y1)) }
                if !set.contains(Cell(x: c.x - 1, y: c.y)) { p.move(to: CGPoint(x: x0, y: y0)); p.addLine(to: CGPoint(x: x0, y: y1)) }
                if !set.contains(Cell(x: c.x + 1, y: c.y)) { p.move(to: CGPoint(x: x1, y: y0)); p.addLine(to: CGPoint(x: x1, y: y1)) }
            }
            return p
        }
    }

    /// Vidinės tinklelio linijos (punktyrinės) plano viduje.
    struct InnerGridShape: Shape {
        let cells: [Cell]
        let cell: CGFloat

        func path(in rect: CGRect) -> Path {
            let set = Set(cells)
            var p = Path()
            for c in cells {
                let x0 = CGFloat(c.x) * cell, y0 = CGFloat(c.y) * cell
                if set.contains(Cell(x: c.x + 1, y: c.y)) {
                    p.move(to: CGPoint(x: x0 + cell, y: y0)); p.addLine(to: CGPoint(x: x0 + cell, y: y0 + cell))
                }
                if set.contains(Cell(x: c.x, y: c.y + 1)) {
                    p.move(to: CGPoint(x: x0, y: y0 + cell)); p.addLine(to: CGPoint(x: x0 + cell, y: y0 + cell))
                }
            }
            return p
        }
    }

    /// Vienas kambarys – užpildas, sienos ir „45-3 / 12,25“ užrašas kaip inventorizacijos plane.
    struct PieceView: View {
        let room: Room
        let shape: [Cell]
        let cell: CGFloat
        var placed = false
        var lifted = false
        var glowing = false

        var body: some View {
            let size = Poly.size(shape)
            let label = Poly.labelCell(shape)
            ZStack(alignment: .topLeading) {
                CellsShape(cells: shape, cell: cell)
                    .fill(Palette.room(room.hue).opacity(placed ? 0.30 : 0.55))
                EdgesShape(cells: shape, cell: cell)
                    .stroke(Palette.ink, style: StrokeStyle(lineWidth: placed ? 2.5 : 2, lineCap: .square))
                VStack(spacing: 0) {
                    Text(room.code)
                        .font(.system(size: max(8, cell * 0.24), weight: .bold, design: .monospaced))
                    if cell >= 30 {
                        Text(room.area.lt())
                            .font(.system(size: max(7, cell * 0.2), weight: .regular, design: .monospaced))
                    }
                }
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: cell, height: cell)
                .offset(x: CGFloat(label.x) * cell, y: CGFloat(label.y) * cell)
            }
            .frame(width: CGFloat(size.w) * cell, height: CGFloat(size.h) * cell, alignment: .topLeading)
            .shadow(color: glowing ? Color.yellow : Color.black.opacity(lifted ? 0.5 : 0), radius: glowing ? 12 : 10, y: lifted ? 8 : 0)
            .scaleEffect(lifted ? 1.04 : 1)
            .contentShape(CellsShape(cells: shape, cell: cell))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(room.name) \(room.code), \(room.area.lt()) kvadratinių metrų")
        }
    }
}
