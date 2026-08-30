import Foundation
import Testing
@testable import RaceFuelTimer

@Test("補給リマインドの設定を保存して読み込める")
func 補給リマインドの設定を保存して読み込める() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    let savedPlan = SavedPlan(
        selectedDistanceKilometers: 10,
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20, displayName: "そろそろ補給"),
        fuel: .init(isEnabled: false),
        notificationEndMinutes: 360
    )!

    // Act
    store.save(savedPlan)
    let restoredPlan = store.load()

    // Assert
    #expect(restoredPlan == savedPlan)
}

@Test("通知終了予定がない旧形式の保存設定は4時間後を初期値にする")
func 通知終了予定がない旧形式の保存設定は4時間後を初期値にする() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    defaults.set(
        Data(
            """
            {"version":1,"selectedDistanceKilometers":10,"hydration":{"isEnabled":true,"firstReminderMinutes":20,"repeatIntervalMinutes":20,"displayName":"補給の時間です"},"fuel":{"isEnabled":false,"firstReminderMinutes":null,"repeatIntervalMinutes":null,"displayName":""}}
            """.utf8
        ),
        forKey: ReminderPlanStore.storageKey
    )

    // Act
    let restoredPlan = store.load()

    // Assert
    #expect(restoredPlan?.notificationEndMinutes == 240)
}

@Test("旧ジェル通知だけの設定を補給リマインドへ引き継ぐ")
func 旧ジェル通知だけの設定を補給リマインドへ引き継ぐ() {
    // Arrange
    let savedPlan = SavedPlan(
        selectedDistanceKilometers: 10,
        hydration: .init(isEnabled: false),
        fuel: .init(isEnabled: true, firstReminderMinutes: 30, repeatIntervalMinutes: 30, displayName: "ジェルを補給")
    )!

    // Act
    let editablePlan = EditablePlan(savedPlan: savedPlan)

    // Assert
    #expect(editablePlan.isReminderEnabled)
    #expect(editablePlan.intervalMinutes == 30)
    #expect(editablePlan.notificationMessage == "ジェルを補給")
}

@Test("破損した保存設定は削除して初期設定へ復旧する")
func 破損した保存設定は削除して初期設定へ復旧する() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    defaults.set(Data("{not-json}".utf8), forKey: ReminderPlanStore.storageKey)

    // Act
    let loadResult = store.loadWithRecoveryStatus()

    // Assert
    #expect(loadResult.plan == nil)
    #expect(loadResult.didRecover)
    #expect(defaults.data(forKey: ReminderPlanStore.storageKey) == nil)
}

@Test("初期化すると保存設定を削除する")
func 初期化すると保存設定を削除する() {
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
    store.reset()

    // Assert
    #expect(store.load() == nil)
    #expect(defaults.data(forKey: ReminderPlanStore.storageKey) == nil)
}

private func makeTestDefaults() -> UserDefaults {
    let suiteName = "ReminderPlanStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
