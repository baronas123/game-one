import Foundation

/// Deterministinis atsitiktinių skaičių generatorius – tas pats lygis visada atrodo vienodai.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension SplitMix64 {
    /// Stabilus „sėklos“ skaičius iš datos – dienos iššūkiams (vienodas visiems žaidėjams).
    static func dailySeed(_ date: Date = .now, salt: UInt64 = 0) -> UInt64 {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        let key = (c.year ?? 2026) * 10_000 + (c.month ?? 1) * 100 + (c.day ?? 1)
        return UInt64(key) &* 2_654_435_761 &+ salt
    }
}
