import Foundation

extension ReminderPlanValidationError {
    var message: String {
        switch self {
        case .noReminderEnabled:
            "給水または補給・ジェルのどちらかを有効にしてください。"
        case let .missingFirstReminder(kind):
            "\(kind.defaultDisplayName)の最初の通知を整数で入力してください。"
        case let .firstReminderOutOfRange(kind):
            "\(kind.defaultDisplayName)の最初の通知は 5〜240 分にしてください。"
        case let .missingRepeatInterval(kind):
            "\(kind.defaultDisplayName)の繰り返し間隔を整数で入力してください。"
        case let .repeatIntervalOutOfRange(kind):
            "\(kind.defaultDisplayName)の繰り返し間隔は 5〜240 分にしてください。"
        case let .displayNameTooLong(kind):
            "\(kind.defaultDisplayName)の通知表示名は 30 文字以内にしてください。"
        case .tooManyScheduledReminders:
            "通知は1回のセッションで60件までです。間隔を長くしてください。"
        }
    }
}
