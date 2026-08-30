import SwiftUI

struct EditablePlan: Equatable {
    static let defaultMessage = "補給の時間です"
    var isReminderEnabled: Bool
    var intervalMinutes: Int
    var notificationEndMinutes: Int
    var notificationMessage: String

    init(savedPlan: SavedPlan) {
        let setting = savedPlan.hydration.isEnabled ? savedPlan.hydration : savedPlan.fuel
        isReminderEnabled = setting.isEnabled
        intervalMinutes = Self.normalizedInterval(setting.repeatIntervalMinutes)
        notificationEndMinutes = Self.normalizedEnd(savedPlan.notificationEndMinutes, intervalMinutes: intervalMinutes)
        let message = setting.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        notificationMessage = message.isEmpty ? Self.defaultMessage : message
    }

    init() {
        isReminderEnabled = true
        intervalMinutes = 20
        notificationEndMinutes = 240
        notificationMessage = Self.defaultMessage
    }

    static func normalizedInterval(_ value: Int?) -> Int {
        guard let value, ReminderPlan.allowedReminderMinutes.contains(value), value.isMultiple(of: 10) else { return 20 }
        return value
    }

    static func normalizedEnd(_ value: Int, intervalMinutes: Int) -> Int {
        let options = notificationEndOptions(intervalMinutes: intervalMinutes)
        return options.contains(value) ? value : 240
    }

    static func notificationEndOptions(intervalMinutes: Int) -> [Int] {
        Array(stride(from: 30, through: 1440, by: 30)).filter {
            $0 >= intervalMinutes && $0 / intervalMinutes <= ReminderPlan.maximumScheduledReminders
        }
    }
}

struct ContentView: View {
    private static let quickIntervals = [10, 20, 30, 40]
    private static let quickEndMinutes = [120, 240, 360, 480]

    let onStart: (ReminderPlan, Bool) -> Void
    private let planStore: ReminderPlanStore
    @State private var editablePlan: EditablePlan
    @State private var didRecoverSavedPlan: Bool
    @State private var isNotificationSettingsPresented = false
    @State private var isNotificationExplanationPresented = false
    @State private var isSafetyInformationPresented = false
    @State private var isPrivacyInformationPresented = false
    @State private var isResetConfirmationPresented = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasChosenNotificationUsage") private var hasChosenNotificationUsage = false
    @AppStorage("shouldUseNotifications") private var shouldUseNotifications = true

    init(onStart: @escaping (ReminderPlan, Bool) -> Void = { _, _ in }, planStore: ReminderPlanStore = .init()) {
        self.onStart = onStart
        self.planStore = planStore
        let result = planStore.loadWithRecoveryStatus()
        _editablePlan = State(initialValue: result.plan.map(EditablePlan.init(savedPlan:)) ?? .init())
        _didRecoverSavedPlan = State(initialValue: result.didRecover)
    }

    private var plan: ReminderPlan {
        ReminderPlan(
            hydration: .init(
                isEnabled: editablePlan.isReminderEnabled,
                firstReminderMinutes: editablePlan.intervalMinutes,
                repeatIntervalMinutes: editablePlan.intervalMinutes,
                displayName: notificationMessage
            ),
            fuel: .init(isEnabled: false),
            notificationEndMinutes: editablePlan.notificationEndMinutes
        )
    }

    private var notificationMessage: String {
        let message = editablePlan.notificationMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? EditablePlan.defaultMessage : message
    }

    private var notificationEndOptions: [Int] {
        EditablePlan.notificationEndOptions(intervalMinutes: editablePlan.intervalMinutes)
    }

