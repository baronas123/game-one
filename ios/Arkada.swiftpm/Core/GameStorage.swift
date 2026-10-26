import Foundation

/// Paprasta, pagal žaidimą atskirta saugykla (UserDefaults).
///
/// Raktai gaunasi „<žaidimo-id>.<raktas>“, todėl žaidimai niekada nesupainioja
/// vienas kito rekordų. SwiftUI vaizduose galima naudoti ir
/// `@AppStorage(GameStorage.key("planu-meistras", "level"))`.
struct GameStorage {
    let gameID: String

    static func key(_ gameID: String, _ name: String) -> String { "\(gameID).\(name)" }

    private func k(_ name: String) -> String { Self.key(gameID, name) }
    private var defaults: UserDefaults { .standard }

    func int(_ name: String, default value: Int = 0) -> Int {
        defaults.object(forKey: k(name)) as? Int ?? value
    }

    func set(_ value: Int, for name: String) { defaults.set(value, forKey: k(name)) }

    func bool(_ name: String) -> Bool { defaults.bool(forKey: k(name)) }

    func set(_ value: Bool, for name: String) { defaults.set(value, forKey: k(name)) }

    /// Įrašo reikšmę tik jei ji geresnė (didesnė) už esamą. Grąžina true, jei tai naujas rekordas.
    @discardableResult
    func setIfHigher(_ value: Int, for name: String) -> Bool {
        guard value > int(name, default: .min) else { return false }
        set(value, for: name)
        return true
    }

    /// Įrašo reikšmę tik jei ji geresnė (mažesnė) – pvz. laikas sekundėmis.
    @discardableResult
    func setIfLower(_ value: Int, for name: String) -> Bool {
        guard value < int(name, default: .max) else { return false }
        set(value, for: name)
        return true
    }

    /// Ištrina visus šio žaidimo duomenis.
    func reset() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(gameID + ".") {
            defaults.removeObject(forKey: key)
        }
    }
}
