import XCTest
@testable import RaceFuelTimer

final class ReminderScheduleTests: XCTestCase {
    func testScheduleMergesKindsAtTheSameMinute() throws {
        let plan = ReminderPlan(
            hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
            fuel: .init(isEnabled: true, firstReminderMinutes: 40, repeatIntervalMinutes: 40)
        )

        let schedule = try plan.schedule().get()

        XCTAssertEqual(schedule.count, 36)
        XCTAssertEqual(schedule[0].trigger, .elapsedMinutes(20))
        XCTAssertEqual(schedule[0].kinds, [.hydration])
        XCTAssertEqual(schedule[1].trigger, .elapsedMinutes(40))
        XCTAssertEqual(schedule[1].kinds, [.hydration, .fuel])
        XCTAssertEqual(schedule[1].displayNames[.hydration], "給水")
        XCTAssertEqual(schedule[1].displayNames[.fuel], "補給")
    }

    func testScheduleSupportsOnlyOneEnabledReminder() throws {
        let plan = ReminderPlan(
            hydration: .init(isEnabled: false),
            fuel: .init(isEnabled: true, firstReminderMinutes: 40, repeatIntervalMinutes: 40, displayName: "ジェル")
        )

        let schedule = try plan.schedule().get()

        XCTAssertEqual(schedule.count, 18)
        XCTAssertTrue(schedule.allSatisfy { $0.kinds == [.fuel] })
        XCTAssertEqual(schedule[0].displayNames[.fuel], "ジェル")
    }

    func testScheduleRejectsInvalidPlansWithoutCrashing() {
        let plan = ReminderPlan(
            hydration: .init(isEnabled: true, firstReminderMinutes: 0, repeatIntervalMinutes: nil),
            fuel: .init(isEnabled: false)
        )

        XCTAssertEqual(
            plan.validationErrors(),
            [.firstReminderOutOfRange(.hydration), .missingRepeatInterval(.hydration)]
        )
        XCTAssertEqual(plan.schedule(), .failure(.firstReminderOutOfRange(.hydration)))
    }

    func testScheduleRejectsMoreThanMaximumNotifications() {
        let plan = ReminderPlan(
            hydration: .init(isEnabled: true, firstReminderMinutes: 5, repeatIntervalMinutes: 5),
            fuel: .init(isEnabled: false)
        )

        XCTAssertEqual(plan.schedule(), .failure(.tooManyScheduledReminders))
    }

    func testExecutionStateSkipsDeliveredReminderWhenFindingNextReminder() throws {
        let plan = ReminderPlan(
            hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
            fuel: .init(isEnabled: false)
        )
        let schedule = try plan.schedule().get()
        var state = ReminderExecutionState()

        state.markDelivered(schedule[0])

        XCTAssertEqual(state.nextReminder(in: schedule, afterElapsedMinutes: 0), schedule[1])
        XCTAssertEqual(state.nextReminder(in: schedule, afterElapsedMinutes: 20), schedule[1])
        XCTAssertNil(state.nextReminder(in: schedule, afterElapsedMinutes: 720))
    }
}
