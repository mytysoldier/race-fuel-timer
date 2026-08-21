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
final class LocalNotificationScheduler: ObservableObject {
    @Published private(set) var authorization: LocalNotificationAuthorization = .notRequested

    private let center = UNUserNotificationCenter.current()
    private var scheduledNotificationIDs: [String] = []
    private var activeOperationID = UUID()

    func beginNotificationOperation() -> UUID {
        let operationID = UUID()
        activeOperationID = operationID
        removeScheduledReminders()
        return operationID
    }

    func requestAuthorizationAndSchedule(for session: Session, operationID: UUID) async {
        let settings = await center.notificationSettings()
        guard isActive(operationID) else { return }

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorization = .authorized
            await scheduleReminders(for: session, operationID: operationID)
        case .notDetermined:
            do {
                let isGranted = try await center.requestAuthorization(options: [.alert, .sound])
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

        for reminder in session.schedule {
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
                if isActive(operationID) {
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
        if kinds == [.hydration] {
            "給水の時間です"
        } else if kinds == [.fuel] {
            "補給・ジェルの時間です"
        } else {
            "給水・補給の時間です"
        }
    }

    var notificationBody: String {
        let names = kinds
            .sorted { $0.rawValue < $1.rawValue }
            .map { displayNames[$0] ?? $0.defaultDisplayName }
            .joined(separator: "・")
        return "\(names)の予定です。体調や製品表示を優先してください。"
    }
}
