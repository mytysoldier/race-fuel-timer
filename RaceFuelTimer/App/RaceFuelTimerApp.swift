import SwiftUI

@main
struct RaceFuelTimerApp: App {
    @UIApplicationDelegateAdaptor(NotificationApplicationDelegate.self) private var applicationDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: Session?
    @State private var notificationsAreEnabledForCurrentSession = false
    @StateObject private var liveActivity = SessionLiveActivityController()
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
                        liveActivityUnavailable: liveActivity.status == .unavailable,
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
            .onChange(of: session) { _, updated in
                liveActivity.synchronize(session: updated)
            }
            .task(id: scenePhase) {
                liveActivity.synchronize(session: session)
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    liveActivity.synchronize(session: session)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { session?.synchronizeAfterInterruption(at: .now) }
                liveActivity.synchronize(session: session, force: phase == .active)
            }
        }
    }
}
