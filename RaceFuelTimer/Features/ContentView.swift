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
    let onStart: (ReminderPlan, Bool) -> Void
    private let planStore: ReminderPlanStore

    @State private var editablePlan: EditablePlan
    @FocusState private var isEditingNumber: Bool
    @State private var didRecoverSavedPlan: Bool
    @State private var isNotificationExplanationPresented = false
    @State private var isResetConfirmationPresented = false
    @State private var isSafetyInformationPresented = false
    @State private var isPrivacyInformationPresented = false
    @State private var pendingPlan: ReminderPlan?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init(
        onStart: @escaping (ReminderPlan, Bool) -> Void = { _, _ in },
        planStore: ReminderPlanStore = .init()
    ) {
        self.onStart = onStart
        self.planStore = planStore

        let loadResult = planStore.loadWithRecoveryStatus()
        _editablePlan = State(initialValue: .init(savedPlan: loadResult.plan))
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
                        Text("走り出す前に、通知の計画を確認しましょう。")
                            .foregroundStyle(.secondary)
                        Text("通知を使わなくても、画面上の経過時間と次の予定は確認できます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)

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
                                    .focused($isEditingNumber)
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
                        onDisabled: { editablePlan.clearHydrationReminderInputs() }
                    )

                    reminderSection(
                        title: "補給・ジェル",
                        isEnabled: $editablePlan.fuelIsEnabled,
                        firstReminder: $editablePlan.fuelFirstReminder,
                        repeatInterval: $editablePlan.fuelRepeatInterval,
                        displayName: $editablePlan.fuelDisplayName,
                        onDisabled: { editablePlan.clearFuelReminderInputs() }
                    )

                    if didRecoverSavedPlan {
                        Label(
                            "保存した設定を安全な初期値へ戻しました。予定距離と通知設定を確認してから開始してください。",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                        .accessibilityElement(children: .combine)
                    }

                    Button("設定を初期化", role: .destructive) {
                        isResetConfirmationPresented = true
                    }

                    if !validationMessages.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("開始前に設定を確認してください")
                                .font(.headline)
                            ForEach(validationMessages, id: \.self) { message in
                                Label(message, systemImage: "exclamationmark.circle.fill")
                            }
                        }
                        .foregroundStyle(.red)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("開始できない設定があります。\(validationMessages.joined(separator: "、"))")
                        .accessibilityHint("表示された内容を修正すると開始できます")
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
                    pendingPlan = plan
                    isNotificationExplanationPresented = true
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
                    Button("完了") { isEditingNumber = false }
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
                isSafetyInformationPresented = !hasCompletedOnboarding
            }
            .confirmationDialog("設定を初期化しますか？", isPresented: $isResetConfirmationPresented) {
                Button("初期化", role: .destructive) {
                    planStore.reset()
                    apply(savedPlan: .default)
                    didRecoverSavedPlan = false
                }
            } message: {
                Text("保存した距離と給水・補給の設定を初期値へ戻します。")
            }
            .alert("通知を使って開始しますか？", isPresented: $isNotificationExplanationPresented) {
                Button("通知なしで開始", role: .cancel) {
                    startPendingPlan(requestingNotificationPermission: false)
                }
                Button("通知を許可") {
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
    }

    private func reminderSection(
        title: String,
        isEnabled: Binding<Bool>,
        firstReminder: Binding<String>,
        repeatInterval: Binding<String>,
        displayName: Binding<String>,
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
                        guard !isEnabled else { return }
                        onDisabled()
                    }

                if isEnabled.wrappedValue {
                    TextField("最初の通知（分）", text: firstReminder)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditingNumber)
                        .accessibilityLabel("\(title)の最初の通知（分）")
                        .accessibilityHint("5〜240分の整数で入力します")
                    TextField("繰り返し間隔（分）", text: repeatInterval)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditingNumber)
                        .accessibilityLabel("\(title)の繰り返し間隔（分）")
                        .accessibilityHint("5〜240分の整数で入力します")
                    TextField("通知表示名（任意）", text: displayName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("\(title)の通知表示名（任意）")
                        .accessibilityHint("30文字以内で入力します")
                    Text("最初の通知と間隔は 5〜240 分の整数です。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
        editablePlan.hydrationFirstReminder = preset.hydration.firstReminderMinutes.map(String.init) ?? ""
        editablePlan.hydrationRepeatInterval = preset.hydration.repeatIntervalMinutes.map(String.init) ?? ""
        editablePlan.hydrationDisplayName = preset.hydration.displayName
        editablePlan.fuelIsEnabled = preset.fuel.isEnabled
        editablePlan.fuelFirstReminder = preset.fuel.firstReminderMinutes.map(String.init) ?? ""
        editablePlan.fuelRepeatInterval = preset.fuel.repeatIntervalMinutes.map(String.init) ?? ""
        editablePlan.fuelDisplayName = preset.fuel.displayName
    }

    private func apply(savedPlan: SavedPlan) {
        editablePlan = .init(savedPlan: savedPlan)
    }

    private func startPendingPlan(requestingNotificationPermission: Bool) {
        guard let pendingPlan else { return }
        self.pendingPlan = nil
        onStart(pendingPlan, requestingNotificationPermission)
    }

}

private struct SafetyInformationView: View {
    let isOnboarding: Bool
    let onCompleteOnboarding: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if isOnboarding {
                    Section("ランニング補給タイマーへようこそ") {
                        Text("走行前に給水・補給の予定を設定し、経過時間と次の予定を確認するためのアプリです。")
                        Text("使い方：距離と予定を確認して「このプランで開始」を押します。通知を許可しなくても、画面上のタイマーは利用できます。")
                    }
                }

                Section("安全上の注意") {
                    Text("通知は目安であり、補給量や医療・栄養上の判断を指示するものではありません。体調、製品表示、専門家の助言を優先してください。")
                    Text("痛み、めまい、吐き気など体調不良を感じた場合は、運動を中止して必要に応じて医療機関へ相談してください。")
                }

                Section("通知について") {
                    Text("通知は給水・補給の予定時刻を知らせる目的でのみ使います。許可しない場合もタイマーと画面上の次回予定は利用できます。")
                    Text("通知の音・振動・表示は、iPhoneの通知設定、サイレントモード、集中モード、端末やOSの状態により遅延・不達となる場合があります。走行中は通知だけに頼らず、安全を最優先してください。")
                }
            }
            .navigationTitle(isOnboarding ? "はじめに" : "安全上の注意")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if isOnboarding {
                    Button("内容を確認して始める", action: onCompleteOnboarding)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.bar)
                }
            }
        }
        .interactiveDismissDisabled(isOnboarding)
    }
}

private struct PrivacyInformationView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("プライバシー") {
                    Text("このアプリは、設定した距離、給水・補給の通知設定をこの端末内にのみ保存します。")
                    Text("位置情報、連絡先、健康データなどは取得しません。データを外部サーバーへ送信・共有・販売することもありません。")
                }

                Section("権限") {
                    Text("通知権限は、給水・補給の予定時刻をローカル通知で知らせるためにのみ使用します。位置情報の権限は要求しません。")
                }

                Section("サポート") {
                    Link("GitHub Issuesで問い合わせる", destination: URL(string: "https://github.com/mytysoldier/race-fuel-timer/issues")!)
                }

                Section("ライセンス") {
                    Text("このアプリは外部ライブラリを使用していません。")
                }
            }
            .navigationTitle("プライバシーとサポート")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
