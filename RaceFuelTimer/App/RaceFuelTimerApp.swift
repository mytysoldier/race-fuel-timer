import SwiftUI

@main
struct RaceFuelTimerApp: App {
    @UIApplicationDelegateAdaptor(NotificationApplicationDelegate.self) private var applicationDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: Session?
    @State private var notificationsAreEnabledForCurrentSession = false
    @StateObject private var notificationScheduler = LocalNotificationScheduler()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if let summary = session?.summary {
                    SessionSummaryView(summary: summary) { session = nil }
                } else if let currentSession = session {
                    SessionTimerView(
                        session: currentSession,
                        notificationAuthorization: notificationScheduler.authorization,
                        onSessionChange: { session = $0 },
                        onRecord: { reminderID, result in
                            guard var updatedSession = session,
                                  updatedSession.record(result, reminderID: reminderID, at: .now) else { return }
                            session = updatedSession
                            notificationScheduler.cancelReminder(reminderID)
                        },
                        onPause: {
                            notificationScheduler.cancelScheduledReminders()
                        },
                        onResume: { session in
                            guard notificationsAreEnabledForCurrentSession else { return }
                            let operationID = notificationScheduler.beginNotificationOperation()
                            Task {
                                await notificationScheduler.scheduleReminders(
                                    for: session,
                                    operationID: operationID
                                )
                            }
                        }
                    ) { endedSession in
                        notificationScheduler.cancelScheduledReminders()
                        notificationsAreEnabledForCurrentSession = false
                        session = endedSession
                    }
                } else {
                    ContentView { plan, shouldRequestNotificationPermission in
                        guard let newSession = try? Session(plan: plan) else { return }
                        session = newSession
                        notificationsAreEnabledForCurrentSession = shouldRequestNotificationPermission

                        guard shouldRequestNotificationPermission else { return }
                        let operationID = notificationScheduler.beginNotificationOperation()
                        Task {
                            await notificationScheduler.requestAuthorizationAndSchedule(
                                for: newSession,
                                operationID: operationID
                            )
                        }
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                session?.synchronizeAfterInterruption(at: .now)
            }
        }
    }
}
