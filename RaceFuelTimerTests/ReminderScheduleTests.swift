import Foundation
import Testing
import UserNotifications
@testable import RaceFuelTimer

private func 週次集計用履歴(_ start: Date, duration: TimeInterval = 900, early: Bool = false) throws -> SessionHistoryEntry {
    let plan = ReminderPlan(hydration: .init(isEnabled: true, firstReminderMinutes: 10, repeatIntervalMinutes: 10),
                            fuel: .init(isEnabled: false), notificationEndMinutes: 30)
    var session = try Session(plan: plan, startedAt: start)
    if early { session.record(.taken, reminderID: session.schedule[0].identifier, at: start) }
    session.end(at: start.addingTimeInterval(duration))
    return try #require(SessionHistoryEntry(session: session))
}

@Test("週の境界は開始以上終了未満で開始週に全時間を計上する")
func 週の境界と週またぎの集計() throws {
    // Arrange
    var calendar = Calendar(identifier: .iso8601)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26)))
    let end = try #require(calendar.date(byAdding: .day, value: 7, to: start))
    let entries = try [週次集計用履歴(start.addingTimeInterval(-1)), 週次集計用履歴(start),
                       週次集計用履歴(end.addingTimeInterval(-1), duration: 1200), 週次集計用履歴(end)]
    // Act
    let summary = try #require(WeeklyHistorySummary(entries: entries, now: start, calendar: calendar))
    // Assert
    #expect(summary.runCount == 2)
    #expect(summary.elapsedSeconds == 2100)
    #expect(summary.dueCount == 3)
    #expect(summary.unrecordedCount == 3)
}

@Test("端末の時間帯で週を判定し先行記録と削除後の値を反映する")
func 時間帯と先行記録と削除後の集計() throws {
    // Arrange
    var utc = Calendar(identifier: .iso8601)
    utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    var japan = utc
    japan.timeZone = try #require(TimeZone(secondsFromGMT: 9 * 3600))
    let mondayUTC = try #require(utc.date(from: DateComponents(year: 2026, month: 10, day: 26)))
    let entry = try 週次集計用履歴(mondayUTC.addingTimeInterval(-3600), duration: 300, early: true)
    // Act
    let japanSummary = try #require(WeeklyHistorySummary(entries: [entry], now: mondayUTC, calendar: japan))
    let utcSummary = try #require(WeeklyHistorySummary(entries: [entry], now: mondayUTC, calendar: utc))
    let deleted = try #require(WeeklyHistorySummary(entries: [], now: mondayUTC, calendar: japan))
    // Assert
    #expect(japanSummary.runCount == 1)
    #expect(japanSummary.takenCount == 1)
    #expect(japanSummary.dueCount == 0)
    #expect(japanSummary.earlyRecordCount == 1)
    #expect(utcSummary.runCount == 0)
    #expect(deleted.runCount == 0)
    #expect(deleted.elapsedSeconds == 0)
}

@Test("10分ごとの通知を終了予定まで生成する")
func 十分ごとの通知を終了予定まで生成する() throws {
    // Arrange
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 10, repeatIntervalMinutes: 10),
        fuel: .init(isEnabled: false),
        notificationEndMinutes: 240
    )

    // Act
    let schedule = try plan.schedule().get()

    // Assert
    #expect(schedule.count == 24)
    #expect(schedule.first?.trigger == .elapsedMinutes(10))
    #expect(schedule.last?.trigger == .elapsedMinutes(240))
}

@Test("通知終了予定後の通知を生成しない")
func 通知終了予定後の通知を生成しない() throws {
    // Arrange
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: false),
        notificationEndMinutes: 90
    )

    // Act
    let schedule = try plan.schedule().get()

    // Assert
    #expect(schedule.map(\.trigger) == [.elapsedMinutes(20), .elapsedMinutes(40), .elapsedMinutes(60), .elapsedMinutes(80)])
}

@Test("通知をオフにしてもタイマー用の予定生成に失敗しない")
func 通知をオフにしてもタイマー用の予定生成に失敗しない() throws {
    // Arrange
    let plan = ReminderPlan(hydration: .init(isEnabled: false), fuel: .init(isEnabled: false))

    // Act
    let schedule = try plan.schedule().get()

    // Assert
    #expect(schedule.isEmpty)
}

@Test("予約上限を超える組み合わせを拒否する")
func 予約上限を超える組み合わせを拒否する() {
    // Arrange
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 10, repeatIntervalMinutes: 10),
        fuel: .init(isEnabled: false),
        notificationEndMinutes: 720
    )

    // Act
    let schedule = plan.schedule()

    // Assert
    #expect(schedule == .failure(.tooManyScheduledReminders))
}

