import Foundation

extension NaktinisGreitkelis {

    enum SpriteKind {
        case lamp, pine, billboard, can
    }

    /// Objektas šalia kelio arba ant jo. `offset` – kelio puspločio dalimis (-1…1 = kelias).
    struct RoadSprite {
        var kind: SpriteKind
        var offset: Double
        var scale: Double = 1
        var text: String = ""
    }

    /// Vienas kelio segmentas („OutRun“ tipo pseudo-3D projekcijai).
    struct Segment {
        let index: Int
        let curve: Double
        let y1: Double
        let y2: Double
        var sprites: [RoadSprite] = []
    }

    /// Visas kelio žiedas: posūkiai, kalvos ir dekoracijos. Generuojamas iš sėklos,
    /// todėl kelias kaskart toks pat – posūkius galima išmokti.
    struct Road {
        static let segmentLength: Double = 200
        static let halfWidth: Double = 2000
        static let lanes = 3
        static let laneOffsets: [Double] = [-0.66, 0, 0.66]

        private(set) var segments: [Segment] = []

        var length: Double { Double(segments.count) * Road.segmentLength }

        init() {
            build()
        }

        func index(at z: Double) -> Int {
            let i = Int(floor(z / Road.segmentLength)) % segments.count
            return i < 0 ? i + segments.count : i
        }

        func segment(at z: Double) -> Segment { segments[index(at: z)] }

        // MARK: - Generavimas

        private var lastY: Double { segments.last?.y2 ?? 0 }

        private mutating func addSegment(curve: Double, y: Double) {
            segments.append(Segment(index: segments.count, curve: curve, y1: lastY, y2: y))
        }

        private static func easeIn(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p * p }
        private static func easeInOut(_ a: Double, _ b: Double, _ p: Double) -> Double {
            a + (b - a) * ((-cos(p * .pi) / 2) + 0.5)
        }

        private mutating func addRoad(enter: Int, hold: Int, leave: Int, curve: Double, hill: Double) {
            let startY = lastY
            let endY = startY + hill * Road.segmentLength
            let total = Double(enter + hold + leave)
            for n in 0..<enter {
                addSegment(curve: Road.easeIn(0, curve, Double(n) / Double(enter)),
                           y: Road.easeInOut(startY, endY, Double(n) / total))
            }
            for n in 0..<hold {
                addSegment(curve: curve, y: Road.easeInOut(startY, endY, Double(enter + n) / total))
            }
            for n in 0..<leave {
                addSegment(curve: Road.easeInOut(curve, 0, Double(n) / Double(leave)),
                           y: Road.easeInOut(startY, endY, Double(enter + hold + n) / total))
            }
        }

        private mutating func build() {
            var rng = SplitMix64(seed: 0xA1A1)
            func r() -> Double { Double.random(in: 0..<1, using: &rng) }

            addRoad(enter: 40, hold: 60, leave: 40, curve: 0, hill: 0)
            while segments.count < 3200 {
                let len = [25, 50, 75][Int(r() * 3)]
                let curve: Double = r() < 0.25 ? 0 : (r() < 0.5 ? -1.0 : 1.0) * [2.0, 3.0, 4.0, 6.0][Int(r() * 4)]
                let hill: Double = r() < 0.4 ? 0 : (r() < 0.5 ? -1.0 : 1.0) * [10.0, 20.0, 40.0][Int(r() * 3)]
                let current = lastY / Road.segmentLength
                let clamped = max(-60, min(60, current + hill)) - current
                addRoad(enter: len, hold: len, leave: len, curve: curve, hill: clamped)
            }
            addRoad(enter: 50, hold: 50, leave: 50, curve: 0, hill: -lastY / Road.segmentLength)

            // Dekoracijos
            for i in stride(from: 20, to: segments.count, by: 12) {
                segments[i].sprites.append(RoadSprite(kind: .lamp, offset: -1.25))
                segments[i].sprites.append(RoadSprite(kind: .lamp, offset: 1.25))
            }
            for i in stride(from: 10, to: segments.count, by: 3) {
                let side: Double = r() < 0.5 ? -1 : 1
                segments[i].sprites.append(RoadSprite(kind: .pine, offset: side * (1.7 + r() * 2.8), scale: 0.7 + r() * 0.7))
                if r() < 0.5 {
                    segments[i].sprites.append(RoadSprite(kind: .pine, offset: -side * (2.0 + r() * 3), scale: 0.7 + r() * 0.7))
                }
            }
            let ads = ["ARKADA", "KAVA 24/7", "NITRO", "CEPELINAI"]
            var i = 300
            while i < segments.count {
                let side: Double = r() < 0.5 ? -1 : 1
                segments[i].sprites.append(RoadSprite(kind: .billboard, offset: side * 2.1, text: ads[Int(r() * 4)]))
                i += 420 + Int(r() * 200)
            }
            i = 120
            while i < segments.count {
                segments[i].sprites.append(RoadSprite(kind: .can, offset: Road.laneOffsets[Int(r() * 3)]))
                i += 70 + Int(r() * 60)
            }
        }
    }
}
