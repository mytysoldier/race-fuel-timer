import Foundation
import Testing
@testable import RaceFuelTimer

private let activityTestStart = Date(timeIntervalSince1970: 0)

private func activityTestSession() throws -> Session {
    try Session(plan: ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 10, repeatIntervalMinutes: 10,
                         displayName: "ジェルをとろう"),
        fuel: .init(isEnabled: false), notificationEndMinutes: 30
    ), startedAt: activityTestStart)
}

@Test("Live Activityの停止中は更新期限を持たず再開後の予定時刻は停止時間を除く")
func ライブ表示の停止再開で時刻が整合する() throws {
    // Arrange
    var session = try activityTestSession()
    session.pause(at: activityTestStart.addingTimeInterval(300))
    // Act
    let paused = try #require(SessionActivitySnapshot(session: session, at: activityTestStart.addingTimeInterval(1200)))
    session.resume(at: activityTestStart.addingTimeInterval(1200))
    let resumed = try #require(SessionActivitySnapshot(session: session, at: activityTestStart.addingTimeInterval(1300)))
    // Assert
    #expect(paused.content.pausedAt == activityTestStart.addingTimeInterval(300))
    #expect(paused.content.reminderDate == activityTestStart.addingTimeInterval(600))
    #expect(paused.content.staleDate == nil)
    #expect(resumed.content.timerStart == activityTestStart.addingTimeInterval(900))
    #expect(resumed.content.reminderDate == activityTestStart.addingTimeInterval(1500))
    #expect(resumed.content.staleDate == resumed.content.reminderDate)
    #expect(resumed.content.pausedAt == nil)
}

@Test("記録済みの補給予定はLive Activityへ再送信せず後続の時刻はずらさない")
func ライブ表示から記録済み予定を除く() throws {
    // Arrange
    var session = try activityTestSession()
    let now = activityTestStart.addingTimeInterval(300)
    // Act
    session.record(.taken, reminderID: session.schedule[0].identifier, at: now)
    let snapshot = try #require(SessionActivitySnapshot(session: session, at: now))
    // Assert
    #expect(snapshot.content.reminderName == "ジェルをとろう")
    #expect(snapshot.content.reminderDate == activityTestStart.addingTimeInterval(1200))
    #expect(snapshot.content.timerStart == activityTestStart)
}

@Test("通知終了予定後も経過を表示でき終了済みセッションはLive Activityを持たない")
func 予定なしと終了を区別する() throws {
    // Arrange
    var session = try activityTestSession()
    let now = activityTestStart.addingTimeInterval(2000)
    // Act
    let running = try #require(SessionActivitySnapshot(session: session, at: now))
    session.end(at: now)
    let ended = SessionActivitySnapshot(session: session, at: now)
    // Assert
    #expect(running.content.reminderDate == nil)
    #expect(running.content.reminderName == nil)
    #expect(running.content.timerStart == activityTestStart)
    #expect(ended == nil)
}

@Test("通知を使わないセッションもLive Activityの経過と状態を持つ")
func 通知なしでもライブ表示できる() throws {
    // Arrange
    let session = try Session(plan: .init(hydration: .init(isEnabled: false), fuel: .init(isEnabled: false)),
                              startedAt: activityTestStart)
    // Act
    let snapshot = try #require(SessionActivitySnapshot(session: session, at: activityTestStart.addingTimeInterval(60)))
    // Assert
    #expect(snapshot.content.timerStart == activityTestStart)
    #expect(snapshot.content.pausedAt == nil)
    #expect(snapshot.content.reminderDate == nil)
}

@MainActor
private final class ActivityTestClient: SessionActivityClient {
    var isEnabled = true
    var shouldFailStart = false
    var current: RunActivityAttributes.ContentState?
    var startCount = 0
    var events: [String] = []
    var duringUpdate: (() -> Void)?

    func start(_ snapshot: SessionActivitySnapshot) throws {
        startCount += 1
        if shouldFailStart { throw TestError.startFailed }
        current = snapshot.content
        events.append("start")
    }

