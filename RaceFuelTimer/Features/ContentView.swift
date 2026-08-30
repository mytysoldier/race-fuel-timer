import SwiftUI

struct EditablePlan: Equatable {
    var selectedDistance: PlannedDistance
    var customDistance: String
    var hydrationIsEnabled: Bool
    var hydrationFirstReminder: String
    var hydrationRepeatInterval: String
    var hydrationDisplayName: String
    var fuelIsEnabled: Bool
    var fuelFirstReminder: String
    var fuelRepeatInterval: String
    var fuelDisplayName: String

    init(savedPlan: SavedPlan) {
        let distance = PlannedDistance.from(savedDistanceKilometers: savedPlan.selectedDistanceKilometers)
        selectedDistance = distance
        customDistance = distance == .custom
            ? DistanceParser.text(from: savedPlan.selectedDistanceKilometers)
            : ""
        hydrationIsEnabled = savedPlan.hydration.isEnabled
        hydrationFirstReminder = savedPlan.hydration.firstReminderMinutes.map(String.init) ?? ""
        hydrationRepeatInterval = savedPlan.hydration.repeatIntervalMinutes.map(String.init) ?? ""
        hydrationDisplayName = savedPlan.hydration.displayName
        fuelIsEnabled = savedPlan.fuel.isEnabled
        fuelFirstReminder = savedPlan.fuel.firstReminderMinutes.map(String.init) ?? ""
        fuelRepeatInterval = savedPlan.fuel.repeatIntervalMinutes.map(String.init) ?? ""
        fuelDisplayName = savedPlan.fuel.displayName
    }

    init(preset: ReminderPlan) {
        selectedDistance = .tenKilometers
        customDistance = ""
        hydrationIsEnabled = preset.hydration.isEnabled
        hydrationFirstReminder = preset.hydration.firstReminderMinutes.map(String.init) ?? ""
        hydrationRepeatInterval = preset.hydration.repeatIntervalMinutes.map(String.init) ?? ""
        hydrationDisplayName = preset.hydration.displayName
        fuelIsEnabled = preset.fuel.isEnabled
        fuelFirstReminder = preset.fuel.firstReminderMinutes.map(String.init) ?? ""
        fuelRepeatInterval = preset.fuel.repeatIntervalMinutes.map(String.init) ?? ""
        fuelDisplayName = preset.fuel.displayName
    }

    mutating func clearHydrationReminderInputs() {
        hydrationFirstReminder = ""
        hydrationRepeatInterval = ""
        hydrationDisplayName = ""
    }

    mutating func clearFuelReminderInputs() {
        fuelFirstReminder = ""
        fuelRepeatInterval = ""
        fuelDisplayName = ""
    }
}

struct ContentView: View {
    private static let firstReminderOptions = Array(stride(from: 10, through: 240, by: 10))
    private static let repeatIntervalOptions = Array(stride(from: 20, through: 240, by: 10))

    let onStart: (ReminderPlan, Bool) -> Void
    private let planStore: ReminderPlanStore

    @State private var editablePlan: EditablePlan
    @FocusState private var isEditingField: Bool
    @State private var didRecoverSavedPlan: Bool
    @State private var isNotificationExplanationPresented = false
    @State private var isResetConfirmationPresented = false
    @State private var isSafetyInformationPresented = false
    @State private var isPrivacyInformationPresented = false
    @State private var isNotificationSettingsPresented = false
    @State private var pendingPlan: ReminderPlan?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasChosenNotificationUsage") private var hasChosenNotificationUsage = false
    @AppStorage("shouldUseNotifications") private var shouldUseNotifications = true

    init(
        onStart: @escaping (ReminderPlan, Bool) -> Void = { _, _ in },
        planStore: ReminderPlanStore = .init()
    ) {
        self.onStart = onStart
        self.planStore = planStore

        let loadResult = planStore.loadWithRecoveryStatus()
        _editablePlan = State(initialValue: loadResult.plan.map(EditablePlan.init(savedPlan:))
            ?? .init(preset: ReminderPlanPreset.make(for: PlannedDistance.tenKilometers.kilometers)))
        _didRecoverSavedPlan = State(initialValue: loadResult.didRecover)
    }

    private var selectedDistanceKilometers: Double? {
        editablePlan.selectedDistance.kilometers ?? DistanceParser.kilometers(from: editablePlan.customDistance)
    }

    private var validCustomDistanceKilometers: Double? {
        guard let kilometers = DistanceParser.kilometers(from: editablePlan.customDistance),
              (0.1...200).contains(kilometers)
        else {
            return nil
        }

        return kilometers
    }

