import SwiftUI

struct SessionTimerView: View {
    let session: Session
    let notificationAuthorization: LocalNotificationAuthorization
    let onSessionChange: (Session) -> Void
    let onPause: () -> Void
    let onResume: (Session) -> Void
    let onEnd: (Session) -> Void

    @State private var isEndConfirmationPresented = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsedSeconds = session.elapsedSeconds(at: context.date)
            let nextReminders = ReminderKind.allCases.compactMap { kind in
                session.nextReminder(for: kind, at: context.date).map { (kind, $0) }
            }

            ScrollView {
                VStack(spacing: 28) {
                    Text(session.state == .paused ? "一時停止中" : "実行中")
                        .font(.headline)
                        .foregroundStyle(session.state == .paused ? .orange : .green)
                        .accessibilityLabel("セッションの状態：\(session.state == .paused ? "一時停止中" : "実行中")")

                    VStack(spacing: 8) {
                        Text("経過時間")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(formattedTime(elapsedSeconds))
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .accessibilityLabel("経過時間 \(formattedTime(elapsedSeconds))")
                    }

                    nextReminderSection(nextReminders, at: context.date)

                    notificationStatusSection

                    Text("画面ロック・アプリ切替中も経過時間は復帰時に再計算します。アプリを終了した場合、実行中セッションは復元されません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 12)

                    Button(session.state == .paused ? "再開" : "一時停止") {
                        var updatedSession = session
                        if session.state == .paused {
                            if updatedSession.resume(at: .now) {
                                onSessionChange(updatedSession)
                                onResume(updatedSession)
                            }
                        } else {
                            updatedSession.pause(at: .now)
                            onSessionChange(updatedSession)
                            onPause()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint(session.state == .paused ? "タイマーと予定を再開します" : "タイマーと予定を止めます")

                    Button("終了", role: .destructive) {
                        isEndConfirmationPresented = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("タイマーを終了し、設定画面へ戻ります。終了後は再開できません")
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .contentMargins(.vertical, 16, for: .scrollContent)
        }
        .navigationTitle("ランニング中")
        .navigationBarTitleDisplayMode(.inline)
        .alert("セッションを終了しますか？", isPresented: $isEndConfirmationPresented) {
            Button("キャンセル", role: .cancel) {}
            Button("終了", role: .destructive) {
                var endedSession = session
                endedSession.end(at: .now)
                onEnd(endedSession)
            }
        } message: {
            Text("タイマーを終了します。この操作は取り消せません。")
        }
    }

    @ViewBuilder
    private var notificationStatusSection: some View {
        switch notificationAuthorization {
        case .denied:
            GroupBox("通知がオフです") {
                Text("タイマーと画面上の次回予定は使えます。通知を受け取るには、iPhoneの「設定」>「通知」>「ランニング補給タイマー」で許可してから、次回のセッションを開始してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .unavailable:
            GroupBox("通知を予約できませんでした") {
                Text("タイマーと画面上の次回予定は継続しています。iPhoneの通知設定を確認してから、次回のセッションを開始してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .notRequested, .authorized:
            EmptyView()
        }
    }

    @ViewBuilder
    private func nextReminderSection(_ reminders: [(ReminderKind, ScheduledReminder)], at date: Date) -> some View {
        GroupBox("次の予定") {
            if reminders.isEmpty {
                Text("このセッションに次の給水・補給予定はありません。設定した予定をすべて過ぎたか、通知を設定していません。")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("次の予定はありません。設定した予定をすべて過ぎたか、通知を設定していません")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(reminders, id: \.0) { kind, reminder in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reminder.displayNames[kind] ?? kind.defaultDisplayName)
                                .font(.title2.bold())
                            Text("開始から \(reminder.trigger.minutes) 分")
                            Text("あと \(remainingTime(until: reminder, at: date))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func remainingTime(until reminder: ScheduledReminder, at date: Date) -> String {
        let remainingSeconds = max(
            0,
            TimeInterval(reminder.trigger.minutes * 60) - session.elapsedSeconds(at: date)
        )
        return formattedTime(remainingSeconds)
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }
}
