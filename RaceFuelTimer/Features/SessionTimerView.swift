import SwiftUI

struct SessionTimerView: View {
    @Binding var session: Session
    let onEnd: () -> Void

    @State private var isEndConfirmationPresented = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsedSeconds = session.elapsedSeconds(at: context.date)
            let nextReminder = session.nextReminder(at: context.date)

            VStack(spacing: 28) {
                Text(session.state == .paused ? "一時停止中" : "実行中")
                    .font(.headline)
                    .foregroundStyle(session.state == .paused ? .orange : .green)

                VStack(spacing: 8) {
                    Text("経過時間")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(formattedTime(elapsedSeconds))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel("経過時間 \\(formattedTime(elapsedSeconds))")
                }

                nextReminderSection(nextReminder, at: context.date)

                Spacer()

                Button(session.state == .paused ? "再開" : "一時停止") {
                    if session.state == .paused {
                        session.resume(at: .now)
                    } else {
                        session.pause(at: .now)
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
            }
            .padding()
        }
        .navigationTitle("ランニング中")
        .navigationBarTitleDisplayMode(.inline)
        .alert("セッションを終了しますか？", isPresented: $isEndConfirmationPresented) {
            Button("キャンセル", role: .cancel) {}
            Button("終了", role: .destructive) {
                session.end(at: .now)
                onEnd()
            }
        } message: {
            Text("タイマーを終了します。この操作は取り消せません。")
        }
    }

    @ViewBuilder
    private func nextReminderSection(_ reminder: ScheduledReminder?, at date: Date) -> some View {
        GroupBox("次の予定") {
            if let reminder {
                VStack(alignment: .leading, spacing: 8) {
                    Text(reminder.displayNames.values.sorted().joined(separator: "・"))
                        .font(.title2.bold())
                    Text("開始から \\(reminder.trigger.minutes) 分")
                    Text("あと \\(remainingTime(until: reminder, at: date))")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            } else {
                Text("このセッションに残っている予定はありません。")
                    .foregroundStyle(.secondary)
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