    private var plan: ReminderPlan {
        ReminderPlan(
            hydration: setting(
                isEnabled: editablePlan.hydrationIsEnabled,
                firstReminder: editablePlan.hydrationFirstReminder,
                repeatInterval: editablePlan.hydrationRepeatInterval,
                displayName: editablePlan.hydrationDisplayName
            ),
            fuel: setting(
                isEnabled: editablePlan.fuelIsEnabled,
                firstReminder: editablePlan.fuelFirstReminder,
                repeatInterval: editablePlan.fuelRepeatInterval,
                displayName: editablePlan.fuelDisplayName
            )
        )
    }

    private var validationMessages: [String] {
        var messages: [String] = []

        if editablePlan.selectedDistance == .custom,
           let kilometers = selectedDistanceKilometers,
           !(0.1...200).contains(kilometers) {
            messages.append("カスタム距離は 0.1〜200 km で入力してください。")
        } else if editablePlan.selectedDistance == .custom, selectedDistanceKilometers == nil {
            messages.append("カスタム距離を数値で入力してください。")
        }

        for error in plan.validationErrors() {
            messages.append(error.message)
        }

        return messages
    }

    private var canStart: Bool {
        validationMessages.isEmpty
    }

    private func notificationLimitValidationMessage(for setting: ReminderSetting) -> String? {
        guard plan.validationErrors().contains(.tooManyScheduledReminders) else {
            return nil
        }

        let enabledSettings = [plan.hydration, plan.fuel].filter(\.isEnabled)
        guard enabledSettings.count == 1,
              let firstReminderMinutes = setting.firstReminderMinutes,
              let repeatIntervalMinutes = setting.repeatIntervalMinutes
        else {
            return ReminderPlanValidationError.tooManyScheduledReminders.message
        }

        let scheduledReminderCount =
            (ReminderPlan.maximumSessionMinutes - firstReminderMinutes) / repeatIntervalMinutes + 1
        let minimumRepeatInterval =
            (ReminderPlan.maximumSessionMinutes - firstReminderMinutes)
                / ReminderPlan.maximumScheduledReminders + 1

        return "現在の設定では通知は\(scheduledReminderCount)件です。最初の通知が\(firstReminderMinutes)分の場合、繰り返し間隔を\(minimumRepeatInterval)分以上にすると60件以内になります。"
    }

    private var supplementalValidationMessages: [String] {
        var messages: [String] = []

        if editablePlan.selectedDistance == .custom,
           let kilometers = selectedDistanceKilometers,
           !(0.1...200).contains(kilometers) {
            messages.append("カスタム距離は 0.1〜200 km で入力してください。")
        } else if editablePlan.selectedDistance == .custom, selectedDistanceKilometers == nil {
            messages.append("カスタム距離を数値で入力してください。")
        }

        for error in plan.validationErrors() {
            switch error {
            case .missingFirstReminder, .missingRepeatInterval:
                continue
            case .tooManyScheduledReminders:
                continue
            default:
                messages.append(error.message)
            }
        }

        return messages
    }

