import Foundation

struct SavedPlan: Equatable {
    static let currentVersion = 1

    let version: Int
    let selectedDistanceKilometers: Double
    let hydration: ReminderSetting
    let fuel: ReminderSetting

    static let `default` = SavedPlan(
        version: currentVersion,
        selectedDistanceKilometers: 10,
        hydration: ReminderPlanPreset.make(for: 10).hydration,
        fuel: ReminderPlanPreset.make(for: 10).fuel
    )!

    init?(
        version: Int = Self.currentVersion,
        selectedDistanceKilometers: Double,
        hydration: ReminderSetting,
        fuel: ReminderSetting
    ) {
        guard version == Self.currentVersion,
              selectedDistanceKilometers.isFinite,
              (0.1...200).contains(selectedDistanceKilometers),
              ReminderPlan(hydration: hydration, fuel: fuel).validationErrors().isEmpty
        else {
            return nil
        }

        self.version = version
        self.selectedDistanceKilometers = selectedDistanceKilometers
        self.hydration = hydration
        self.fuel = fuel
    }
}

struct ReminderPlanStore {
    static let storageKey = "savedReminderPlan"

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = Self.storageKey) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() -> SavedPlan {
        guard let data = defaults.data(forKey: storageKey),
              let payload = try? JSONDecoder().decode(SavedPlanPayload.self, from: data),
              let savedPlan = payload.savedPlan
        else {
            defaults.removeObject(forKey: storageKey)
            return .default
        }

        return savedPlan
    }

    func save(_ savedPlan: SavedPlan) {
        guard let data = try? JSONEncoder().encode(SavedPlanPayload(savedPlan: savedPlan)) else {
            return
        }

        defaults.set(data, forKey: storageKey)
    }

    func reset() {
        defaults.removeObject(forKey: storageKey)
    }
}

private struct SavedPlanPayload: Codable {
    let version: Int
    let selectedDistanceKilometers: Double
    let hydration: ReminderSettingPayload
    let fuel: ReminderSettingPayload

    init(savedPlan: SavedPlan) {
        version = savedPlan.version
        selectedDistanceKilometers = savedPlan.selectedDistanceKilometers
        hydration = .init(setting: savedPlan.hydration)
        fuel = .init(setting: savedPlan.fuel)
    }

    var savedPlan: SavedPlan? {
        // 新しい形式を追加する際は、ここで既知の旧バージョンを明示的に変換する。
        SavedPlan(
            version: version,
            selectedDistanceKilometers: selectedDistanceKilometers,
            hydration: hydration.reminderSetting,
            fuel: fuel.reminderSetting
        )
    }
}

private struct ReminderSettingPayload: Codable {
    let isEnabled: Bool
    let firstReminderMinutes: Int?
    let repeatIntervalMinutes: Int?
    let displayName: String

    init(setting: ReminderSetting) {
        isEnabled = setting.isEnabled
        firstReminderMinutes = setting.firstReminderMinutes
        repeatIntervalMinutes = setting.repeatIntervalMinutes
        displayName = setting.displayName
    }

    var reminderSetting: ReminderSetting {
        ReminderSetting(
            isEnabled: isEnabled,
            firstReminderMinutes: firstReminderMinutes,
            repeatIntervalMinutes: repeatIntervalMinutes,
            displayName: displayName
        )
    }
}
