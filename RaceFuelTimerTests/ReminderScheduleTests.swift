import Testing
@testable import RaceFuelTimer

@Test
func scheduleMergesKindsAtTheSameMinute() throws {
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: true, firstReminderMinutes: 40, repeatIntervalMinutes: 40)
    )

    let schedule = try plan.schedule().get()

    #expect(schedule.count == 36)
    #expect(schedule[0].trigger == .elapsedMinutes(20))
    #expect(schedule[0].kinds == [.hydration])
    #expect(schedule[1].trigger == .elapsedMinutes(40))
    #expect(schedule[1].kinds == [.hydration, .fuel])
    #expect(schedule[1].displayNames[.hydration] == "給水")
    #expect(schedule[1].displayNames[.fuel] == "補給")
}

@Test
func scheduleSupportsOnlyOneEnabledReminder() throws {
    let plan = ReminderPlan(
        hydration: .init(isEnabled: false),
        fuel: .init(isEnabled: true, firstReminderMinutes: 40, repeatIntervalMinutes: 40, displayName: "ジェル")
    )

    let schedule = try plan.schedule().get()

    #expect(schedule.count == 18)
    #expect(schedule.allSatisfy { $0.kinds == [.fuel] })
    #expect(schedule[0].displayNames[.fuel] == "ジェル")
}

@Test
func scheduleRejectsInvalidPlansWithoutCrashing() {
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 0, repeatIntervalMinutes: nil),
        fuel: .init(isEnabled: false)
    )

    #expect(
        plan.validationErrors() == [.firstReminderOutOfRange(.hydration), .missingRepeatInterval(.hydration)]
    )
    #expect(plan.schedule() == .failure(.firstReminderOutOfRange(.hydration)))
}

@Test
func scheduleRejectsMoreThanMaximumNotifications() {
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 5, repeatIntervalMinutes: 5),
        fuel: .init(isEnabled: false)
    )

    #expect(plan.schedule() == .failure(.tooManyScheduledReminders))
}

@Test
func executionStateSkipsDeliveredReminderWhenFindingNextReminder() throws {
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: false)
    )
    let schedule = try plan.schedule().get()
    var state = ReminderExecutionState()

    state.markDelivered(schedule[0])

    #expect(state.nextReminder(in: schedule, afterElapsedMinutes: 0) == schedule[1])
    #expect(state.nextReminder(in: schedule, afterElapsedMinutes: 20) == schedule[1])
    #expect(state.nextReminder(in: schedule, afterElapsedMinutes: 720) == nil)
}
