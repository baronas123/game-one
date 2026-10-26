import SwiftUI

extension PlanuMeistras {

    enum Mode: Equatable {
        case level(Int)
        case daily

        var blueprint: Blueprint {
            switch self {
            case .level(let n): return LevelGenerator.level(n)
            case .daily: return LevelGenerator.daily()
            }
        }
    }

    struct GameView: View {
        @Environment(\.dismiss) private var dismiss
        @State private var mode: Mode
        @State private var engine: Engine
        @State private var drag: DragState?
        @State private var showWin = false
        @State private var glowing: Int?

        init(mode: Mode) {
            _mode = State(initialValue: mode)
            _engine = State(initialValue: Engine(blueprint: mode.blueprint))
        }

        struct DragState {
            let id: Int
            var location: CGPoint
            /// Kurioje detalės vietoje (0…1) pirštas ją „pagriebė“.
            let grab: CGPoint
            var moved = false
        }

        struct Layout {
            let cell: CGFloat
            let board: CGRect
            let trayCell: CGFloat
            let tray: [Int: CGPoint]
        }

        var body: some View {
            ZStack {
                BlueprintBackground()
                GeometryReader { geo in
                    let layout = makeLayout(geo.size)
                    ZStack(alignment: .topLeading) {
                        board(layout)
                        ghost(layout)
                        ForEach(engine.pieces) { piece in
                            pieceView(piece, layout)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .coordinateSpace(name: "game")
                    .animation(.spring(response: 0.35, dampingFraction: 0.78), value: engine.revision)
                }
                .padding(.top, 64)

                VStack { header; Spacer() }

                if showWin {
                    WinOverlay(engine: engine, mode: mode, onNext: nextLevel, onMenu: { dismiss() })
                        .transition(.opacity)
                }
            }
            .onChange(of: engine.isSolved) { _, solved in
                guard solved else { return }
                saveResult()
                Haptics.success()
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    withAnimation(.easeOut(duration: 0.25)) { showWin = true }
                }
            }
            .statusBarHidden(showWin)
        }

        // MARK: - Antraštė

        private var header: some View {
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Atgal")

                VStack(alignment: .leading, spacing: 0) {
                    Text(engine.blueprint.title)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(engine.placedCount)/\(engine.pieces.count) kambarių · \(engine.blueprint.totalArea.lt()) m²")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 4)

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    StatChip(symbol: "stopwatch", text: engine.elapsedSeconds.clockText)
                }

                Menu {
                    Button {
                        if let id = engine.hint() {
                            Haptics.place()
                            flash(id)
                        }
                    } label: { Label("Užuomina (−1★)", systemImage: "lightbulb") }
                    Button(role: .destructive) {
                        engine.resetAll()
                    } label: { Label("Viską į dėklą", systemImage: "arrow.uturn.backward") }
                } label: {
                    Image(systemName: "lightbulb.max")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Pagalba")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }

        // MARK: - Planas

        private func board(_ l: Layout) -> some View {
            let cells = Array(engine.blueprint.outline)
            let bp = engine.blueprint
            return ZStack(alignment: .topLeading) {
                CellsShape(cells: cells, cell: l.cell)
                    .fill(.white.opacity(0.05))
                InnerGridShape(cells: cells, cell: l.cell)
                    .stroke(.white.opacity(0.22), style: StrokeStyle(lineWidth: 0.7, dash: [3, 4]))
                EdgesShape(cells: cells, cell: l.cell)
                    .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .square))

                HStack {
                    Text(bp.number == "D" ? "DIENOS BUTAS" : "BUTAS NR. \(bp.number)")
                    Spacer()
                    Text("M 1:50")
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: CGFloat(bp.width) * l.cell)
                .offset(y: CGFloat(bp.height) * l.cell + 10)
            }
            .frame(width: CGFloat(bp.width) * l.cell, height: CGFloat(bp.height) * l.cell, alignment: .topLeading)
            .offset(x: l.board.minX, y: l.board.minY)
            .allowsHitTesting(false)
        }

        /// Žalias „šešėlis“, rodantis, kur detalė nusileis.
        @ViewBuilder
        private func ghost(_ l: Layout) -> some View {
            if let d = drag, d.moved,
               let piece = engine.pieces.first(where: { $0.id == d.id }),
               let target = dropTarget(piece, l),
               engine.canPlace(piece.shape, at: target, ignoring: piece.id) {
                CellsShape(cells: piece.shape, cell: l.cell)
                    .fill(Color.green.opacity(0.35))
                    .frame(width: CGFloat(Poly.size(piece.shape).w) * l.cell,
                           height: CGFloat(Poly.size(piece.shape).h) * l.cell,
                           alignment: .topLeading)
                    .offset(x: l.board.minX + CGFloat(target.x) * l.cell,
                            y: l.board.minY + CGFloat(target.y) * l.cell)
                    .allowsHitTesting(false)
            }
        }

        // MARK: - Detalės

        private func pieceView(_ piece: Piece, _ l: Layout) -> some View {
            let isDragged = drag?.id == piece.id
            let cell = isDragged || piece.origin != nil ? l.cell : l.trayCell
            let size = Poly.size(piece.shape)
            let w = CGFloat(size.w) * cell, h = CGFloat(size.h) * cell
            let topLeft = origin(of: piece, l)

            return PieceView(room: piece.room, shape: piece.shape, cell: cell,
                             placed: piece.origin != nil && !isDragged,
                             lifted: isDragged,
                             glowing: glowing == piece.id)
                .position(x: topLeft.x + w / 2, y: topLeft.y + h / 2)
                .zIndex(isDragged ? 100 : (piece.origin == nil ? 2 : 1))
                .gesture(dragGesture(piece, l))
                .allowsHitTesting(!engine.isSolved)
        }

        private func origin(of piece: Piece, _ l: Layout) -> CGPoint {
            if let d = drag, d.id == piece.id {
                let size = Poly.size(piece.shape)
                return CGPoint(x: d.location.x - d.grab.x * CGFloat(size.w) * l.cell,
                               y: d.location.y - d.grab.y * CGFloat(size.h) * l.cell)
            }
            if let o = piece.origin {
                return CGPoint(x: l.board.minX + CGFloat(o.x) * l.cell, y: l.board.minY + CGFloat(o.y) * l.cell)
            }
            return l.tray[piece.id] ?? .zero
        }

        private func dropTarget(_ piece: Piece, _ l: Layout) -> Cell? {
            let topLeft = origin(of: piece, l)
            let gx = ((topLeft.x - l.board.minX) / l.cell).rounded()
            let gy = ((topLeft.y - l.board.minY) / l.cell).rounded()
            guard gx.isFinite, gy.isFinite, abs(gx) < 100, abs(gy) < 100 else { return nil }
            return Cell(x: Int(gx), y: Int(gy))
        }

        private func dragGesture(_ piece: Piece, _ l: Layout) -> some Gesture {
            DragGesture(minimumDistance: 0, coordinateSpace: .named("game"))
                .onChanged { v in
                    if drag?.id != piece.id {
                        let cell = piece.origin != nil ? l.cell : l.trayCell
                        let size = Poly.size(piece.shape)
                        let o = origin(of: piece, l)
                        drag = DragState(
                            id: piece.id,
                            location: v.startLocation,
                            grab: CGPoint(x: (v.startLocation.x - o.x) / (CGFloat(size.w) * cell),
                                          y: (v.startLocation.y - o.y) / (CGFloat(size.h) * cell))
                        )
                    }
                    drag?.location = v.location
                    if hypot(v.translation.width, v.translation.height) > 8 { drag?.moved = true }
                }
                .onEnded { _ in
                    guard let d = drag, d.id == piece.id else { return }
                    if !d.moved {
                        drag = nil
                        Haptics.tap()
                        engine.rotate(piece.id)
                        return
                    }
                    let target = dropTarget(piece, l)
                    drag = nil
                    if let target, engine.place(piece.id, at: target) {
                        Haptics.place()
                    } else {
                        if l.board.insetBy(dx: -l.cell, dy: -l.cell).contains(d.location) { Haptics.error() }
                        engine.sendToTray(piece.id)
                    }
                }
        }

        // MARK: - Išdėstymas

        private func makeLayout(_ size: CGSize) -> Layout {
            let bp = engine.blueprint
            let cell = min((size.width - 40) / CGFloat(bp.width),
                           size.height * 0.5 / CGFloat(bp.height),
                           64).rounded(.down)
            let board = CGRect(x: ((size.width - cell * CGFloat(bp.width)) / 2).rounded(),
                               y: 12,
                               width: cell * CGFloat(bp.width),
                               height: cell * CGFloat(bp.height))
            let trayRect = CGRect(x: 16, y: board.maxY + 40,
                                  width: size.width - 32,
                                  height: max(60, size.height - board.maxY - 52))
            let (trayCell, tray) = layoutTray(engine.pieces.filter { $0.origin == nil },
                                              in: trayRect, fullCell: cell)
            return Layout(cell: cell, board: board, trayCell: trayCell, tray: tray)
        }

        /// Sudeda nepanaudotas detales eilutėmis; jei netelpa – mažina mastelį.
        private func layoutTray(_ pieces: [Piece], in rect: CGRect, fullCell: CGFloat) -> (CGFloat, [Int: CGPoint]) {
            var result: (CGFloat, [Int: CGPoint]) = (fullCell * 0.3, [:])
            for factor in stride(from: 0.7, through: 0.3, by: -0.05) {
                let tc = (fullCell * factor).rounded(.down)
                let gap = max(10, tc * 0.5)
                var rows: [[(Int, CGSize)]] = [[]]
                var rowWidth: CGFloat = 0
                for p in pieces {
                    let s = Poly.size(p.shape)
                    let sz = CGSize(width: CGFloat(s.w) * tc, height: CGFloat(s.h) * tc)
                    if !rows[rows.count - 1].isEmpty && rowWidth + gap + sz.width > rect.width {
                        rows.append([])
                        rowWidth = 0
                    }
                    rowWidth += (rows[rows.count - 1].isEmpty ? 0 : gap) + sz.width
                    rows[rows.count - 1].append((p.id, sz))
                }
                var positions: [Int: CGPoint] = [:]
                var y = rect.minY
                for row in rows where !row.isEmpty {
                    let width = row.map { $0.1.width }.reduce(0, +) + gap * CGFloat(row.count - 1)
                    let height = row.map { $0.1.height }.max() ?? 0
                    var x = rect.minX + (rect.width - width) / 2
                    for (id, sz) in row {
                        positions[id] = CGPoint(x: x, y: y + (height - sz.height) / 2)
                        x += sz.width + gap
                    }
                    y += height + gap
                }
                result = (tc, positions)
                if y - gap <= rect.maxY { break }
            }
            return result
        }

        // MARK: - Rezultatai

        private func flash(_ id: Int) {
            glowing = id
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation { glowing = nil }
            }
        }

        private func saveResult() {
            let s = PlanuMeistras.storage
            switch mode {
            case .level(let n):
                s.setIfHigher(n + 1, for: "unlocked")
                s.setIfHigher(engine.stars, for: "stars.\(n)")
            case .daily:
                s.setIfHigher(engine.stars, for: "daily.\(LevelGenerator.dayKey())")
            }
        }

        private func nextLevel() {
            guard case .level(let n) = mode else { dismiss(); return }
            drag = nil
            mode = .level(n + 1)
            engine = Engine(blueprint: mode.blueprint)
            withAnimation { showWin = false }
        }
    }
}