@Test("詳細設定の間隔より短い通知終了予定は候補に出さない")
func 詳細設定の間隔より短い通知終了予定は候補に出さない() {
    // Arrange
    let intervalMinutes = 240

    // Act
    let options = EditablePlan.notificationEndOptions(intervalMinutes: intervalMinutes)

    // Assert
    #expect(!options.contains(120))
    #expect(options.first == 240)
}

@Test("通知間隔を長くしたとき終了予定は最短の有効値へ寄せる")
func 通知間隔を長くしたとき終了予定は最短の有効値へ寄せる() {
    // Arrange
    let notificationEndMinutes = 30

    // Act
    let normalizedEnd = EditablePlan.normalizedEnd(notificationEndMinutes, intervalMinutes: 40)

    // Assert
    #expect(normalizedEnd == 60)
}

@Test("通知メッセージを通知本文に使う")
func 通知メッセージを通知本文に使う() throws {
    // Arrange
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20, displayName: "ジェルをとろう"),
        fuel: .init(isEnabled: false),
        notificationEndMinutes: 120
    )

    // Act
    let reminder = try plan.schedule().get()[0]

    // Assert
    #expect(reminder.notificationTitle == "ランニング補給タイマー")
    #expect(reminder.notificationBody == "ジェルをとろう")
}

@Test("一時停止中は次の補給予定が進まない")
func 一時停止中は次の補給予定が進まない() throws {
    // Arrange
    let startedAt = Date(timeIntervalSinceReferenceDate: 0)
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: false),
        notificationEndMinutes: 240
    )
    var session = try Session(plan: plan, startedAt: startedAt)
    session.pause(at: startedAt.addingTimeInterval(10 * 60))

    // Act
    let nextReminder = session.nextReminder(at: startedAt.addingTimeInterval(40 * 60))

    // Assert
    #expect(nextReminder?.trigger == .elapsedMinutes(20))
}

private func 記録用セッション() throws -> Session {
    try Session(plan: ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 10, repeatIntervalMinutes: 10),
        fuel: .init(isEnabled: false), notificationEndMinutes: 30
    ), startedAt: Date(timeIntervalSince1970: 0))
}

@Test("予定直前の先行記録は同じIDの連打で次の予定に記録しない")
func 予定直前の先行記録は同じIDの連打で次の予定に記録しない() throws {
    // Arrange
    var session = try 記録用セッション()
    let target = try #require(session.recordingTarget(at: Date(timeIntervalSince1970: 599)))
    // Act
    let first = session.record(.taken, reminderID: target.identifier, at: Date(timeIntervalSince1970: 599))
    let duplicate = session.record(.skipped, reminderID: target.identifier, at: Date(timeIntervalSince1970: 600))
    // Assert
    #expect(first)
    #expect(!duplicate)
    #expect(session.records.count == 1)
    #expect(session.records[target.identifier]?.recordedAt == Date(timeIntervalSince1970: 599))
    #expect(session.records[target.identifier]?.result == .taken)
    #expect(session.nextReminder(at: Date(timeIntervalSince1970: 599))?.trigger.minutes == 20)
    #expect(session.pendingReminders(at: Date(timeIntervalSince1970: 599)).map(\.trigger.minutes) == [20, 30])
}

@Test("復帰で通知到来を同期しても過去の未記録予定を古い順に記録できる")
func 復帰で通知到来を同期しても過去の未記録予定を古い順に記録できる() throws {
    // Arrange
    var session = try 記録用セッション()
    let now = Date(timeIntervalSince1970: 1200)
    // Act
    session.synchronizeAfterInterruption(at: now)
    let target = try #require(session.recordingTarget(at: now))
    let recorded = session.record(.skipped, reminderID: target.identifier, at: now)
    // Assert
    #expect(target.trigger.minutes == 10)
    #expect(recorded)
    #expect(session.recordingTarget(at: now)?.trigger.minutes == 20)
    #expect(session.nextReminder(at: now)?.trigger.minutes == 30)
    #expect(session.pendingReminders(at: now).map(\.trigger.minutes) == [30])
}

