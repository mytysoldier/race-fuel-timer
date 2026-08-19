import Foundation

enum ReminderKind: String, CaseIterable, Hashable {
    case hydration
    case fuel

    var defaultDisplayName: String {
        switch self {
        case .hydration:
            "給水"
        case .fuel:
            "補給"
        }
    }
}

enum ReminderTrigger: Hashable {
    case elapsedMinutes(Int)

    var minutes: Int {
        switch self {
        case let .elapsedMinutes(minutes):
            minutes
        }
    }
}

struct ReminderSetting: Equatable {
    let isEnabled: Bool
    let firstReminderMinutes: Int?
    let repeatIntervalMinutes: Int?
    let displayName: String

    init(
        isEnabled: Bool,
        firstReminderMinutes: Int? = nil,
        repeatIntervalMinutes: Int? = nil,
        displayName: String = ""
    ) {
        self.isEnabled = isEnabled
        self.firstReminderMinutes = firstReminderMinutes
        self.repeatIntervalMinutes = repeatIntervalMinutes
        self.displayName = displayName
    }
}

struct ReminderPlan: Equatable {
    static let maximumSessionMinutes = 12 * 60
    static let maximumScheduledReminders = 60
    static let allowedReminderMinutes = 5...240

    let hydration: ReminderSetting
    let fuel: ReminderSetting

    init(hydration: ReminderSetting, fuel: ReminderSetting) {
        self.hydration = hydration
        self.fuel = fuel
    }

    func setting(for kind: ReminderKind) -> ReminderSetting {
        switch kind {
        case .hydration:
            hydration
        case .fuel:
            fuel
        }
    }

    func validationErrors() -> [ReminderPlanValidationError] {
        var errors: [ReminderPlanValidationError] = []
        let enabledKinds = ReminderKind.allCases.filter { setting(for: $0).isEnabled }

        if enabledKinds.isEmpty {
            errors.append(.noReminderEnabled)
        }

        for kind in enabledKinds {
            let setting = setting(for: kind)

            if let firstReminderMinutes = setting.firstReminderMinutes {
                if !Self.allowedReminderMinutes.contains(firstReminderMinutes) {
                    errors.append(.firstReminderOutOfRange(kind))
                }
            } else {
                errors.append(.missingFirstReminder(kind))
            }

            if let repeatIntervalMinutes = setting.repeatIntervalMinutes {
                if !Self.allowedReminderMinutes.contains(repeatIntervalMinutes) {
                    errors.append(.repeatIntervalOutOfRange(kind))
                }
            } else {
                errors.append(.missingRepeatInterval(kind))
            }

            if setting.displayName.trimmingCharacters(in: .whitespacesAndNewlines).count > 30 {
                errors.append(.displayNameTooLong(kind))
            }
        }

        guard errors.isEmpty else { return errors }

        if scheduledRemindersUnchecked().count > Self.maximumScheduledReminders {
            errors.append(.tooManyScheduledReminders)
        }

        return errors
    }

    func schedule() -> Result<[ScheduledReminder], ReminderPlanValidationError> {
        if let error = validationErrors().first {
            return .failure(error)
        }

        return .success(scheduledRemindersUnchecked())
    }

    private func scheduledRemindersUnchecked() -> [ScheduledReminder] {
        var kindsByMinute: [Int: Set<ReminderKind>] = [:]

        for kind in ReminderKind.allCases {
            let setting = setting(for: kind)
            guard setting.isEnabled,
                  let firstReminderMinutes = setting.firstReminderMinutes,
                  let repeatIntervalMinutes = setting.repeatIntervalMinutes
            else {
                continue
            }

            for minute in stride(
                from: firstReminderMinutes,
                through: Self.maximumSessionMinutes,
                by: repeatIntervalMinutes
            ) {
                kindsByMinute[minute, default: []].insert(kind)
            }
        }

        return kindsByMinute
            .map { minute, kinds in
                ScheduledReminder(
                    trigger: .elapsedMinutes(minute),
                    kinds: kinds,
                    displayNames: Dictionary(uniqueKeysWithValues: kinds.map { kind in
                        let displayName = setting(for: kind).displayName
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return (kind, displayName.isEmpty ? kind.defaultDisplayName : displayName)
                    })
                )
            }
            .sorted { $0.trigger.minutes < $1.trigger.minutes }
    }
}