    private var savedPlan: SavedPlan? {
        SavedPlan(
            selectedDistanceKilometers: selectedDistanceKilometers ?? .nan,
            hydration: plan.hydration,
            fuel: plan.fuel
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ランニング補給タイマー")
                        .font(.largeTitle.bold())
                    Text("通知の予定を確認して、すぐスタートできます。")
                        .foregroundStyle(.secondary)
                    Text("通知を使わなくても、画面上の経過時間と次の予定は確認できます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                reminderSummarySection(
                    title: "給水",
                    isEnabled: $editablePlan.hydrationIsEnabled,
                    firstReminder: $editablePlan.hydrationFirstReminder,
                    repeatInterval: $editablePlan.hydrationRepeatInterval,
                    defaultFirstReminder: 20,
                    defaultRepeatInterval: 20,
                    onDisabled: { editablePlan.clearHydrationReminderInputs() }
                )

                reminderSummarySection(
                    title: "補給・ジェル",
                    isEnabled: $editablePlan.fuelIsEnabled,
                    firstReminder: $editablePlan.fuelFirstReminder,
                    repeatInterval: $editablePlan.fuelRepeatInterval,
                    defaultFirstReminder: 40,
                    defaultRepeatInterval: 40,
                    onDisabled: { editablePlan.clearFuelReminderInputs() }
                )

                Button("通知を調整") {
                    isNotificationSettingsPresented = true
                }
                .buttonStyle(.bordered)
                .accessibilityHint("予定距離と通知のタイミングを変更します")

                if didRecoverSavedPlan {
                    Label(
                        "保存した設定を安全な初期値へ戻しました。必要に応じて通知を調整してください。",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .accessibilityElement(children: .combine)
                }

                if !validationMessages.isEmpty {
                    Label("通知設定を確認してください。", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .accessibilityHint("通知を調整から設定を修正すると開始できます")
                }

                Text("通知は目安であり、補給量を指示するものではありません。体調、製品表示、専門家の助言を優先し、体調不良時は運動を中止してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button("このプランで開始") {
                    startPlan()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.bar)
                .disabled(!canStart)
                .accessibilityHint(canStart ? "通知を許可するか、通知なしで開始するかを選びます" : "表示された設定を修正すると開始できます")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("情報", systemImage: "info.circle") {
                        Button("安全上の注意") {
                            isSafetyInformationPresented = true
                        }
                        Button("プライバシーとサポート") {
                            isPrivacyInformationPresented = true
                        }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { isEditingField = false }
                }
            }
            .onChange(of: editablePlan.selectedDistance) { _, distance in
                applyPreset(for: distance == .custom ? validCustomDistanceKilometers : distance.kilometers)
            }
            .onChange(of: editablePlan.customDistance) { _, distance in
                guard editablePlan.selectedDistance == .custom,
                      let kilometers = DistanceParser.kilometers(from: distance),
                      (0.1...200).contains(kilometers)
                else {
                    return
                }

                applyPreset(for: kilometers)
            }
            .onChange(of: savedPlan) { _, savedPlan in
                guard let savedPlan else { return }
                planStore.save(savedPlan)
            }
            .onAppear {
                normalizeReminderInputValues()
                isSafetyInformationPresented = !hasCompletedOnboarding
            }
            .alert("通知を使って開始しますか？", isPresented: $isNotificationExplanationPresented) {
                Button("通知なしで開始", role: .cancel) {
                    hasChosenNotificationUsage = true
                    shouldUseNotifications = false
                    startPendingPlan(requestingNotificationPermission: false)
                }
                Button("通知を許可") {
                    hasChosenNotificationUsage = true
                    shouldUseNotifications = true
                    startPendingPlan(requestingNotificationPermission: true)
                }
            } message: {
                Text("給水・補給の予定時刻をローカル通知でお知らせします。許可しなくても画面上のタイマーは使えます。通知はiPhoneの通知設定、サイレントモード、集中モード、端末やOSの状態により遅延・不達となる場合があります。")
            }
            .sheet(isPresented: $isSafetyInformationPresented) {
                SafetyInformationView(
                    isOnboarding: !hasCompletedOnboarding,
                    onCompleteOnboarding: {
                        hasCompletedOnboarding = true
                        isSafetyInformationPresented = false
                    }
                )
            }
            .sheet(isPresented: $isPrivacyInformationPresented) {
                PrivacyInformationView()
            }
            .sheet(isPresented: $isNotificationSettingsPresented) {
                NavigationStack {
                    notificationSettingsView
                        .navigationTitle("通知を調整")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完了") {
                                    isNotificationSettingsPresented = false
                                }
                            }
                        }
                }
            }
    }

    private var notificationSettingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GroupBox("予定距離") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("予定距離", selection: $editablePlan.selectedDistance) {
                            ForEach(PlannedDistance.allCases) { distance in
                                Text(distance.title).tag(distance)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityHint("距離に合わせて通知の初期設定を選びます")

                        if editablePlan.selectedDistance == .custom {
                            TextField("距離（km）", text: $editablePlan.customDistance)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .focused($isEditingField)
                                .accessibilityLabel("カスタム距離（km）")
                                .accessibilityHint("0.1〜200 kmの範囲で入力します")
                        }
                    }
                }

                reminderSection(
                    title: "給水",
                    isEnabled: $editablePlan.hydrationIsEnabled,
                    firstReminder: $editablePlan.hydrationFirstReminder,
                    repeatInterval: $editablePlan.hydrationRepeatInterval,
                    displayName: $editablePlan.hydrationDisplayName,
                    defaultFirstReminder: 20,
                    defaultRepeatInterval: 20,
                    notificationLimitMessage: editablePlan.hydrationIsEnabled
                        ? notificationLimitValidationMessage(for: plan.hydration)
                        : nil,
                    onDisabled: { editablePlan.clearHydrationReminderInputs() }
                )

                reminderSection(
                    title: "補給・ジェル",
                    isEnabled: $editablePlan.fuelIsEnabled,
                    firstReminder: $editablePlan.fuelFirstReminder,
                    repeatInterval: $editablePlan.fuelRepeatInterval,
                    displayName: $editablePlan.fuelDisplayName,
                    defaultFirstReminder: 40,
                    defaultRepeatInterval: 40,
                    notificationLimitMessage: editablePlan.fuelIsEnabled
                        ? notificationLimitValidationMessage(for: plan.fuel)
                        : nil,
                    onDisabled: { editablePlan.clearFuelReminderInputs() }
                )

                if !validationMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("開始できない設定があります。", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ForEach(supplementalValidationMessages, id: \.self) { message in
                            Label(message, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                GroupBox("通知") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(
                            "通知を使う",
                            isOn: Binding(
                                get: { shouldUseNotifications },
                                set: { isEnabled in
                                    shouldUseNotifications = isEnabled
                                    hasChosenNotificationUsage = true
                                }
                            )
                        )
                        Text("オフにすると、次回は通知を出さずに開始します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Button("設定を初期化", role: .destructive) {
                    isResetConfirmationPresented = true
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .confirmationDialog("設定を初期化しますか？", isPresented: $isResetConfirmationPresented) {
            Button("初期化", role: .destructive) {
                planStore.reset()
                apply(preset: ReminderPlanPreset.make(for: PlannedDistance.tenKilometers.kilometers))
                didRecoverSavedPlan = false
            }
        } message: {
            Text("保存した距離と給水・補給の設定を初期値へ戻します。")
        }
    }

    private func reminderSummarySection(
        title: String,
        isEnabled: Binding<Bool>,
        firstReminder: Binding<String>,
        repeatInterval: Binding<String>,
        defaultFirstReminder: Int,
        defaultRepeatInterval: Int,
        onDisabled: @escaping () -> Void
    ) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("\(title)を通知する", isOn: isEnabled)
                    .onChange(of: isEnabled.wrappedValue) { _, isEnabled in
                        if isEnabled {
                            firstReminder.wrappedValue = normalizedReminderValue(
                                firstReminder.wrappedValue,
                                options: Self.firstReminderOptions,
                                fallback: defaultFirstReminder
                            )
                            repeatInterval.wrappedValue = normalizedReminderValue(
                                repeatInterval.wrappedValue,
                                options: Self.repeatIntervalOptions,
                                fallback: defaultRepeatInterval
                            )
                        } else {
                            onDisabled()
                        }
                    }

                if isEnabled.wrappedValue,
                   let firstReminderMinutes = Int(firstReminder.wrappedValue),
                   let repeatIntervalMinutes = Int(repeatInterval.wrappedValue) {
                    Text("スタートから\(firstReminderMinutes)分後、その後\(repeatIntervalMinutes)分ごと")
                        .foregroundStyle(.secondary)
                } else {
                    Text("通知しない")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reminderSection(
        title: String,
        isEnabled: Binding<Bool>,
        firstReminder: Binding<String>,
        repeatInterval: Binding<String>,
        displayName: Binding<String>,
        defaultFirstReminder: Int,
        defaultRepeatInterval: Int,
        notificationLimitMessage: String?,
        onDisabled: @escaping () -> Void
    ) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("\(title)を通知する", isOn: isEnabled)
                    .accessibilityHint(
                        isEnabled.wrappedValue
                            ? "オフにすると、この通知の時刻と表示名を初期化します"
                            : "オンにすると、この通知の時刻と表示名を入力できます"
                    )
                    .onChange(of: isEnabled.wrappedValue) { _, isEnabled in
                        if isEnabled {
                            firstReminder.wrappedValue = normalizedReminderValue(
                                firstReminder.wrappedValue,
                                options: Self.firstReminderOptions,
                                fallback: defaultFirstReminder
                            )
                            repeatInterval.wrappedValue = normalizedReminderValue(
                                repeatInterval.wrappedValue,
                                options: Self.repeatIntervalOptions,
                                fallback: defaultRepeatInterval
                            )
                        } else {
                            onDisabled()
                        }
                }

                if isEnabled.wrappedValue {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最初に知らせるタイミング")
                            .font(.subheadline.weight(.medium))
                        Picker("最初に知らせるタイミング", selection: firstReminder) {
                            ForEach(Self.firstReminderOptions, id: \.self) { minutes in
                                Text("スタートから\(minutes)分後").tag(String(minutes))
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityLabel("\(title)を最初に知らせるタイミング")
                        .accessibilityHint("スタートしてから最初に知らせる時間を選びます")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("その後の通知間隔")
                            .font(.subheadline.weight(.medium))
                        Picker("その後の通知間隔", selection: repeatInterval) {
                            ForEach(Self.repeatIntervalOptions, id: \.self) { minutes in
                                Text("以後\(minutes)分ごと").tag(String(minutes))
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityLabel("\(title)のその後の通知間隔")
                        .accessibilityHint("最初の通知の後に知らせる間隔を選びます")
                    }

                    if let firstReminderMinutes = Int(firstReminder.wrappedValue),
                       let repeatIntervalMinutes = Int(repeatInterval.wrappedValue) {
                        Text("通知予定：スタートから\(firstReminderMinutes)分後、その後は\(repeatIntervalMinutes)分ごと")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("通知表示名（任意）")
                            .font(.subheadline.weight(.medium))
                        TextField("通知表示名（任意）", text: displayName)
                            .textFieldStyle(.roundedBorder)
                            .focused($isEditingField)
                            .accessibilityLabel("\(title)の通知表示名（任意）")
                            .accessibilityHint("30文字以内で入力します")
                    }
                    if let notificationLimitMessage {
                        Label(notificationLimitMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func setting(
        isEnabled: Bool,
        firstReminder: String,
        repeatInterval: String,
        displayName: String
    ) -> ReminderSetting {
        ReminderSetting(
            isEnabled: isEnabled,
            firstReminderMinutes: Int(firstReminder),
            repeatIntervalMinutes: Int(repeatInterval),
            displayName: displayName
        )
    }

    private func applyPreset(for kilometers: Double?) {
        let preset = ReminderPlanPreset.make(for: kilometers)
        editablePlan.hydrationIsEnabled = preset.hydration.isEnabled
        editablePlan.hydrationFirstReminder = preset.hydration.firstReminderMinutes.map(String.init) ?? "20"
        editablePlan.hydrationRepeatInterval = preset.hydration.repeatIntervalMinutes.map(String.init) ?? "20"
        editablePlan.hydrationDisplayName = preset.hydration.displayName
        editablePlan.fuelIsEnabled = preset.fuel.isEnabled
        editablePlan.fuelFirstReminder = preset.fuel.isEnabled
            ? preset.fuel.firstReminderMinutes.map(String.init) ?? "40"
            : ""
        editablePlan.fuelRepeatInterval = preset.fuel.isEnabled
            ? preset.fuel.repeatIntervalMinutes.map(String.init) ?? "40"
            : ""
        editablePlan.fuelDisplayName = preset.fuel.displayName
    }

    private func apply(savedPlan: SavedPlan) {
        editablePlan = .init(savedPlan: savedPlan)
    }

    private func apply(preset: ReminderPlan) {
        editablePlan = .init(preset: preset)
        normalizeReminderInputValues()
    }

    private func normalizeReminderInputValues() {
        if editablePlan.hydrationIsEnabled {
            editablePlan.hydrationFirstReminder = normalizedReminderValue(
                editablePlan.hydrationFirstReminder,
                options: Self.firstReminderOptions,
                fallback: 20
            )
            editablePlan.hydrationRepeatInterval = normalizedReminderValue(
                editablePlan.hydrationRepeatInterval,
                options: Self.repeatIntervalOptions,
                fallback: 20
            )
        }

        if editablePlan.fuelIsEnabled {
            editablePlan.fuelFirstReminder = normalizedReminderValue(
                editablePlan.fuelFirstReminder,
                options: Self.firstReminderOptions,
                fallback: 40
            )
            editablePlan.fuelRepeatInterval = normalizedReminderValue(
                editablePlan.fuelRepeatInterval,
                options: Self.repeatIntervalOptions,
                fallback: 40
            )
        }
    }

    private func normalizedReminderValue(_ value: String, options: [Int], fallback: Int) -> String {
        guard let minutes = Int(value), options.contains(minutes) else {
            return String(fallback)
        }

        return value
    }

    private func startPendingPlan(requestingNotificationPermission: Bool) {
        guard let pendingPlan else { return }
        self.pendingPlan = nil
        onStart(pendingPlan, requestingNotificationPermission)
    }

    private func startPlan() {
        if hasChosenNotificationUsage {
            onStart(plan, shouldUseNotifications)
        } else {
            pendingPlan = plan
            isNotificationExplanationPresented = true
        }
    }

}