@Test("一時停止中は記録と通知予約を拒否し再開後は停止時間を除く")
func 一時停止中は記録と通知予約を拒否し再開後は停止時間を除く() throws {
    // Arrange
    var session = try 記録用セッション()
    let target = session.schedule[0]
    session.pause(at: Date(timeIntervalSince1970: 300))
    // Act
    let pausedRecord = session.record(.taken, reminderID: target.identifier, at: Date(timeIntervalSince1970: 1000))
    let pausedPending = session.pendingReminders(at: Date(timeIntervalSince1970: 1000))
    let resumed = session.resume(at: Date(timeIntervalSince1970: 1200))
    let recorded = session.record(.taken, reminderID: target.identifier, at: Date(timeIntervalSince1970: 1500))
    // Assert
    #expect(!pausedRecord)
    #expect(pausedPending.isEmpty)
    #expect(resumed)
    #expect(recorded)
    #expect(session.elapsedSeconds(at: Date(timeIntervalSince1970: 1500)) == 600)
    #expect(session.pendingReminders(at: Date(timeIntervalSince1970: 1500)).map(\.trigger.minutes) == [20, 30])
}

@Test("途中終了サマリは到来済み未記録と未到来の先行記録を区別する")
func 途中終了サマリは到来済み未記録と未到来の先行記録を区別する() throws {
    // Arrange
    var session = try 記録用セッション()
    session.record(.taken, reminderID: session.schedule[0].identifier, at: Date(timeIntervalSince1970: 500))
    session.record(.skipped, reminderID: session.schedule[1].identifier, at: Date(timeIntervalSince1970: 600))
    // Act
    session.end(at: Date(timeIntervalSince1970: 900))
    let summary = try #require(session.summary)
    let endedRecord = session.record(.taken, reminderID: session.schedule[2].identifier, at: Date(timeIntervalSince1970: 1800))
    // Assert
    #expect(summary == SessionSummary(elapsedSeconds: 900, dueCount: 1, takenCount: 1,
                                     skippedCount: 1, unrecordedCount: 0, earlyRecordCount: 1))
    #expect(!endedRecord)
    #expect(session.pendingReminders(at: Date(timeIntervalSince1970: 900)).isEmpty)
    #expect(session.summary == summary)
}

@Test("通知終了予定後も未記録を記録でき記録ゼロサマリは全到来を未記録にする")
func 通知終了予定後も未記録を記録でき記録ゼロサマリは全到来を未記録にする() throws {
    // Arrange
    var empty = try 記録用セッション()
    var recorded = empty
    let date = Date(timeIntervalSince1970: 2400)
    // Act
    empty.end(at: date)
    let success = recorded.record(.taken, reminderID: recorded.schedule[0].identifier, at: date)
    recorded.end(at: date)
    // Assert
    #expect(empty.summary?.dueCount == 3)
    #expect(empty.summary?.unrecordedCount == 3)
    #expect(empty.summary?.takenCount == 0)
    #expect(success)
    #expect(recorded.summary?.unrecordedCount == 2)
    #expect(recorded.summary?.takenCount == 1)
}

@Test("通知なしプランと再開始のログは空で安全に集計できる")
func 通知なしプランと再開始のログは空で安全に集計できる() throws {
    // Arrange
    var session = try Session(plan: ReminderPlan(hydration: .init(isEnabled: false), fuel: .init(isEnabled: false)),
                              startedAt: Date(timeIntervalSince1970: 0))
    let next = try 記録用セッション()
    // Act
    let target = session.recordingTarget(at: Date(timeIntervalSince1970: 3600))
    session.end(at: Date(timeIntervalSince1970: 3600))
    // Assert
    #expect(target == nil)
    #expect(session.summary == SessionSummary(elapsedSeconds: 3600, dueCount: 0, takenCount: 0,
                                             skippedCount: 0, unrecordedCount: 0, earlyRecordCount: 0))
    #expect(next.records.isEmpty)
    #expect(next.summary == nil)
}

@Test("存在しない予定や対象外IDは記録せず通知時刻境界でも予定IDを維持する")
func 存在しない予定や対象外IDは記録せず通知時刻境界でも予定IDを維持する() throws {
    // Arrange
    var session = try 記録用セッション()
    let date = Date(timeIntervalSince1970: 600)
    // Act
    let unknown = session.record(.taken, reminderID: "unknown", at: date)
    let later = session.record(.taken, reminderID: session.schedule[1].identifier, at: date)
    let first = session.record(.taken, reminderID: session.schedule[0].identifier, at: date)
    // Assert
    #expect(!unknown)
    #expect(!later)
    #expect(first)
    #expect(session.records.count == 1)
    #expect(session.pendingReminders(at: date).map(\.trigger.minutes) == [20, 30])
}

@Test("一時停止中の終了サマリは停止中の時間を含めない")
func 一時停止中の終了サマリは停止中の時間を含めない() throws {
    // Arrange
    var session = try 記録用セッション()
    session.pause(at: Date(timeIntervalSince1970: 900))
    // Act
    session.end(at: Date(timeIntervalSince1970: 7200))
    // Assert
    #expect(session.summary?.elapsedSeconds == 900)
    #expect(session.summary?.dueCount == 1)
    #expect(session.summary?.unrecordedCount == 1)
}

