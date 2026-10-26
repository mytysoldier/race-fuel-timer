import ActivityKit
import SwiftUI
import UserNotifications

@main
struct ProbeApp: App {
    @StateObject private var model = ProbeModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    Section("Issue #75 専用・本番アプリとは別") {
                        Text("サーバー・バックグラウンド処理なし。アプリが前面にある時だけ予定を再送信します。")
                        Picker("間隔", selection: $model.interval) {
                            Text("1分 × 3回（短時間検証）").tag(60.0)
                            Text("10分 × 3回（通常間隔）").tag(600.0)
                            Text("3時間 × 3回（8時間制限検証）").tag(10800.0)
                        }
                        Toggle("補給予定あり", isOn: $model.hasSchedule)
                        Toggle("ローカル通知も予約", isOn: $model.notifications)
                        Text("長時間検証は実時間で8時間超必要。時刻変更では代用しません。")
                    }.disabled(model.running || model.busy)
                    Section("操作") {
                        Text(model.running ? (model.pausedAt == nil ? "実行中" : "一時停止") : "未開始／終了")
                        if model.running {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text("経過 \(Int(model.elapsed(at: context.date))) 秒")
                                Text("アプリの次の予定 #\(model.nextNumber(at: context.date) ?? 0)（0は予定なし）")
                            }
                        }
                        Text("Live Activity: \(model.activityStatus)")
                        Button("開始") { Task { await model.start() } }.disabled(model.running || model.busy)
                        Button(model.pausedAt == nil ? "一時停止" : "再開") {
                            Task { await model.togglePause() }
                        }.disabled(!model.running || model.busy)
                        Button("終了・表示と通知を削除", role: .destructive) {
                            Task { await model.end() }
                        }.disabled(model.busy)
                        Text("ホームへ移動→ロックして、1分・2分・3分後の通知と予定番号を比較してください。アプリへ戻ると再送信されます。")
                    }
                    Section("記録（前面での送信履歴）") {
                        ShareLink("検証ログを共有", item: model.logText)
                        Text(model.logText).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }.navigationTitle("Live Activity 検証")
                .task { await model.prepare() }
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        if phase == .active { await model.refreshIfNeeded() }
                    }
                }
                .onChange(of: phase) { _, value in
                    model.log("scene=\(value)")
                    if value == .active { Task { await model.refreshIfNeeded() } }
                }
            }
        }
    }
}

@MainActor
final class ProbeModel: ObservableObject {
    @Published var interval: TimeInterval = 60
    @Published var hasSchedule = true
    @Published var notifications = false
    @Published var running = false
    @Published var busy = false
    @Published var pausedAt: Date?
    @Published var activityStatus = "未開始"
    @Published var logText = ""
    private var activity: Activity<ProbeAttributes>?
    private var startedAt = Date.now
    private var pausedSeconds: TimeInterval = 0
    private var lastNumber: Int?
    private var prepared = false
    private let center = UNUserNotificationCenter.current()

    func log(_ text: String) {
        logText += "\(Date.now.formatted(date: .numeric, time: .standard)) \(text)\n"
    }

    func prepare() async {
        guard !prepared else { return }
        prepared = true
        log("\(UIDevice.current.model) / iOS \(UIDevice.current.systemVersion) / build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?")")
        // この検証アプリもセッションを永続化しない。再起動時は残留表示を終了する。
        await end()
    }

    func start() async {
        guard !busy, !running else { return }
        busy = true
        defer { busy = false }
        if notifications {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                log("通知許可=\(granted)")
            } catch { log("通知許可エラー=\(error)") }
        }
        startedAt = .now
        pausedAt = nil
        pausedSeconds = 0
        running = true
        let state = snapshot(at: .now)
        lastNumber = state.nextNumber
        log("開始 interval=\(interval) schedule=\(hasSchedule) notifications=\(notifications)")
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                activity = try Activity.request(
                    attributes: ProbeAttributes(runID: UUID().uuidString),
                    content: ActivityContent(state: state, staleDate: state.nextDate), pushType: nil
                )
                activityStatus = "開始成功"
                log("Activity開始 #\(state.nextNumber ?? 0)")
            } catch {
                activityStatus = "開始失敗・アプリ内は継続"
                log("Activity開始失敗=\(error)")
            }
        } else {
            activityStatus = "無効・アプリ内は継続"
            log("Live Activityが設定で無効")
        }
        await scheduleNotifications()
    }

    func togglePause() async {
        guard running, !busy else { return }
        busy = true
        defer { busy = false }
        if let pause = pausedAt {
            pausedSeconds += Date.now.timeIntervalSince(pause)
            pausedAt = nil
            log("再開")
            await scheduleNotifications()
        } else {
            pausedAt = .now
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
            log("一時停止・通知取消")
        }
        await send(snapshot(at: .now))
    }

    func refreshIfNeeded() async {
        guard running, !busy else { return }
        busy = true
        defer { busy = false }
        let state = snapshot(at: .now)
        if state.nextNumber != lastNumber { await send(state) }
    }

    func elapsed(at now: Date) -> TimeInterval {
        max(0, (pausedAt ?? now).timeIntervalSince(startedAt) - pausedSeconds)
    }

    func nextNumber(at now: Date) -> Int? { snapshot(at: now).nextNumber }

    private func send(_ state: ProbeAttributes.ContentState) async {
        lastNumber = state.nextNumber
        guard let activity else { return }
        await activity.update(ActivityContent(state: state, staleDate: pausedAt == nil ? state.nextDate : nil))
        activityStatus = "\(activity.activityState)"
        log("送信 #\(state.nextNumber ?? 0) pause=\(pausedAt != nil)")
    }

    private func snapshot(at now: Date) -> ProbeAttributes.ContentState {
        let effectiveStart = startedAt.addingTimeInterval(pausedSeconds)
        let elapsed = (pausedAt ?? now).timeIntervalSince(effectiveStart)
        let number = max(1, Int(elapsed / interval) + 1)
        let next = hasSchedule && number <= 3 ? number : nil
        return .init(timerStart: effectiveStart, pausedAt: pausedAt,
                     nextDate: next.map { effectiveStart.addingTimeInterval(Double($0) * interval) },
                     nextNumber: next, sentAt: now)
    }

    private func scheduleNotifications() async {
        center.removeAllPendingNotificationRequests()
        guard notifications, hasSchedule else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            log("通知なし・タイマー継続")
            return
        }
        for number in 1...3 {
            let due = startedAt.addingTimeInterval(pausedSeconds + Double(number) * interval)
            let seconds = due.timeIntervalSinceNow
            guard seconds > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Live Activity 検証 #\(number)"
            content.body = "ロック画面の送信済み予定番号・残り時間と比較してください"
            content.sound = .default
            do {
                try await center.add(UNNotificationRequest(identifier: "probe-\(number)", content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
            } catch { log("通知予約失敗=\(error)") }
        }
    }

    func end() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        running = false
        pausedAt = nil
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        for existing in Activity<ProbeAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        activityStatus = "終了"
        log("終了・既存Activityと通知を削除")
    }
}
