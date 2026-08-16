import Testing
@testable import RaceFuelTimer

@Test("同時刻の給水と補給を一件の予定へ統合する")
func 同時刻の給水と補給を一件の予定へ統合する() throws {
    // Arrange
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: true, firstReminderMinutes: 40, repeatIntervalMinutes: 40)
    )

    // Act
    let schedule = try plan.schedule().get()

    // Assert
    #expect(schedule.count == 36)
    #expect(schedule[0].trigger == .elapsedMinutes(20))
    #expect(schedule[0].kinds == [.hydration])
    #expect(schedule[1].trigger == .elapsedMinutes(40))
    #expect(schedule[1].kinds == [.hydration, .fuel])
    #expect(schedule[1].displayNames[.hydration] == "給水")
    #expect(schedule[1].displayNames[.fuel] == "補給")
}

@Test("補給だけを有効にした予定を生成する")
func 補給だけを有効にした予定を生成する() throws {
    // Arrange
    let plan = ReminderPlan(
        hydration: .init(isEnabled: false),
        fuel: .init(isEnabled: true, firstReminderMinutes: 40, repeatIntervalMinutes: 40, displayName: "ジェル")
    )

    // Act
    let schedule = try plan.schedule().get()

    // Assert
    #expect(schedule.count == 18)
    #expect(schedule.allSatisfy { $0.kinds == [.fuel] })
    #expect(schedule[0].displayNames[.fuel] == "ジェル")
}

@Test("不正な設定では予定を生成しない")
func 不正な設定では予定を生成しない() {
    // Arrange
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 0, repeatIntervalMinutes: nil),
        fuel: .init(isEnabled: false)
    )

    // Act
    let validationErrors = plan.validationErrors()
    let schedule = plan.schedule()

    // Assert
    #expect(
        validationErrors == [.firstReminderOutOfRange(.hydration), .missingRepeatInterval(.hydration)]
    )
    #expect(schedule == .failure(.firstReminderOutOfRange(.hydration)))
}

@Test("通知数が上限を超える設定を拒否する")
func 通知数が上限を超える設定を拒否する() {
    // Arrange
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 5, repeatIntervalMinutes: 5),
        fuel: .init(isEnabled: false)
    )

    // Act
    let schedule = plan.schedule()

    // Assert
    #expect(schedule == .failure(.tooManyScheduledReminders))
}

@Test("通知済みの予定を次回予定から除外する")
func 通知済みの予定を次回予定から除外する() throws {
    // Arrange
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: false)
    )
    let schedule = try plan.schedule().get()
    var state = ReminderExecutionState()

    // Act
    state.markDelivered(schedule[0])
    let nextAtStart = state.nextReminder(in: schedule, afterElapsedMinutes: 0)
    let nextAfterFirstReminder = state.nextReminder(in: schedule, afterElapsedMinutes: 20)
    let nextAtSessionEnd = state.nextReminder(in: schedule, afterElapsedMinutes: 720)

    // Assert
    #expect(nextAtStart == schedule[1])
    #expect(nextAfterFirstReminder == schedule[1])
    #expect(nextAtSessionEnd == nil)
}