    private var savedPlan: SavedPlan? {
        SavedPlan(selectedDistanceKilometers: 10, hydration: plan.hydration, fuel: plan.fuel, notificationEndMinutes: plan.notificationEndMinutes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ランニング補給タイマー").font(.largeTitle.bold())
                    Text("補給ペースと、通知を止める予定を選んで始めよう。").foregroundStyle(.secondary)
                }

                GroupBox("補給リマインド") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("補給を通知する", isOn: $editablePlan.isReminderEnabled)
                        if editablePlan.isReminderEnabled {
                            Text("どのくらいの間隔で知らせる？").font(.subheadline.weight(.medium))
                            quickChoiceRow(values: Self.quickIntervals, selected: editablePlan.intervalMinutes, title: { "\($0)分" }, onSelect: selectInterval)
                            Text("いつまで知らせる？").font(.subheadline.weight(.medium))
                            quickChoiceRow(values: Self.quickEndMinutes, selected: editablePlan.notificationEndMinutes, title: formattedDuration, onSelect: selectNotificationEnd)
                            Text(notificationSummary).font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("通知しません。タイマーだけを使えます。").font(.footnote).foregroundStyle(.secondary)
                        }
                        Button {
                            isNotificationSettingsPresented = true
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("通知を調整")
                                    Text("間隔・終了予定・メッセージを細かく指定").font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "slider.horizontal.3") }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if didRecoverSavedPlan {
                    Label("保存した設定を新しい初期値へ戻しました。", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Text("通知は目安です。体調や補給計画に合わせて設定してください。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Button("このプランで開始") { startPlan() }
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).padding().background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("情報", systemImage: "info.circle") {
                    Button("安全上の注意") { isSafetyInformationPresented = true }
                    Button("プライバシーとサポート") { isPrivacyInformationPresented = true }
                }
            }
        }
        .onChange(of: editablePlan.intervalMinutes) { _, _ in
            if !notificationEndOptions.contains(editablePlan.notificationEndMinutes) {
                editablePlan.notificationEndMinutes = notificationEndOptions.last ?? 240
            }
        }
        .onChange(of: savedPlan) { _, savedPlan in
            if let savedPlan { planStore.save(savedPlan) }
        }
        .onAppear { isSafetyInformationPresented = !hasCompletedOnboarding }
        .alert("通知を使って開始しますか？", isPresented: $isNotificationExplanationPresented) {
            Button("通知なしで開始", role: .cancel) { hasChosenNotificationUsage = true; shouldUseNotifications = false; onStart(plan, false) }
            Button("通知を許可") { hasChosenNotificationUsage = true; shouldUseNotifications = true; onStart(plan, true) }
        } message: { Text("補給の予定をローカル通知でお知らせします。") }
        .sheet(isPresented: $isSafetyInformationPresented) {
            SafetyInformationView(isOnboarding: !hasCompletedOnboarding, onCompleteOnboarding: {
                hasCompletedOnboarding = true
                isSafetyInformationPresented = false
            })
        }
        .sheet(isPresented: $isPrivacyInformationPresented) { PrivacyInformationView() }
        .sheet(isPresented: $isNotificationSettingsPresented) {
            NavigationStack {
                notificationSettingsView.navigationTitle("通知を調整").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { isNotificationSettingsPresented = false } } }
            }
        }
    }

    private var notificationSettingsView: some View {
        Form {
            Section("通知のタイミング") {
                Picker("通知間隔", selection: $editablePlan.intervalMinutes) {
                    ForEach(Array(stride(from: 10, through: 240, by: 10)), id: \.self) { Text("\($0)分ごと").tag($0) }
                }
                Picker("通知を止める予定", selection: $editablePlan.notificationEndMinutes) {
                    ForEach(notificationEndOptions, id: \.self) { Text("\(formattedDuration($0))後").tag($0) }
                }
                Text(notificationSummary).font(.footnote).foregroundStyle(.secondary)
            }
            Section("通知メッセージ") {
                TextField("補給の時間です", text: $editablePlan.notificationMessage)
                    .onChange(of: editablePlan.notificationMessage) { _, message in
                        editablePlan.notificationMessage = String(message.prefix(30))
                    }
                Text("通知に表示する短いメッセージです。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("通知プレビュー") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ランニング補給タイマー").font(.subheadline.weight(.semibold))
                    Text(notificationMessage)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("通知プレビュー。ランニング補給タイマー。\(notificationMessage)")
            }
            Section {
                Toggle("通知を使う", isOn: Binding(get: { shouldUseNotifications }, set: {
                    shouldUseNotifications = $0
                    hasChosenNotificationUsage = true
                }))
                Button("設定を初期化", role: .destructive) { isResetConfirmationPresented = true }
            }
        }
        .confirmationDialog("設定を初期化しますか？", isPresented: $isResetConfirmationPresented) {
            Button("初期化", role: .destructive) { planStore.reset(); editablePlan = .init(); didRecoverSavedPlan = false }
        } message: { Text("補給リマインドの設定を初期値へ戻します。") }
    }

    private var notificationSummary: String {
        "開始\(editablePlan.intervalMinutes)分後から\(editablePlan.intervalMinutes)分ごと。\(formattedDuration(editablePlan.notificationEndMinutes))後に通知を止めます。"
    }

    private func quickChoiceRow(values: [Int], selected: Int, title: @escaping (Int) -> String, onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(values, id: \.self) { value in
                if value == selected {
                    Button(title(value)) { onSelect(value) }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                } else {
                    Button(title(value)) { onSelect(value) }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func selectInterval(_ minutes: Int) { editablePlan.intervalMinutes = minutes }
    private func selectNotificationEnd(_ minutes: Int) { editablePlan.notificationEndMinutes = minutes }

    private func formattedDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remaining = minutes % 60
        if remaining == 0 { return "\(hours)時間" }
        if hours == 0 { return "\(remaining)分" }
        return "\(hours)時間\(remaining)分"
    }

    private func startPlan() {
        guard plan.validationErrors().isEmpty else { return }
        if hasChosenNotificationUsage {
            onStart(plan, shouldUseNotifications && editablePlan.isReminderEnabled)
        } else {
            isNotificationExplanationPresented = true
        }
    }
}
