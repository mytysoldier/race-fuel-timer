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

@Test("破損したJSONからの復旧を画面へ通知できる")
func 破損したJSONからの復旧を画面へ通知できる() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    defaults.set(Data("{not-json}".utf8), forKey: ReminderPlanStore.storageKey)

    // Act
    let loadResult = store.loadWithRecoveryStatus()

    // Assert
    #expect(loadResult.plan == .default)
    #expect(loadResult.didRecover)
}

@Test("Data以外の保存値からの復旧を画面へ通知できる")
func Data以外の保存値からの復旧を画面へ通知できる() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    defaults.set("legacy-format", forKey: ReminderPlanStore.storageKey)

    // Act
    let loadResult = store.loadWithRecoveryStatus()

    // Assert
    #expect(loadResult.plan == .default)
    #expect(loadResult.didRecover)
    #expect(defaults.object(forKey: ReminderPlanStore.storageKey) == nil)
}

@Test("保存設定がない初回起動では復旧案内を表示しない")
func 保存設定がない初回起動では復旧案内を表示しない() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)

    // Act
    let loadResult = store.loadWithRecoveryStatus()

    // Assert
    #expect(loadResult.plan == .default)
    #expect(!loadResult.didRecover)
    #expect(!loadResult.didLoadSavedPlan)
}

@Test("初回起動時の通知時刻と間隔は未入力にする")
func 初回起動時の通知時刻と間隔は未入力にする() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)

    // Act
    let restoredPlan = store.load()

    // Assert
    #expect(restoredPlan.hydration.firstReminderMinutes == nil)
    #expect(restoredPlan.hydration.repeatIntervalMinutes == nil)
    #expect(restoredPlan.fuel.firstReminderMinutes == nil)
    #expect(restoredPlan.fuel.repeatIntervalMinutes == nil)
}

@Test("保存した設定がある場合は保存値を読み込む")
func 保存した設定がある場合は保存値を読み込む() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    let savedPlan = SavedPlan(
        selectedDistanceKilometers: 10,
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: false)
    )!
    store.save(savedPlan)

    // Act
    let loadResult = store.loadWithRecoveryStatus()

    // Assert
    #expect(loadResult.plan == savedPlan)
    #expect(loadResult.didLoadSavedPlan)
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

@Test("通知を無効にすると入力済みの値を初期化する")
func 通知を無効にすると入力済みの値を初期化する() {
    // Arrange
    var editablePlan = EditablePlan(savedPlan: .default)
    editablePlan.fuelIsEnabled = false
    editablePlan.fuelFirstReminder = "0"
    editablePlan.fuelRepeatInterval = "999"
    editablePlan.fuelDisplayName = "長い表示名"

    // Act
    editablePlan.clearFuelReminderInputs()

    // Assert
    #expect(editablePlan.fuelFirstReminder.isEmpty)
    #expect(editablePlan.fuelRepeatInterval.isEmpty)
    #expect(editablePlan.fuelDisplayName.isEmpty)
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

@Test("対応していない保存バージョンは削除して初期設定へ復旧する")
func 対応していない保存バージョンは削除して初期設定へ復旧する() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    defaults.set(
        Data(
            """
            {"version":2,"selectedDistanceKilometers":10,"hydration":{"isEnabled":true,"firstReminderMinutes":20,"repeatIntervalMinutes":20,"displayName":""},"fuel":{"isEnabled":false,"firstReminderMinutes":null,"repeatIntervalMinutes":null,"displayName":""}}
            """.utf8
        ),
        forKey: ReminderPlanStore.storageKey
    )

    // Act
    let loadResult = store.loadWithRecoveryStatus()

    // Assert
    #expect(loadResult.plan == .default)
    #expect(loadResult.didRecover)
    #expect(defaults.object(forKey: ReminderPlanStore.storageKey) == nil)
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
