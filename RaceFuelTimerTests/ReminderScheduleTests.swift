import Foundation
import Testing
@testable import RaceFuelTimer

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
