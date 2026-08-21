import SwiftUI

@main
struct RaceFuelTimerApp: App {
    @UIApplicationDelegateAdaptor(NotificationApplicationDelegate.self) private var applicationDelegate
    @State private var session: Session?
    @StateObject private var notificationScheduler = LocalNotificationScheduler()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                // switch でも分岐できるが、Optional の Binding<Session> を安全に取り出す目的が明確な if let を使う。
                if let sessionBinding = Binding($session) {
                    SessionTimerView(
                        session: sessionBinding,
                        notificationAuthorization: notificationScheduler.authorization,
                        onPause: {
                            notificationScheduler.cancelScheduledReminders()
                        },
                        onResume: { session in
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
                        session = nil
                    }
                } else {
                    ContentView { plan, shouldRequestNotificationPermission in
                        guard let newSession = try? Session(plan: plan) else { return }
                        session = newSession

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
        }
    }
}
