import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RunActivityWidgets: WidgetBundle {
    var body: some Widget { RunActivityWidget() }
}

struct RunActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(context.state.pausedAt == nil ? "ランニング中" : "一時停止中", systemImage: "figure.run")
                        .font(.headline)
                    Spacer()
                    elapsed(context.state).font(.title2.bold().monospacedDigit())
                }
                reminder(context)
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.pausedAt == nil ? "実行中" : "一時停止中", systemImage: "figure.run")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsed(context.state).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) { reminder(context) }
            } compactLeading: {
                Image(systemName: context.state.pausedAt == nil ? "figure.run" : "pause.fill")
            } compactTrailing: {
                elapsed(context.state).monospacedDigit().frame(maxWidth: 80)
            } minimal: {
                Image(systemName: context.state.pausedAt == nil ? "figure.run" : "pause.fill")
            }
        }
    }

    @ViewBuilder
    private func elapsed(_ state: RunActivityAttributes.ContentState) -> some View {
        if let pausedAt = state.pausedAt {
            Text(Duration.seconds(max(0, pausedAt.timeIntervalSince(state.timerStart)))
                .formatted(.time(pattern: .hourMinuteSecond)))
        } else {
            Text(state.timerStart, style: .timer)
        }
    }

    @ViewBuilder
    private func reminder(_ context: ActivityViewContext<RunActivityAttributes>) -> some View {
        let state = context.state
        if let date = state.reminderDate {
            if context.isStale && state.pausedAt == nil {
                Label("最新の補給予定はアプリで確認", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("補給予定（更新時点）").font(.caption).foregroundStyle(.secondary)
                    Text(state.reminderName ?? "補給の時間です").font(.headline).lineLimit(2)
                    HStack {
                        Text(date, style: .time)
                        Text("・あと")
                        if let pausedAt = state.pausedAt {
                            Text(Duration.seconds(max(0, date.timeIntervalSince(pausedAt)))
                                .formatted(.time(pattern: .hourMinuteSecond)))
                        } else {
                            Text(timerInterval: state.timerStart...max(state.timerStart, date), countsDown: true)
                        }
                    }.font(.subheadline).monospacedDigit()
                }
            }
        } else {
            Text("次の補給予定はありません").font(.subheadline)
        }
    }
}
