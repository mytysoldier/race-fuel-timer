import ActivityKit
import Foundation

struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let timerStart: Date
        let pausedAt: Date?
        let reminderName: String?
        let reminderDate: Date?

        var staleDate: Date? { pausedAt == nil ? reminderDate : nil }
    }

    let sessionStartedAt: Date
}
