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

@Test("小数点にカンマを使うロケールでカスタム距離を復元できる")
func 小数点にカンマを使うロケールでカスタム距離を復元できる() {
    // Arrange
    let locale = Locale(identifier: "fr_FR")

    // Act
    let text = DistanceParser.text(from: 15.5, locale: locale)
    let distance = DistanceParser.kilometers(from: text, locale: locale)

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

@Test("一時停止中は経過時間と次回予定が進まない")
func 一時停止中は経過時間と次回予定が進まない() throws {
    // Arrange
    let startedAt = Date(timeIntervalSinceReferenceDate: 0)
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: false)
    )
    var session = try Session(plan: plan, startedAt: startedAt)
    session.pause(at: startedAt.addingTimeInterval(10 * 60))

    // Act
    let elapsedMinutes = session.elapsedMinutes(at: startedAt.addingTimeInterval(40 * 60))
    let nextReminder = session.nextReminder(at: startedAt.addingTimeInterval(40 * 60))

    // Assert
    #expect(session.state == .paused)
    #expect(elapsedMinutes == 10)
    #expect(nextReminder?.trigger == .elapsedMinutes(20))
}

@Test("再開後は停止時間を除いた経過時間で次回予定を計算する")
func 再開後は停止時間を除いた経過時間で次回予定を計算する() throws {
    // Arrange
    let startedAt = Date(timeIntervalSinceReferenceDate: 0)
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: false)
    )
    var session = try Session(plan: plan, startedAt: startedAt)
    session.pause(at: startedAt.addingTimeInterval(10 * 60))
    session.resume(at: startedAt.addingTimeInterval(40 * 60))

    // Act
    let elapsedMinutes = session.elapsedMinutes(at: startedAt.addingTimeInterval(50 * 60))
    let nextReminder = session.nextReminder(at: startedAt.addingTimeInterval(50 * 60))

    // Assert
    #expect(session.state == .running)
    #expect(elapsedMinutes == 20)
    #expect(nextReminder?.trigger == .elapsedMinutes(40))
}

@Test("終了したセッションは停止時間を確定して状態を終了にする")
func 終了したセッションは停止時間を確定して状態を終了にする() throws {
    // Arrange
    let startedAt = Date(timeIntervalSinceReferenceDate: 0)
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: false)
    )
    var session = try Session(plan: plan, startedAt: startedAt)
    session.pause(at: startedAt.addingTimeInterval(10 * 60))

    // Act
    session.end(at: startedAt.addingTimeInterval(40 * 60))

    // Assert
    #expect(session.state == .ended)
    #expect(session.elapsedMinutes(at: startedAt.addingTimeInterval(50 * 60)) == 10)
}

@Test("実行中から終了したセッションの経過時間を固定する")
func 実行中から終了したセッションの経過時間を固定する() throws {
    // Arrange
    let startedAt = Date(timeIntervalSinceReferenceDate: 0)
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: false)
    )
    var session = try Session(plan: plan, startedAt: startedAt)

    // Act
    session.end(at: startedAt.addingTimeInterval(30 * 60))
    let elapsedMinutes = session.elapsedMinutes(at: startedAt.addingTimeInterval(50 * 60))

    // Assert
    #expect(session.state == .ended)
    #expect(elapsedMinutes == 30)
}

@Test("給水と補給の次回予定をそれぞれ取得する")
func 給水と補給の次回予定をそれぞれ取得する() throws {
    // Arrange
    let startedAt = Date(timeIntervalSinceReferenceDate: 0)
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: true, firstReminderMinutes: 40, repeatIntervalMinutes: 40)
    )
    let session = try Session(plan: plan, startedAt: startedAt)

    // Act
    let hydrationReminder = session.nextReminder(for: .hydration, at: startedAt)
    let fuelReminder = session.nextReminder(for: .fuel, at: startedAt)

    // Assert
    #expect(hydrationReminder?.trigger == .elapsedMinutes(20))
    #expect(fuelReminder?.trigger == .elapsedMinutes(40))
}

