import Combine
import Foundation
import UIKit
import UserNotifications

enum LocalNotificationAuthorization: Equatable {
    case notRequested
    case authorized
    case denied
    case unavailable
}

@MainActor
protocol NotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

@MainActor
private struct SystemNotificationCenterClient: NotificationCenterClient {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

@MainActor
final class LocalNotificationScheduler: ObservableObject {
    @Published private(set) var authorization: LocalNotificationAuthorization = .notRequested

    private let center: any NotificationCenterClient
    private var scheduledNotificationIDs: [String] = []
    private var activeOperationID = UUID()
    private var recordedReminderIDs: Set<String> = []

    init(center: (any NotificationCenterClient)? = nil) {
        self.center = center ?? SystemNotificationCenterClient()
    }

    func beginNotificationOperation() -> UUID {
        let operationID = UUID()
        activeOperationID = operationID
        removeScheduledReminders()
        recordedReminderIDs.removeAll()
        return operationID
    }

    func requestAuthorizationAndSchedule(for session: Session, operationID: UUID) async {
        let status = await center.authorizationStatus()
        guard isActive(operationID) else { return }

        switch status {
        case .authorized, .provisional, .ephemeral:
            authorization = .authorized
            await scheduleReminders(for: session, operationID: operationID)
        case .notDetermined:
            do {
                let isGranted = try await center.requestAuthorization()
                guard isActive(operationID) else { return }
                authorization = isGranted ? .authorized : .denied
                if isGranted {
                    await scheduleReminders(for: session, operationID: operationID)
                }
            } catch {
                if isActive(operationID) {
                    authorization = .unavailable
                }
            }
        case .denied:
            authorization = .denied
        @unknown default:
            authorization = .unavailable
        }
    }

    func scheduleReminders(for session: Session, operationID: UUID) async {
        guard isActive(operationID), authorization == .authorized else { return }

        let now = Date.now
        let elapsedSeconds = session.elapsedSeconds(at: now)

        for reminder in session.pendingReminders(at: now) {
            guard isActive(operationID) else { return }
            guard !recordedReminderIDs.contains(reminder.identifier) else { continue }
            let remainingSeconds = TimeInterval(reminder.trigger.minutes * 60) - elapsedSeconds
            guard remainingSeconds > 0 else { continue }

            let content = notificationContent(for: reminder)
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, remainingSeconds),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "\(reminder.identifier)-\(operationID.uuidString)",
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
                if isActive(operationID), !recordedReminderIDs.contains(reminder.identifier) {
                    scheduledNotificationIDs.append(request.identifier)
                } else {
                    center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                }
            } catch {
                // 予約失敗はタイマーの状態遷移に影響させない。
                if isActive(operationID) {
                    authorization = .unavailable
                }
            }
        }
    }

    func cancelReminder(_ reminderID: String) {
        recordedReminderIDs.insert(reminderID)
        let requestID = "\(reminderID)-\(activeOperationID.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        scheduledNotificationIDs.removeAll { $0 == requestID }
    }

    func cancelScheduledReminders() {
        activeOperationID = UUID()
        removeScheduledReminders()
    }

    private func isActive(_ operationID: UUID) -> Bool {
        activeOperationID == operationID
    }

    private func removeScheduledReminders() {
        center.removePendingNotificationRequests(withIdentifiers: scheduledNotificationIDs)
        scheduledNotificationIDs.removeAll()
    }

    private func notificationContent(for reminder: ScheduledReminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = reminder.notificationTitle
        content.body = reminder.notificationBody
        // 通常通知の音・振動は、iOSの通知設定、サイレント、Focusに従う。
        content.sound = .default
        return content
    }
}

final class NotificationApplicationDelegate: NSObject, UIApplicationDelegate {
    private let notificationDelegate = ForegroundNotificationDelegate()

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        return true
    }
}

final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

extension ScheduledReminder {
    var notificationTitle: String {
        "ランニング補給タイマー"
    }

    var notificationBody: String {
        displayNames[.hydration] ?? "補給の時間です"
    }
}
