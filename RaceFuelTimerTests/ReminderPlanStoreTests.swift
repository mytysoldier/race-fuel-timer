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

@Test("旧形式の5分通知は10分へ引き上げて引き継ぐ")
func 旧形式の五分通知は十分へ引き上げて引き継ぐ() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    defaults.set(
        Data(
            """
            {"version":1,"selectedDistanceKilometers":10,"hydration":{"isEnabled":true,"firstReminderMinutes":5,"repeatIntervalMinutes":5,"displayName":"補給の時間です"},"fuel":{"isEnabled":false,"firstReminderMinutes":null,"repeatIntervalMinutes":null,"displayName":""}}
            """.utf8
        ),
        forKey: ReminderPlanStore.storageKey
    )

    // Act
    let restoredPlan = store.load()

    // Assert
    #expect(restoredPlan?.hydration.firstReminderMinutes == 10)
    #expect(restoredPlan?.hydration.repeatIntervalMinutes == 10)
}

@Test("旧形式の任意の通知間隔は次の10分単位へ引き上げて引き継ぐ")
func 旧形式の任意の通知間隔は次の十分単位へ引き上げて引き継ぐ() {
    // Arrange
    let defaults = makeTestDefaults()
    let store = ReminderPlanStore(defaults: defaults)
    defaults.set(
        Data(
            """
            {"version":1,"selectedDistanceKilometers":10,"hydration":{"isEnabled":true,"firstReminderMinutes":15,"repeatIntervalMinutes":235,"displayName":"補給の時間です"},"fuel":{"isEnabled":false,"firstReminderMinutes":null,"repeatIntervalMinutes":null,"displayName":""}}
            """.utf8
        ),
        forKey: ReminderPlanStore.storageKey
    )

    // Act
    let restoredPlan = store.load()

    // Assert
    #expect(restoredPlan?.hydration.firstReminderMinutes == 20)
    #expect(restoredPlan?.hydration.repeatIntervalMinutes == 240)
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

@Test("通知をオフにした設定でも間隔とメッセージを引き継ぐ")
func 通知をオフにした設定でも間隔とメッセージを引き継ぐ() {
    // Arrange
    let savedPlan = SavedPlan(
        selectedDistanceKilometers: 10,
        hydration: .init(isEnabled: false, firstReminderMinutes: 30, repeatIntervalMinutes: 30, displayName: "補給を忘れずに"),
        fuel: .init(isEnabled: false)
    )!

    // Act
    let editablePlan = EditablePlan(savedPlan: savedPlan)

    // Assert
    #expect(!editablePlan.isReminderEnabled)
    #expect(editablePlan.intervalMinutes == 30)
    #expect(editablePlan.notificationMessage == "補給を忘れずに")
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

@Test("終了したセッションの履歴は再読込でき重複保存されず個別に削除できる")
func 終了したセッションの履歴は再読込でき重複保存されず個別に削除できる() throws {
    // Arrange
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.json")
    let store = SessionHistoryStore(fileURL: url)
    let start = Date(timeIntervalSince1970: 1000)
    var session = try Session(plan: ReminderPlan(hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20), fuel: .init(isEnabled: false)), startedAt: start)
    let target = try #require(session.recordingTarget(at: start))
    let recorded = session.record(.taken, reminderID: target.identifier, at: start)
    #expect(recorded)
    session.end(at: start.addingTimeInterval(60))
    let entry = try #require(SessionHistoryEntry(session: session))

    // Act
    try store.save(entry)
    try store.save(entry)
    let restored = try SessionHistoryStore(fileURL: url).load()
    try store.delete(id: entry.id)

    // Assert
    #expect(restored == [entry])
    #expect(restored.first?.summary.earlyRecordCount == 1)
    #expect(restored.first?.summary.unrecordedCount == 0)
    #expect(try store.load().isEmpty)
}

@Test("破損または未知バージョンの履歴は保存や削除で上書きしない")
func 破損または未知バージョンの履歴は保存や削除で上書きしない() throws {
    // Arrange
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.json")
    let store = SessionHistoryStore(fileURL: url)
    var session = try Session(plan: ReminderPlan(hydration: .init(isEnabled: false), fuel: .init(isEnabled: false)))
    session.end(at: .now)
    let entry = try #require(SessionHistoryEntry(session: session))

    for content in ["broken", "{\"version\":999,\"entries\":[]}"] {
        // Act
        let original = Data(content.utf8)
        try original.write(to: url)
        #expect(throws: (any Error).self) { try store.save(entry) }
        #expect(throws: (any Error).self) { try store.delete(id: entry.id) }

        // Assert
        #expect(try Data(contentsOf: url) == original)
    }
}

@Test("書き込み先を作成できない場合は履歴保存が失敗する")
func 書き込み先を作成できない場合は履歴保存が失敗する() throws {
    // Arrange
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("existing".utf8).write(to: parent)
    defer { try? FileManager.default.removeItem(at: parent) }
    let store = SessionHistoryStore(fileURL: parent.appendingPathComponent("history.json"))
    var session = try Session(plan: ReminderPlan(hydration: .init(isEnabled: false), fuel: .init(isEnabled: false)))
    session.end(at: .now)
    let entry = try #require(SessionHistoryEntry(session: session))

    // Act
    #expect(throws: (any Error).self) { try store.save(entry) }

    // Assert
    #expect(try Data(contentsOf: parent) == Data("existing".utf8))
}
