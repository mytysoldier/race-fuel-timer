import Foundation

struct SessionActivitySnapshot: Equatable {
    let sessionStartedAt: Date
    let content: RunActivityAttributes.ContentState

    init?(session: Session, at date: Date) {
        guard session.state != .ended else { return nil }
        let timerStart = session.startedAt.addingTimeInterval(session.totalPausedSeconds)
        let reminder = session.nextReminder(at: date)
        sessionStartedAt = session.startedAt
        content = .init(
            timerStart: timerStart,
            pausedAt: session.pausedAt,
            reminderName: reminder.map { $0.displayNames[.hydration] ?? "補給の時間です" },
            reminderDate: reminder.map { timerStart.addingTimeInterval(TimeInterval($0.trigger.minutes * 60)) }
        )
    }
}
