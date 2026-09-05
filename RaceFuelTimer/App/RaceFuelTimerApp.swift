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
                if let currentSession = session {
                    SessionTimerView(
                        session: currentSession,
                        notificationAuthorization: notificationScheduler.authorization,
                        onSessionChange: { session = $0 },
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
                    ) { _ in
                        notificationScheduler.cancelScheduledReminders()
                        notificationsAreEnabledForCurrentSession = false
                        session = nil
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
