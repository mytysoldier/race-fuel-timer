import Foundation
import Testing
@testable import RaceFuelTimer

@Test("有効な設定を保存して読み込める")
func 有効な設定を保存して読み込める() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    let savedPlan = SavedPlan(
        selectedDistanceKilometers: 21.0975,
        hydration: .init(isEnabled: true, firstReminderMinutes: 25, repeatIntervalMinutes: 30, displayName: "水分"),
        fuel: .init(isEnabled: true, firstReminderMinutes: 45, repeatIntervalMinutes: 45, displayName: "ジェル")
    )!

    // Act
    store.save(savedPlan)
    let restoredPlan = store.load()

    // Assert
    #expect(restoredPlan == savedPlan)
}

@Test("破損したJSONは初期設定へフォールバックして削除する")
func 破損したJSONは初期設定へフォールバックして削除する() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    defaults.set(Data("{not-json}".utf8), forKey: ReminderPlanStore.storageKey)

    // Act
    let restoredPlan = store.load()

    // Assert
    #expect(restoredPlan == .default)
    #expect(defaults.data(forKey: ReminderPlanStore.storageKey) == nil)
}

@Test("範囲外の保存設定は初期設定へフォールバックする")
func 範囲外の保存設定は初期設定へフォールバックする() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    defaults.set(
        Data(
            """
            {"version":1,"selectedDistanceKilometers":10,"hydration":{"isEnabled":true,"firstReminderMinutes":4,"repeatIntervalMinutes":20,"displayName":""},"fuel":{"isEnabled":false,"firstReminderMinutes":null,"repeatIntervalMinutes":null,"displayName":""}}
            """.utf8
        ),
        forKey: ReminderPlanStore.storageKey
    )

    // Act
    let restoredPlan = store.load()

    // Assert
    #expect(restoredPlan == .default)
}

@Test("無効な通知に残った範囲外の保存設定は初期設定へフォールバックする")
func 無効な通知に残った範囲外の保存設定は初期設定へフォールバックする() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    defaults.set(
        Data(
            """
            {"version":1,"selectedDistanceKilometers":10,"hydration":{"isEnabled":true,"firstReminderMinutes":20,"repeatIntervalMinutes":20,"displayName":""},"fuel":{"isEnabled":false,"firstReminderMinutes":0,"repeatIntervalMinutes":999,"displayName":""}}
            """.utf8
        ),
        forKey: ReminderPlanStore.storageKey
    )

    // Act
    let restoredPlan = store.load()

    // Assert
    #expect(restoredPlan == .default)
}

@Test("旧バージョンの保存設定は初期設定へフォールバックする")
func 旧バージョンの保存設定は初期設定へフォールバックする() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    defaults.set(
        Data(
            """
            {"version":0,"selectedDistanceKilometers":10,"hydration":{"isEnabled":true,"firstReminderMinutes":20,"repeatIntervalMinutes":20,"displayName":""},"fuel":{"isEnabled":false,"firstReminderMinutes":null,"repeatIntervalMinutes":null,"displayName":""}}
            """.utf8
        ),
        forKey: ReminderPlanStore.storageKey
    )

    // Act
    let restoredPlan = store.load()

    // Assert
    #expect(restoredPlan == .default)
}

@Test("初期化すると保存設定を削除して初期設定を返す")
func 初期化すると保存設定を削除して初期設定を返す() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    let savedPlan = SavedPlan(
        selectedDistanceKilometers: 5,
        hydration: .init(isEnabled: true, firstReminderMinutes: 30, repeatIntervalMinutes: 30),
        fuel: .init(isEnabled: false)
    )!
    store.save(savedPlan)

    // Act
    store.reset()
    let restoredPlan = store.load()

    // Assert
    #expect(restoredPlan == .default)
    #expect(defaults.data(forKey: ReminderPlanStore.storageKey) == nil)
}

private func makeTestDefaults() -> UserDefaults {
    let suiteName = "ReminderPlanStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