enum ReminderPlanValidationError: Error, Equatable {
    case noReminderEnabled
    case missingFirstReminder(ReminderKind)
    case firstReminderOutOfRange(ReminderKind)
    case missingRepeatInterval(ReminderKind)
    case repeatIntervalOutOfRange(ReminderKind)
    case displayNameTooLong(ReminderKind)
    case tooManyScheduledReminders
}

struct ScheduledReminder: Equatable, Hashable {
    let trigger: ReminderTrigger
    let kinds: Set<ReminderKind>
    let displayNames: [ReminderKind: String]

    var identifier: String {
        let kindsComponent = kinds.map(\.rawValue).sorted().joined(separator: "-")
        return "reminder-\(trigger.minutes)-\(kindsComponent)"
    }
}

struct ReminderExecutionState: Equatable {
    private(set) var deliveredReminderIDs: Set<String> = []

    mutating func markDelivered(_ reminder: ScheduledReminder) {
        deliveredReminderIDs.insert(reminder.identifier)
    }

    func nextReminder(
        in schedule: [ScheduledReminder],
        afterElapsedMinutes elapsedMinutes: Int
    ) -> ScheduledReminder? {
        schedule.first {
            $0.trigger.minutes > elapsedMinutes && !deliveredReminderIDs.contains($0.identifier)
        }
    }
}

enum SessionState: Equatable {
    case running
    case paused
    case ended
}

struct Session: Equatable {
    private(set) var state: SessionState
    let startedAt: Date
    private(set) var pausedAt: Date?
    private(set) var totalPausedSeconds: TimeInterval
    let schedule: [ScheduledReminder]
    private(set) var reminderExecutionState: ReminderExecutionState

    init(plan: ReminderPlan, startedAt: Date = .now) throws {
        state = .running
        self.startedAt = startedAt
        pausedAt = nil
        totalPausedSeconds = 0
        schedule = try plan.schedule().get()
        reminderExecutionState = ReminderExecutionState()
    }

    mutating func pause(at date: Date) {
        guard state == .running else { return }

        state = .paused
        pausedAt = date
    }

    mutating func resume(at date: Date) {
        guard state == .paused, let pausedAt else { return }

        totalPausedSeconds += max(0, date.timeIntervalSince(pausedAt))
        self.pausedAt = nil
        state = .running
    }

    mutating func end(at date: Date) {
        guard state != .ended else { return }

        if state == .paused, let pausedAt {
            totalPausedSeconds += max(0, date.timeIntervalSince(pausedAt))
            self.pausedAt = nil
        }
        state = .ended
    }

    mutating func markDelivered(_ reminder: ScheduledReminder) {
        reminderExecutionState.markDelivered(reminder)
    }

    func elapsedSeconds(at date: Date) -> TimeInterval {
        let endDate = pausedAt ?? date
        return max(0, endDate.timeIntervalSince(startedAt) - totalPausedSeconds)
    }

    func elapsedMinutes(at date: Date) -> Int {
        Int(elapsedSeconds(at: date) / 60)
    }

    func nextReminder(at date: Date) -> ScheduledReminder? {
        reminderExecutionState.nextReminder(
            in: schedule,
            afterElapsedMinutes: elapsedMinutes(at: date)
        )
    }

    func nextReminder(for kind: ReminderKind, at date: Date) -> ScheduledReminder? {
        reminderExecutionState.nextReminder(
            in: schedule.filter { $0.kinds.contains(kind) },
            afterElapsedMinutes: elapsedMinutes(at: date)
        )
    }
}
