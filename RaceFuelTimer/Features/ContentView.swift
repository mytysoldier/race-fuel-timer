import SwiftUI

struct ContentView: View {
    let onStart: (ReminderPlan, Bool) -> Void
    private let planStore: ReminderPlanStore

    @State private var selectedDistance: PlannedDistance
    @State private var customDistance: String
    @State private var hydrationIsEnabled: Bool
    @State private var hydrationFirstReminder: String
    @State private var hydrationRepeatInterval: String
    @State private var hydrationDisplayName: String
    @State private var fuelIsEnabled: Bool
    @State private var fuelFirstReminder: String
    @State private var fuelRepeatInterval: String
    @State private var fuelDisplayName: String
    @FocusState private var isEditingNumber: Bool
    @State private var isNotificationExplanationPresented = false
    @State private var isResetConfirmationPresented = false
    @State private var pendingPlan: ReminderPlan?

    init(
        onStart: @escaping (ReminderPlan, Bool) -> Void = { _, _ in },
        planStore: ReminderPlanStore = .init()
    ) {
        self.onStart = onStart
        self.planStore = planStore

        let savedPlan = planStore.load()
        let distance = PlannedDistance.from(savedDistanceKilometers: savedPlan.selectedDistanceKilometers)
        _selectedDistance = State(initialValue: distance)
        _customDistance = State(initialValue: distance == .custom ? String(savedPlan.selectedDistanceKilometers) : "")
        _hydrationIsEnabled = State(initialValue: savedPlan.hydration.isEnabled)
        _hydrationFirstReminder = State(initialValue: savedPlan.hydration.firstReminderMinutes.map(String.init) ?? "")
        _hydrationRepeatInterval = State(initialValue: savedPlan.hydration.repeatIntervalMinutes.map(String.init) ?? "")
        _hydrationDisplayName = State(initialValue: savedPlan.hydration.displayName)
        _fuelIsEnabled = State(initialValue: savedPlan.fuel.isEnabled)
        _fuelFirstReminder = State(initialValue: savedPlan.fuel.firstReminderMinutes.map(String.init) ?? "")
        _fuelRepeatInterval = State(initialValue: savedPlan.fuel.repeatIntervalMinutes.map(String.init) ?? "")
        _fuelDisplayName = State(initialValue: savedPlan.fuel.displayName)
    }

    private var selectedDistanceKilometers: Double? {
        selectedDistance.kilometers ?? DistanceParser.kilometers(from: customDistance)
    }

    private var validCustomDistanceKilometers: Double? {
        guard let kilometers = DistanceParser.kilometers(from: customDistance),
              (0.1...200).contains(kilometers)
        else {
            return nil
        }

        return kilometers
    }

    private var plan: ReminderPlan {
        ReminderPlan(
            hydration: setting(
                isEnabled: hydrationIsEnabled,
                firstReminder: hydrationFirstReminder,
                repeatInterval: hydrationRepeatInterval,
                displayName: hydrationDisplayName
            ),
            fuel: setting(
                isEnabled: fuelIsEnabled,
                firstReminder: fuelFirstReminder,
                repeatInterval: fuelRepeatInterval,
                displayName: fuelDisplayName
            )
        )
    }