@MainActor
private final class 記録通知センター: NotificationCenterClient {
    var requests: [String: UNNotificationRequest] = [:]
    var duringAuthorization: (() -> Void)?
    var duringAdd: ((UNNotificationRequest) -> Void)?
    var duringPendingRead: (() async -> Void)?

    func authorizationStatus() async -> UNAuthorizationStatus {
        duringAuthorization?()
        return .authorized
    }

    func requestAuthorization() async throws -> Bool { true }

    func add(_ request: UNNotificationRequest) async throws {
        duringAdd?(request)
        // 取消が先行してもOS側への追加が完了する競合を再現する。
        requests[request.identifier] = request
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        let hook = duringPendingRead
        duringPendingRead = nil
        await hook?()
        return Array(requests.values)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        for identifier in identifiers { requests[identifier] = nil }
    }
}

@Test("通知追加中の記録取消は追加完了後も対象通知を残さず後続時刻を保つ")
@MainActor
func 通知追加中の記録取消は追加完了後も対象通知を残さず後続時刻を保つ() async throws {
    // Arrange
    let center = 記録通知センター()
    let scheduler = LocalNotificationScheduler(center: center)
    let session = try Session(plan: ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 10, repeatIntervalMinutes: 10),
        fuel: .init(isEnabled: false), notificationEndMinutes: 30))
    let id = session.schedule[0].identifier
    center.duringAdd = { request in
        if request.identifier.hasPrefix(id + "-") { scheduler.cancelReminder(id) }
    }
    let operation = scheduler.beginNotificationOperation()
    // Act
    await scheduler.requestAuthorizationAndSchedule(for: session, operationID: operation)
    // Assert
    #expect(center.requests.count == 2)
    #expect(!center.requests.keys.contains { $0.hasPrefix(id + "-") })
    let intervals = center.requests.values.compactMap { ($0.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval }.sorted()
    #expect(intervals.count == 2)
    #expect(intervals[0] > 1190 && intervals[0] <= 1200)
    #expect(intervals[1] > 1790 && intervals[1] <= 1800)
}

@Test("通知許可待ちの記録と再開でも記録済み通知を再予約しない")
@MainActor
func 通知許可待ちの記録と再開でも記録済み通知を再予約しない() async throws {
    // Arrange
    let center = 記録通知センター()
    let scheduler = LocalNotificationScheduler(center: center)
    var session = try Session(plan: ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 10, repeatIntervalMinutes: 10),
        fuel: .init(isEnabled: false), notificationEndMinutes: 30))
    let id = session.schedule[0].identifier
    center.duringAuthorization = { scheduler.cancelReminder(id) }
    let operation = scheduler.beginNotificationOperation()
    // Act
    await scheduler.requestAuthorizationAndSchedule(for: session, operationID: operation)
    let initialIDs = Set(center.requests.keys)
    session.record(.taken, reminderID: id, at: .now)
    session.pause(at: .now)
    scheduler.cancelScheduledReminders()
    session.resume(at: .now)
    let resumedOperation = scheduler.beginNotificationOperation()
    await scheduler.scheduleReminders(for: session, operationID: resumedOperation)
    // Assert
    #expect(initialIDs.count == 2)
    #expect(center.requests.count == 2)
    #expect(!center.requests.keys.contains { $0.hasPrefix(id + "-") })
}

@Test("通知追加中の終了は後続を含む全通知を取り消す")
@MainActor
func 通知追加中の終了は後続を含む全通知を取り消す() async throws {
    // Arrange
    let center = 記録通知センター()
    let scheduler = LocalNotificationScheduler(center: center)
    let session = try Session(plan: ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 10, repeatIntervalMinutes: 10),
        fuel: .init(isEnabled: false), notificationEndMinutes: 30))
    center.duringAdd = { _ in scheduler.cancelScheduledReminders() }
    let operation = scheduler.beginNotificationOperation()
    // Act
    await scheduler.requestAuthorizationAndSchedule(for: session, operationID: operation)
    // Assert
    #expect(center.requests.isEmpty)
}

