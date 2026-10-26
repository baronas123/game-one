import Foundation

extension PlanuMeistras {

    /// Vienas kambarys (dėlionės detalė) su teisingu jo atsakymu.
    struct Room: Identifiable {
        let id: Int
        let code: String          // pvz. „45-3“
        let name: String          // pvz. „Svetainė“
        let solutionShape: [Cell]  // normalizuota figūra teisinga orientacija
        let solutionOrigin: Cell   // kur figūros (0,0) yra plane
        let hue: Double

        var area: Double { Double(solutionShape.count) * PlanuMeistras.cellArea }
    }

    /// Buto planas – lygio aprašas.
    struct Blueprint {
        let number: String        // „45“ arba „D“
        let title: String         // „Butas Nr. 45“
        let width: Int
        let height: Int
        let outline: Set<Cell>
        let rooms: [Room]
        let startRotations: [Int]  // kiek kartų pasukta kiekviena detalė pradžioje

        var totalArea: Double { Double(outline.count) * PlanuMeistras.cellArea }
    }

    enum LevelGenerator {

        static func level(_ n: Int) -> Blueprint {
            generate(number: "\(n)", title: "Butas Nr. \(n)", difficulty: n,
                     seed: 0xB0_7A_5_45 &+ UInt64(n) &* 7_919)
        }

        static func daily(_ date: Date = .now) -> Blueprint {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return generate(number: "D", title: "Dienos butas · \(f.string(from: date))",
                            difficulty: 9, seed: SplitMix64.dailySeed(date, salt: 45))
        }

        /// „20261026“ – dienos iššūkio rezultatų raktas.
        static func dayKey(_ date: Date = .now) -> String {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd"
            return f.string(from: date)
        }

        // MARK: - Generavimas

        static func generate(number: String, title: String, difficulty d: Int, seed: UInt64) -> Blueprint {
            var rng = SplitMix64(seed: seed)

            let w = min(4 + d / 3, 7)
            let h = min(5 + d / 3, 9)
            let maxPiece = min(4 + d / 4, 7)

            let outline = makeOutline(w: w, h: h, notches: min(d / 2, 3), rng: &rng)
            let regions = partition(outline, maxPiece: maxPiece, rng: &rng)

            // Didesni kambariai – svetainės/miegamieji, maži – vonia, WC ir t.t.
            let bigNames = ["Svetainė", "Miegamasis", "Virtuvė", "Vaikų kambarys", "Darbo kambarys",
                            "Valgomasis", "Svečių kambarys"]
            let smallNames = ["Vonia", "Koridorius", "WC", "Sandėliukas", "Prieškambaris", "Balkonas",
                              "Drabužinė", "Katilinė"]
            var bigIdx = 0, smallIdx = 0

            // Numeruojame kaip inventorizacijos byloje: nuo viršutinio kairiojo kampo.
            func topLeft(_ r: [Cell]) -> Cell { r.min { p, q in (p.y, p.x) < (q.y, q.x) }! }
            let ordered = regions.sorted { r1, r2 in
                let a = topLeft(r1), b = topLeft(r2)
                return (a.y, a.x) < (b.y, b.x)
            }
            let sizeRank = ordered.indices.sorted { ordered[$0].count > ordered[$1].count }
            var names = Array(repeating: "", count: ordered.count)
            for i in sizeRank {
                if ordered[i].count >= 4 && bigIdx < bigNames.count {
                    names[i] = bigNames[bigIdx]; bigIdx += 1
                } else {
                    names[i] = smallNames[smallIdx % smallNames.count]; smallIdx += 1
                }
            }

            var rooms: [Room] = []
            var rotations: [Int] = []
            for (i, cells) in ordered.enumerated() {
                let minX = cells.map(\.x).min()!, minY = cells.map(\.y).min()!
                rooms.append(Room(
                    id: i,
                    code: "\(number)-\(i + 1)",
                    name: names[i],
                    solutionShape: Poly.normalized(cells),
                    solutionOrigin: Cell(x: minX, y: minY),
                    hue: Double(i) / Double(ordered.count)
                ))
                rotations.append(Int.random(in: 0...3, using: &rng))
            }

            return Blueprint(number: number, title: title, width: w, height: h,
                             outline: outline, rooms: rooms, startRotations: rotations)
        }

        /// Stačiakampis su „įlenkimais“ kampuose (laiptinė, balkonas, šachta...).
        private static func makeOutline(w: Int, h: Int, notches: Int, rng: inout SplitMix64) -> Set<Cell> {
            var cells = Set((0..<w).flatMap { x in (0..<h).map { y in Cell(x: x, y: y) } })
            let corners = [(0, 0), (1, 0), (0, 1), (1, 1)].shuffled(using: &rng)
            for (cx, cy) in corners.prefix(notches) {
                let nw = Int.random(in: 1...max(1, (w - 1) / 2), using: &rng)
                let nh = Int.random(in: 1...max(1, h / 3), using: &rng)
                for dx in 0..<nw {
                    for dy in 0..<nh {
                        let x = cx == 0 ? dx : w - 1 - dx
                        let y = cy == 0 ? dy : h - 1 - dy
                        cells.remove(Cell(x: x, y: y))
                    }
                }
            }
            return cells
        }

        /// Suskaido kontūrą į kambarius (polimino figūras). Kadangi skaidome patį
        /// kontūrą, kiekvienas lygis garantuotai išsprendžiamas.
        private static func partition(_ outline: Set<Cell>, maxPiece: Int, rng: inout SplitMix64) -> [[Cell]] {
            var owner: [Cell: Int] = [:]
            var regions: [[Cell]] = []

            func freeNeighbours(_ c: Cell) -> [Cell] {
                c.neighbours.filter { outline.contains($0) && owner[$0] == nil }
            }

            // Pradedame nuo „labiausiai įspraustų“ laisvų langelių – mažiau vienišų likučių.
            let order = outline.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            while true {
                let free = order.filter { owner[$0] == nil }
                guard !free.isEmpty else { break }
                let minDeg = free.map { freeNeighbours($0).count }.min()!
                let candidates = free.filter { freeNeighbours($0).count == minDeg }
                let start = candidates.randomElement(using: &rng)!

                let target = Int.random(in: 2...maxPiece, using: &rng)
                let id = regions.count
                var region = [start]
                owner[start] = id
                while region.count < target {
                    let frontier = Array(Set(region.flatMap(freeNeighbours)))
                        .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
                    guard let next = frontier.randomElement(using: &rng) else { break }
                    region.append(next)
                    owner[next] = id
                }
                regions.append(region)
            }

            // Vieno langelio „kambarius“ prijungiame prie mažiausio kaimyno.
            var changed = true
            while changed {
                changed = false
                for (i, region) in regions.enumerated() where region.count == 1 {
                    let neighbourIDs = Set(region[0].neighbours.compactMap { owner[$0] }).subtracting([i])
                    guard let target = neighbourIDs.min(by: { regions[$0].count < regions[$1].count }) else { continue }
                    regions[target].append(region[0])
                    owner[region[0]] = target
                    regions[i] = []
                    changed = true
                    break
                }
                if changed {
                    regions = regions.filter { !$0.isEmpty }
                    owner = [:]
                    for (i, r) in regions.enumerated() { for c in r { owner[c] = i } }
                }
            }
            return regions
        }
    }
}
