import Foundation

struct SavedPlan: Equatable {
    static let currentVersion = 1

    let version: Int
    let selectedDistanceKilometers: Double
    let hydration: ReminderSetting
    let fuel: ReminderSetting
    let notificationEndMinutes: Int

    init?(
        version: Int = Self.currentVersion,
        selectedDistanceKilometers: Double,
        hydration: ReminderSetting,
        fuel: ReminderSetting,
        notificationEndMinutes: Int = 240
    ) {
        guard version == Self.currentVersion,
              selectedDistanceKilometers.isFinite,
              (0.1...200).contains(selectedDistanceKilometers),
              Self.isValidStoredSetting(hydration),
              Self.isValidStoredSetting(fuel),
              ReminderPlan(
                  hydration: hydration,
                  fuel: fuel,
                  notificationEndMinutes: notificationEndMinutes
              ).validationErrors().isEmpty
        else {
            return nil
        }

        self.version = version
        self.selectedDistanceKilometers = selectedDistanceKilometers
        self.hydration = hydration
        self.fuel = fuel
        self.notificationEndMinutes = notificationEndMinutes
    }

    private static func isValidStoredSetting(_ setting: ReminderSetting) -> Bool {
        let hasValidFirstReminder = setting.firstReminderMinutes.map(ReminderPlan.allowedReminderMinutes.contains) ?? true
        let hasValidRepeatInterval = setting.repeatIntervalMinutes.map(ReminderPlan.allowedReminderMinutes.contains) ?? true
        let displayNameLength = setting.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .count

        return hasValidFirstReminder && hasValidRepeatInterval && displayNameLength <= 30
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

    func load() -> SavedPlan? {
        loadWithRecoveryStatus().plan
    }

    func loadWithRecoveryStatus() -> SavedPlanLoadResult {
        guard let storedValue = defaults.object(forKey: storageKey) else {
            return .init(plan: nil, didRecover: false)
        }

        guard let data = storedValue as? Data,
              let payload = try? JSONDecoder().decode(SavedPlanPayload.self, from: data),
              let savedPlan = payload.savedPlan
        else {
            defaults.removeObject(forKey: storageKey)
            return .init(plan: nil, didRecover: true)
        }

        return .init(plan: savedPlan, didRecover: false)
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

struct SavedPlanLoadResult: Equatable {
    let plan: SavedPlan?
    let didRecover: Bool
}

private struct SavedPlanPayload: Codable {
    let version: Int
    let selectedDistanceKilometers: Double
    let hydration: ReminderSettingPayload
    let fuel: ReminderSettingPayload
    let notificationEndMinutes: Int?

    init(savedPlan: SavedPlan) {
        version = savedPlan.version
        selectedDistanceKilometers = savedPlan.selectedDistanceKilometers
        hydration = .init(setting: savedPlan.hydration)
        fuel = .init(setting: savedPlan.fuel)
        notificationEndMinutes = savedPlan.notificationEndMinutes
    }

    var savedPlan: SavedPlan? {
        // 新しい形式を追加する際は、ここで既知の旧バージョンを明示的に変換する。
        SavedPlan(
            version: version,
            selectedDistanceKilometers: selectedDistanceKilometers,
            hydration: hydration.reminderSetting,
            fuel: fuel.reminderSetting,
            notificationEndMinutes: notificationEndMinutes ?? 240
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