    private var validationMessages: [String] {
        var messages: [String] = []

        if selectedDistance == .custom,
           let kilometers = selectedDistanceKilometers,
           !(0.1...200).contains(kilometers) {
            messages.append("カスタム距離は 0.1〜200 km で入力してください。")
        } else if selectedDistance == .custom, selectedDistanceKilometers == nil {
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
                    }

                    GroupBox("予定距離") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("予定距離", selection: $selectedDistance) {
                                ForEach(PlannedDistance.allCases) { distance in
                                    Text(distance.title).tag(distance)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityHint("距離に合わせて通知の初期設定を選びます")

                            if selectedDistance == .custom {
                                TextField("距離（km）", text: $customDistance)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($isEditingNumber)
                                    .accessibilityLabel("カスタム距離（km）")
                            }
                        }
                    }

                    reminderSection(
                        title: "給水",
                        isEnabled: $hydrationIsEnabled,
                        firstReminder: $hydrationFirstReminder,
                        repeatInterval: $hydrationRepeatInterval,
                        displayName: $hydrationDisplayName
                    )

                    reminderSection(
                        title: "補給・ジェル",
                        isEnabled: $fuelIsEnabled,
                        firstReminder: $fuelFirstReminder,
                        repeatInterval: $fuelRepeatInterval,
                        displayName: $fuelDisplayName
                    )

                    Button("設定を初期化", role: .destructive) {
                        isResetConfirmationPresented = true
                    }

                    if !validationMessages.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("開始前に修正してください")
                                .font(.headline)
                            ForEach(validationMessages, id: \.self) { message in
                                Label(message, systemImage: "exclamationmark.circle.fill")
                            }
                        }
                        .foregroundStyle(.red)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("入力エラー。\(validationMessages.joined(separator: "、"))")
                    }

                    Text("通知は補給量を指示するものではありません。体調や製品表示を優先してください。")
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
                .accessibilityHint(canStart ? "有効な通知プランです" : "入力エラーを修正すると開始できます")
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { isEditingNumber = false }
                }
            }
            .onChange(of: selectedDistance) { _, distance in
                applyPreset(for: distance == .custom ? validCustomDistanceKilometers : distance.kilometers)
            }
            .onChange(of: customDistance) { _, distance in
                guard selectedDistance == .custom,
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
            .confirmationDialog("設定を初期化しますか？", isPresented: $isResetConfirmationPresented) {
                Button("初期化", role: .destructive) {
                    planStore.reset()
                    apply(savedPlan: .default)
                }
            } message: {
                Text("保存した距離と給水・補給の設定を初期値へ戻します。")
            }
            .alert("通知を許可しますか？", isPresented: $isNotificationExplanationPresented) {
                Button("通知なしで開始", role: .cancel) {
                    startPendingPlan(requestingNotificationPermission: false)
                }
                Button("通知を許可") {
                    startPendingPlan(requestingNotificationPermission: true)
                }
            } message: {
                Text("給水・補給の予定時刻をローカル通知でお知らせします。音・振動・表示はiPhoneの通知設定、サイレント、集中モードにより届かない場合があります。")
            }
    }

    private func reminderSection(
        title: String,
        isEnabled: Binding<Bool>,
        firstReminder: Binding<String>,
        repeatInterval: Binding<String>,
        displayName: Binding<String>
    ) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("\(title)を通知する", isOn: isEnabled)

                if isEnabled.wrappedValue {
                    TextField("最初の通知（分）", text: firstReminder)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditingNumber)
                    TextField("繰り返し間隔（分）", text: repeatInterval)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditingNumber)
                    TextField("通知表示名（任意）", text: displayName)
                        .textFieldStyle(.roundedBorder)
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
        hydrationIsEnabled = preset.hydration.isEnabled
        hydrationFirstReminder = preset.hydration.firstReminderMinutes.map(String.init) ?? ""
        hydrationRepeatInterval = preset.hydration.repeatIntervalMinutes.map(String.init) ?? ""
        hydrationDisplayName = preset.hydration.displayName
        fuelIsEnabled = preset.fuel.isEnabled
        fuelFirstReminder = preset.fuel.firstReminderMinutes.map(String.init) ?? ""
        fuelRepeatInterval = preset.fuel.repeatIntervalMinutes.map(String.init) ?? ""
        fuelDisplayName = preset.fuel.displayName
    }

    private func apply(savedPlan: SavedPlan) {
        let distance = PlannedDistance.from(savedDistanceKilometers: savedPlan.selectedDistanceKilometers)
        selectedDistance = distance
        customDistance = distance == .custom ? String(savedPlan.selectedDistanceKilometers) : ""
        hydrationIsEnabled = savedPlan.hydration.isEnabled
        hydrationFirstReminder = savedPlan.hydration.firstReminderMinutes.map(String.init) ?? ""
        hydrationRepeatInterval = savedPlan.hydration.repeatIntervalMinutes.map(String.init) ?? ""
        hydrationDisplayName = savedPlan.hydration.displayName
        fuelIsEnabled = savedPlan.fuel.isEnabled
        fuelFirstReminder = savedPlan.fuel.firstReminderMinutes.map(String.init) ?? ""
        fuelRepeatInterval = savedPlan.fuel.repeatIntervalMinutes.map(String.init) ?? ""
        fuelDisplayName = savedPlan.fuel.displayName
    }

    private func startPendingPlan(requestingNotificationPermission: Bool) {
        guard let pendingPlan else { return }
        self.pendingPlan = nil
        onStart(pendingPlan, requestingNotificationPermission)
    }

}
