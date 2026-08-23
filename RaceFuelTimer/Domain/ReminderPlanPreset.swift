import Foundation

enum PlannedDistance: String, CaseIterable, Identifiable {
    case fiveKilometers
    case tenKilometers
    case halfMarathon
    case fullMarathon
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveKilometers: "5 km"
        case .tenKilometers: "10 km"
        case .halfMarathon: "ハーフ"
        case .fullMarathon: "フル"
        case .custom: "カスタム"
        }
    }

    var kilometers: Double? {
        switch self {
        case .fiveKilometers: 5
        case .tenKilometers: 10
        case .halfMarathon: 21.0975
        case .fullMarathon: 42.195
        case .custom: nil
        }
    }

    static func from(savedDistanceKilometers: Double) -> PlannedDistance {
        allCases.first { $0.kilometers == savedDistanceKilometers } ?? .custom
    }
}

enum ReminderPlanPreset {
    static func make(for distanceKilometers: Double?) -> ReminderPlan {
        let fuelIsEnabled = (distanceKilometers ?? 0) >= 15

        return ReminderPlan(
            hydration: .init(
                isEnabled: true,
                firstReminderMinutes: nil,
                repeatIntervalMinutes: nil
            ),
            fuel: .init(
                isEnabled: fuelIsEnabled,
                firstReminderMinutes: nil,
                repeatIntervalMinutes: nil
            )
        )
    }
}