    func update(_ content: RunActivityAttributes.ContentState) async -> Bool {
        guard current != nil else { return false }
        let hook = duringUpdate
        duringUpdate = nil
        hook?()
        await Task.yield()
        current = content
        events.append("update")
        return true
    }

    func endAll() async {
        current = nil
        events.append("end")
    }

    private enum TestError: Error { case startFailed }
}

@Test("Live Activity無効でもセッションは進み起動時の残留表示を削除する")
@MainActor
func ライブ表示無効時もタイマーを維持する() async throws {
    // Arrange
    let session = try activityTestSession()
    let client = ActivityTestClient()
    client.isEnabled = false
    client.current = SessionActivitySnapshot(session: session, at: activityTestStart)?.content
    let controller = SessionLiveActivityController(client: client)
    // Act
    controller.synchronize(session: session, at: activityTestStart.addingTimeInterval(300))
    await controller.waitForUpdates()
    // Assert
    #expect(controller.status == .unavailable)
    #expect(client.startCount == 0)
    #expect(client.current == nil)
    #expect(session.state == .running)
    #expect(session.elapsedSeconds(at: activityTestStart.addingTimeInterval(300)) == 300)
}

@Test("Live Activity開始失敗後に前面復帰しても同じランを繰り返し開始しない")
@MainActor
func ライブ表示開始失敗を安全に扱う() async throws {
    // Arrange
    let session = try activityTestSession()
    let client = ActivityTestClient()
    client.shouldFailStart = true
    let controller = SessionLiveActivityController(client: client)
    // Act
    controller.synchronize(session: session, at: activityTestStart)
    await controller.waitForUpdates()
    controller.synchronize(session: session, at: activityTestStart, force: true)
    await controller.waitForUpdates()
    // Assert
    #expect(controller.status == .unavailable)
    #expect(client.startCount == 1)
    #expect(client.current == nil)
    #expect(session.state == .running)
}

@Test("Live Activity更新中に終了しても古い更新の完了後に表示が残らない")
@MainActor
func ライブ表示更新と終了を直列化する() async throws {
    // Arrange
    var session = try activityTestSession()
    let client = ActivityTestClient()
    let controller = SessionLiveActivityController(client: client)
    controller.synchronize(session: session, at: activityTestStart)
    await controller.waitForUpdates()
    session.pause(at: activityTestStart.addingTimeInterval(300))
    client.duringUpdate = { controller.synchronize(session: nil) }
    // Act
    controller.synchronize(session: session, at: activityTestStart.addingTimeInterval(300))
    await controller.waitForUpdates()
    // Assert
    #expect(client.events.contains("update"))
    #expect(client.events.last == "end")
    #expect(client.current == nil)
    #expect(controller.status == .notStarted)
}

@Test("OSが終了または削除したLive Activityは同じランの前面復帰で作り直さない")
@MainActor
func 削除済みライブ表示を再作成しない() async throws {
    // Arrange
    let session = try activityTestSession()
    let client = ActivityTestClient()
    let controller = SessionLiveActivityController(client: client)
    controller.synchronize(session: session, at: activityTestStart)
    await controller.waitForUpdates()
    client.current = nil
    // Act
    controller.synchronize(session: session, at: activityTestStart.addingTimeInterval(700), force: true)
    await controller.waitForUpdates()
    // Assert
    #expect(client.startCount == 1)
    #expect(controller.status == .unavailable)
}

@Test("セッションなしの起動で前回のLive Activityを終了する")
@MainActor
func セッションなしの起動時に残留表示を削除する() async throws {
    // Arrange
    let client = ActivityTestClient()
    client.current = SessionActivitySnapshot(session: try activityTestSession(), at: activityTestStart)?.content
    let controller = SessionLiveActivityController(client: client)
    // Act
    controller.synchronize(session: nil)
    await controller.waitForUpdates()
    // Assert
    #expect(client.current == nil)
    #expect(client.startCount == 0)
    #expect(controller.status == .notStarted)
}
