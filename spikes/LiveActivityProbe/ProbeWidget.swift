import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ProbeWidgets: WidgetBundle {
    var body: some Widget { ProbeWidget() }
}

struct ProbeWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProbeAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text("Live Activity 検証・本番用ではありません").font(.caption)
                HStack {
                    Text(context.state.pausedAt == nil ? "実行中" : "一時停止")
                    Spacer()
                    elapsed(context.state)
                }.font(.title2.monospacedDigit())
                if let date = context.state.nextDate, let number = context.state.nextNumber {
                    Text("送信した予定 #\(number)・\(date.formatted(date: .omitted, time: .standard))")
                    if context.state.pausedAt == nil {
                        Text(timerInterval: context.state.sentAt...max(context.state.sentAt, date), countsDown: true)
                            .monospacedDigit()
                    } else {
                        Text("残り \(max(0, Int(date.timeIntervalSince(context.state.pausedAt!)))) 秒（停止中）")
                    }
                } else {
                    Text("次の予定なし")
                }
                if context.isStale {
                    Text("更新期限を通過・最新の予定はアプリで確認").font(.caption).foregroundStyle(.orange)
                }
                Text("最終送信 \(context.state.sentAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
            }.padding().activityBackgroundTint(.black).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("検証") }
                DynamicIslandExpandedRegion(.trailing) { elapsed(context.state) }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.isStale ? "予定の更新期限を通過" : "送信した予定 #\(context.state.nextNumber ?? 0)")
                }
            } compactLeading: {
                Text(context.state.pausedAt == nil ? "検" : "停")
            } compactTrailing: {
                elapsed(context.state)
            } minimal: {
                Text("検")
            }
        }
    }

    @ViewBuilder
    private func elapsed(_ state: ProbeAttributes.ContentState) -> some View {
        if let pausedAt = state.pausedAt {
            Text(Duration.seconds(max(0, pausedAt.timeIntervalSince(state.timerStart)))
                .formatted(.time(pattern: .hourMinuteSecond)))
        } else {
            Text(state.timerStart, style: .timer)
        }
    }
}
