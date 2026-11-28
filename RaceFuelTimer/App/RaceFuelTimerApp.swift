import SwiftUI

@main
struct RaceFuelTimerApp: App {
    @UIApplicationDelegateAdaptor(NotificationApplicationDelegate.self) private var applicationDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: Session?
    @State private var historySaveFailed = false
    private let historyStore = SessionHistoryStore()
    @State private var notificationsAreEnabledForCurrentSession = false
    @StateObject private var liveActivity = SessionLiveActivityController()
    @StateObject private var notificationScheduler = LocalNotificationScheduler()

    private func saveHistory() {
        guard let session, let entry = SessionHistoryEntry(session: session) else { return }
        do {
            try historyStore.save(entry)
            historySaveFailed = false
        } catch {
            historySaveFailed = true
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if let summary = session?.summary {
                    SessionSummaryView(summary: summary, historySaveFailed: historySaveFailed, onRetry: saveHistory) { session = nil }
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
                        saveHistory()
                    }
                } else {
                    HomeView {
                        ContentView { plan, shouldRequestNotificationPermission in
                            guard let newSession = try? Session(plan: plan) else { return }
                            session = newSession
                            notificationsAreEnabledForCurrentSession = shouldRequestNotificationPermission

                            let operationID = notificationScheduler.beginNotificationOperation()
                            guard shouldRequestNotificationPermission else { return }
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
            .id(session != nil)
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

private struct HomeView<TimerContent: View>: View {
    @ViewBuilder let timerContent: () -> TimerContent
    @State private var showingSafety = false
    @State private var showingPrivacy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ランの足あと").font(.largeTitle.bold())
                    Text("走った思い出を、あなただけの作品に。")
                        .foregroundStyle(.secondary)
                }
                GroupBox("ルートアート") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ヘルスケアのルート付きランから作品を作れます。")
                            .font(.subheadline)
                        NavigationLink("ルートアートを作る") { RouteArtView() }
                            .buttonStyle(.borderedProminent)
                        NavigationLink("保存した作品を見る") { ProbeSavedArtworks() }
                            .buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                NavigationLink("補給タイマーを使う", destination: timerContent)
                    .buttonStyle(.bordered)
                NavigationLink("ランの履歴") { SessionHistoryView() }
                    .buttonStyle(.bordered)
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("情報", systemImage: "info.circle") {
                    Button("安全上の注意") { showingSafety = true }
                    Button("プライバシーとサポート") { showingPrivacy = true }
                }
            }
        }
        .sheet(isPresented: $showingSafety) {
            SafetyInformationView(isOnboarding: false, onCompleteOnboarding: {})
        }
        .sheet(isPresented: $showingPrivacy) { PrivacyInformationView() }
    }
}
