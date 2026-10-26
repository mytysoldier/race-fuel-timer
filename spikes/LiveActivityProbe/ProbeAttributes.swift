import ActivityKit
import Foundation

struct ProbeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var timerStart: Date
        var pausedAt: Date?
        var nextDate: Date?
        var nextNumber: Int?
        var sentAt: Date
    }
    var runID: String
}
