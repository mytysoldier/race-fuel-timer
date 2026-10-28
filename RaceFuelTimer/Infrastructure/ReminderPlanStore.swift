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
            hydration: hydration.reminderSetting(normalizingLegacyInterval: notificationEndMinutes == nil),
            fuel: fuel.reminderSetting(normalizingLegacyInterval: notificationEndMinutes == nil),
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

    func reminderSetting(normalizingLegacyInterval: Bool) -> ReminderSetting {
        ReminderSetting(
            isEnabled: isEnabled,
            firstReminderMinutes: normalizedMinutes(firstReminderMinutes, normalizingLegacyInterval: normalizingLegacyInterval),
            repeatIntervalMinutes: normalizedMinutes(repeatIntervalMinutes, normalizingLegacyInterval: normalizingLegacyInterval),
            displayName: displayName
        )
    }

    private func normalizedMinutes(_ minutes: Int?, normalizingLegacyInterval: Bool) -> Int? {
        guard normalizingLegacyInterval,
              let minutes,
              (5...ReminderPlan.allowedReminderMinutes.upperBound).contains(minutes)
        else {
            return minutes
        }

        let increment = ReminderPlan.allowedReminderMinutes.lowerBound
        return min(((minutes + increment - 1) / increment) * increment, ReminderPlan.allowedReminderMinutes.upperBound)
    }
}


struct SessionHistoryStore {
    private struct Archive: Codable {
        let version: Int
        var entries: [SessionHistoryEntry]
    }

    enum StoreError: Error { case unsupportedVersion }
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("session-history.json")
    }

    func load() throws -> [SessionHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
        guard archive.version == 1 else { throw StoreError.unsupportedVersion }
        return archive.entries.sorted { $0.startedAt > $1.startedAt }
    }

    func save(_ entry: SessionHistoryEntry) throws {
        var entries = try load()
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        entries.append(entry)
        try write(entries)
    }

    func delete(id: UUID) throws {
        var entries = try load()
        entries.removeAll { $0.id == id }
        try write(entries)
    }

    private func write(_ entries: [SessionHistoryEntry]) throws {
        let data = try JSONEncoder().encode(Archive(version: 1, entries: entries))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
