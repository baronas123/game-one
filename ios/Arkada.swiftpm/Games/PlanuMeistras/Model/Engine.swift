import Foundation
import Observation

extension PlanuMeistras {

    /// Viena detalė žaidimo metu.
    struct Piece: Identifiable {
        let room: Room
        var shape: [Cell]
        /// Kur detalė padėta plane; `nil` – guli dėklo zonoje.
        var origin: Cell?

        var id: Int { room.id }

        var boardCells: Set<Cell> {
            guard let origin else { return [] }
            return Set(shape.map { $0 + origin })
        }

        var isCorrect: Bool {
            boardCells == Set(room.solutionShape.map { $0 + room.solutionOrigin })
        }
    }

    /// Žaidimo logika – be jokio UI, kad būtų lengva testuoti.
    @Observable
    final class Engine {
        let blueprint: Blueprint
        private(set) var pieces: [Piece]
        private(set) var moves = 0
        private(set) var hintsUsed = 0
        private(set) var startDate = Date()
        private(set) var finishedAt: Date?
        /// Didėja po kiekvieno pakeitimo – naudojama animacijoms.
        private(set) var revision = 0

        var isSolved: Bool { finishedAt != nil }
        var placedCount: Int { pieces.filter { $0.origin != nil }.count }

        init(blueprint: Blueprint) {
            self.blueprint = blueprint
            self.pieces = zip(blueprint.rooms, blueprint.startRotations).map { room, turns in
                var shape = room.solutionShape
                for _ in 0..<turns { shape = Poly.rotated(shape) }
                return Piece(room: room, shape: shape, origin: nil)
            }
        }

        var elapsedSeconds: Int {
            Int((finishedAt ?? Date()).timeIntervalSince(startDate))
        }

        /// 3★ – be užuominų ir greitai; kiekviena užuomina ar lėtumas nuima po žvaigždutę.
        var stars: Int {
            var s = 3
            if hintsUsed >= 1 { s -= 1 }
            if hintsUsed >= 2 { s -= 1 }
            if elapsedSeconds > pieces.count * 20 { s -= 1 }
            return max(1, s)
        }

        // MARK: - Taisyklės

        func canPlace(_ shape: [Cell], at origin: Cell, ignoring id: Int) -> Bool {
            var taken = Set<Cell>()
            for p in pieces where p.id != id { taken.formUnion(p.boardCells) }
            return shape.allSatisfy {
                let c = $0 + origin
                return blueprint.outline.contains(c) && !taken.contains(c)
            }
        }

        // MARK: - Veiksmai

        @discardableResult
        func place(_ id: Int, at origin: Cell) -> Bool {
            guard !isSolved, let i = index(id), canPlace(pieces[i].shape, at: origin, ignoring: id) else { return false }
            pieces[i].origin = origin
            moves += 1
            changed()
            return true
        }

        func sendToTray(_ id: Int) {
            guard !isSolved, let i = index(id) else { return }
            pieces[i].origin = nil
            changed()
        }

        /// Pasuka detalę. Jei ji plane ir po pasukimo netelpa – bandome šalia, kitaip grąžiname į dėklą.
        func rotate(_ id: Int) {
            guard !isSolved, let i = index(id) else { return }
            let shape = Poly.rotated(pieces[i].shape)
            pieces[i].shape = shape
            if let o = pieces[i].origin {
                let tries = [Cell(x: 0, y: 0), Cell(x: -1, y: 0), Cell(x: 0, y: -1), Cell(x: 1, y: 0),
                             Cell(x: 0, y: 1), Cell(x: -1, y: -1)]
                pieces[i].origin = tries.map { o + $0 }.first { canPlace(shape, at: $0, ignoring: id) }
            }
            moves += 1
            changed()
        }

        func resetAll() {
            guard !isSolved else { return }
            for i in pieces.indices { pieces[i].origin = nil }
            changed()
        }

        /// Padeda vieną detalę į teisingą vietą (ir nustumia trukdančias į dėklą).
        @discardableResult
        func hint() -> Int? {
            guard !isSolved,
                  let i = pieces.firstIndex(where: { $0.origin == nil }) ?? pieces.firstIndex(where: { !$0.isCorrect })
            else { return nil }
            let room = pieces[i].room
            let target = Set(room.solutionShape.map { $0 + room.solutionOrigin })
            for j in pieces.indices where j != i && !pieces[j].boardCells.isDisjoint(with: target) {
                pieces[j].origin = nil
            }
            pieces[i].shape = room.solutionShape
            pieces[i].origin = room.solutionOrigin
            hintsUsed += 1
            changed()
            return room.id
        }

        // MARK: -

        private func index(_ id: Int) -> Int? { pieces.firstIndex { $0.id == id } }

        private func changed() {
            revision += 1
            // Visos detalės plane ir niekas nepersidengia → plotai sutampa → butas pilnas.
            if pieces.allSatisfy({ $0.origin != nil }) && finishedAt == nil {
                finishedAt = Date()
            }
        }
    }
}