@Test("再起動後の新セッション開始で前プロセスの予約通知が残らない")
@MainActor
func 再起動後に古い予約通知を残さない() async throws {
    // Arrange
    let center = 記録通知センター()
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 10, repeatIntervalMinutes: 10),
        fuel: .init(isEnabled: false), notificationEndMinutes: 30
    )
    let previousScheduler = LocalNotificationScheduler(center: center)
    let previousSession = try Session(plan: plan)
    let previousOperation = previousScheduler.beginNotificationOperation()
    await previousScheduler.requestAuthorizationAndSchedule(for: previousSession, operationID: previousOperation)
    let previousIDs = Set(center.requests.keys)
    let restartedScheduler = LocalNotificationScheduler(center: center)
    let newSession = try Session(plan: plan)
    // Act
    let newOperation = restartedScheduler.beginNotificationOperation()
    await restartedScheduler.requestAuthorizationAndSchedule(for: newSession, operationID: newOperation)
    // Assert
    #expect(previousIDs.count == 3)
    #expect(center.requests.count == 3)
    #expect(Set(center.requests.keys).isDisjoint(with: previousIDs))
    #expect(center.requests.keys.allSatisfy { $0.hasSuffix(newOperation.uuidString) })
}

private func 残留検証用通知(_ identifier: String) -> UNNotificationRequest {
    UNNotificationRequest(identifier: identifier, content: UNMutableNotificationContent(),
                          trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false))
}

@Test("起動時に古い補給予約だけを削除し別用途の予約を保持する")
@MainActor
func 起動時に古い補給予約だけを削除する() async {
    // Arrange
    let center = 記録通知センター()
    let oldID = "reminder-10-hydration-" + UUID().uuidString
    center.requests[oldID] = 残留検証用通知(oldID)
    center.requests["unrelated-request"] = 残留検証用通知("unrelated-request")
    // Act
    let scheduler = LocalNotificationScheduler(center: center)
    await scheduler.waitForPendingCleanup()
    // Assert
    #expect(Set(center.requests.keys) == ["unrelated-request"])
    #expect(scheduler.authorization == .notRequested)
}

@Test("通知なしの新しい予約操作でも古い補給予約を取り消す")
@MainActor
func 通知なし開始でも古い補給予約を取り消す() async {
    // Arrange
    let center = 記録通知センター()
    let scheduler = LocalNotificationScheduler(center: center)
    await scheduler.waitForPendingCleanup()
    let oldID = "reminder-20-hydration-" + UUID().uuidString
    center.requests[oldID] = 残留検証用通知(oldID)
    // Act
    _ = scheduler.beginNotificationOperation()
    await scheduler.waitForPendingCleanup()
    // Assert
    #expect(center.requests.isEmpty)
    #expect(scheduler.authorization == .notRequested)
}

@Test("起動時の古い予約取得が遅れても新しいランの予約を消さない")
@MainActor
func 遅い起動時整理から新しい予約を保護する() async throws {
    // Arrange
    let center = 記録通知センター()
    let oldID = "reminder-10-hydration-" + UUID().uuidString
    center.requests[oldID] = 残留検証用通知(oldID)
    let session = try Session(plan: ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 10, repeatIntervalMinutes: 10),
        fuel: .init(isEnabled: false), notificationEndMinutes: 30
    ))
    let scheduler = LocalNotificationScheduler(center: center)
    var newOperation: UUID?
    // 起動時の照会が、新ランの予約追加後の内容を返す競合を再現する。
    center.duringPendingRead = {
        let operation = scheduler.beginNotificationOperation()
        newOperation = operation
        await scheduler.requestAuthorizationAndSchedule(for: session, operationID: operation)
    }
    // Act
    await scheduler.waitForPendingCleanup()
    // Assert
    let operation = try #require(newOperation)
    #expect(center.requests.count == 3)
    #expect(center.requests[oldID] == nil)
    #expect(center.requests.keys.allSatisfy { $0.hasSuffix(operation.uuidString) })
}

@Test("古い予約整理を待つ間に別操作が始まっても旧操作は予約しない")
@MainActor
func 古い予約操作を再開させない() async throws {
    // Arrange
    let center = 記録通知センター()
    let scheduler = LocalNotificationScheduler(center: center)
    let session = try Session(plan: ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 10, repeatIntervalMinutes: 10),
        fuel: .init(isEnabled: false), notificationEndMinutes: 30
    ))
    let oldOperation = scheduler.beginNotificationOperation()
    let newOperation = scheduler.beginNotificationOperation()
    // Act
    await scheduler.requestAuthorizationAndSchedule(for: session, operationID: oldOperation)
    let oldRequests = center.requests
    await scheduler.requestAuthorizationAndSchedule(for: session, operationID: newOperation)
    // Assert
    #expect(oldRequests.isEmpty)
    #expect(center.requests.count == 3)
    #expect(center.requests.keys.allSatisfy { $0.hasSuffix(newOperation.uuidString) })
}
