import Foundation
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

@Test("15km未満のプリセットでは補給通知を無効にする")
func 十五km未満のプリセットでは補給通知を無効にする() {
    // Arrange
    let distance = PlannedDistance.tenKilometers.kilometers

    // Act
    let plan = ReminderPlanPreset.make(for: distance)

    // Assert
    #expect(plan.hydration.isEnabled)
    #expect(plan.hydration.firstReminderMinutes == 20)
    #expect(!plan.fuel.isEnabled)
}

@Test("15km以上のプリセットでは補給通知を40分で有効にする")
func 十五km以上のプリセットでは補給通知を40分で有効にする() {
    // Arrange
    let distance = PlannedDistance.halfMarathon.kilometers

    // Act
    let plan = ReminderPlanPreset.make(for: distance)

    // Assert
    #expect(plan.fuel.isEnabled)
    #expect(plan.fuel.firstReminderMinutes == 40)
    #expect(plan.fuel.repeatIntervalMinutes == 40)
}

@Test("カスタム距離が15km以上なら補給通知を有効にする")
func カスタム距離が十五km以上なら補給通知を有効にする() {
    // Arrange
    let customDistance = 15.0

    // Act
    let plan = ReminderPlanPreset.make(for: customDistance)

    // Assert
    #expect(plan.fuel.isEnabled)
    #expect(plan.fuel.firstReminderMinutes == 40)
}

@Test("小数点にカンマを使うロケールのカスタム距離を読み取る")
func 小数点にカンマを使うロケールのカスタム距離を読み取る() {
    // Arrange
    let locale = Locale(identifier: "fr_FR")

    // Act
    let distance = DistanceParser.kilometers(from: "15,5", locale: locale)

    // Assert
    #expect(distance == 15.5)
}

@Test("単位などの末尾文字を含むカスタム距離を拒否する")
func 単位などの末尾文字を含むカスタム距離を拒否する() {
    // Arrange
    let locale = Locale(identifier: "ja_JP")

    // Act
    let distance = DistanceParser.kilometers(from: "15 km", locale: locale)

    // Assert
    #expect(distance == nil)
}