@Test("給水と補給で通知文言を区別する")
func 給水と補給で通知文言を区別する() throws {
    // Arrange
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: true, firstReminderMinutes: 40, repeatIntervalMinutes: 40, displayName: "ジェル")
    )
    let schedule = try plan.schedule().get()

    // Act
    let hydrationReminder = schedule[0]
    let combinedReminder = schedule[1]

    // Assert
    #expect(hydrationReminder.notificationTitle == "給水の時間です")
    #expect(hydrationReminder.notificationBody.contains("給水"))
    #expect(combinedReminder.notificationTitle == "給水・補給の時間です")
    #expect(combinedReminder.notificationBody.contains("ジェル"))
}

@Test("復帰時に経過済み予定を通知済みにして次回予定を二重表示しない")
func 復帰時に経過済み予定を通知済みにして次回予定を二重表示しない() throws {
    // Arrange
    let startedAt = Date(timeIntervalSinceReferenceDate: 0)
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: false)
    )
    var session = try Session(plan: plan, startedAt: startedAt)
    let resumedAt = startedAt.addingTimeInterval(45 * 60)

    // Act
    session.synchronizeAfterInterruption(at: resumedAt)
    let nextReminder = session.nextReminder(at: resumedAt)

    // Assert
    #expect(session.reminderExecutionState.deliveredReminderIDs == ["reminder-20-hydration", "reminder-40-hydration"])
    #expect(nextReminder?.trigger == .elapsedMinutes(60))
}

@Test("一時停止中の復帰同期では停止時点より先の予定を通知済みにしない")
func 一時停止中の復帰同期では停止時点より先の予定を通知済みにしない() throws {
    // Arrange
    let startedAt = Date(timeIntervalSinceReferenceDate: 0)
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: false)
    )
    var session = try Session(plan: plan, startedAt: startedAt)
    session.pause(at: startedAt.addingTimeInterval(10 * 60))

    // Act
    session.synchronizeAfterInterruption(at: startedAt.addingTimeInterval(45 * 60))
    let nextReminder = session.nextReminder(at: startedAt.addingTimeInterval(45 * 60))

    // Assert
    #expect(session.reminderExecutionState.deliveredReminderIDs.isEmpty)
    #expect(nextReminder?.trigger == .elapsedMinutes(20))
}

@Test("セッション終了時刻ちょうどの予定まで生成する")
func セッション終了時刻ちょうどの予定まで生成する() throws {
    // Arrange
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 240, repeatIntervalMinutes: 240),
        fuel: .init(isEnabled: false)
    )

    // Act
    let schedule = try plan.schedule().get()

    // Assert
    #expect(schedule.map(\.trigger) == [
        .elapsedMinutes(240),
        .elapsedMinutes(480),
        .elapsedMinutes(720),
    ])
}

@Test("同時刻の予定は種類の順序に関係なく同じ識別子になる")
func 同時刻の予定は種類の順序に関係なく同じ識別子になる() {
    // Arrange
    let hydrationAndFuel = ScheduledReminder(
        trigger: .elapsedMinutes(40),
        kinds: [.hydration, .fuel],
        displayNames: [.hydration: "給水", .fuel: "補給"]
    )
    let fuelAndHydration = ScheduledReminder(
        trigger: .elapsedMinutes(40),
        kinds: [.fuel, .hydration],
        displayNames: [.hydration: "給水", .fuel: "補給"]
    )

    // Act
    let identifiers = [hydrationAndFuel.identifier, fuelAndHydration.identifier]

    // Assert
    #expect(identifiers == ["reminder-40-fuel-hydration", "reminder-40-fuel-hydration"])
}

@Test("不正な状態遷移と過去時刻ではセッションの経過時間を巻き戻さない")
func 不正な状態遷移と過去時刻ではセッションの経過時間を巻き戻さない() throws {
    // Arrange
    let startedAt = Date(timeIntervalSinceReferenceDate: 1_000)
    let plan = ReminderPlan(
        hydration: .init(isEnabled: true, firstReminderMinutes: 20, repeatIntervalMinutes: 20),
        fuel: .init(isEnabled: false)
    )
    var session = try Session(plan: plan, startedAt: startedAt)

    // Act
    session.resume(at: startedAt.addingTimeInterval(10 * 60))
    session.pause(at: startedAt.addingTimeInterval(10 * 60))
    session.resume(at: startedAt.addingTimeInterval(5 * 60))
    let elapsedMinutes = session.elapsedMinutes(at: startedAt.addingTimeInterval(30 * 60))

    // Assert
    #expect(session.state == .running)
    #expect(elapsedMinutes == 30)
    #expect(session.totalPausedSeconds == 0)
}
