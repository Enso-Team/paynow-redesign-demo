import Foundation

/// Which dependency chain Scan & Pay runs from the entry screen.
enum FlowMode: String, CaseIterable, Sendable {
    case sequential, router

    var title: String {
        switch self {
        case .sequential: "DBS Sequential"
        case .router: "Intent Router"
        }
    }
}

/// The A/B control bar's two switches, kept in UserDefaults.
enum ABSettings {
    static let flowKey = "ab.flow"
    static let multiplierKey = "ab.multiplier"
    static let multipliers = [1, 3]

    static var flow: FlowMode {
        UserDefaults.standard.string(forKey: flowKey).flatMap(FlowMode.init) ?? .router
    }

    static var multiplier: Int {
        let stored = UserDefaults.standard.integer(forKey: multiplierKey)
        return multipliers.contains(stored) ? stored : 1
    }
}
