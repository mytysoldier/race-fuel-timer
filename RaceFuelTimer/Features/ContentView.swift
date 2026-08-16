import SwiftUI

struct ContentView: View {
    let onStart: (ReminderPlan) -> Void

    @State private var selectedDistance: PlannedDistance = .tenKilometers
    @State private var customDistance = ""
    @State private var hydrationIsEnabled = true
    @State private var hydrationFirstReminder = "20"
    @State private var hydrationRepeatInterval = "20"
    @State private var hydrationDisplayName = ""
    @State private var fuelIsEnabled = false
    @State private var fuelFirstReminder = ""
    @State private var fuelRepeatInterval = ""
    @State private var fuelDisplayName = ""
    @FocusState private var isEditingNumber: Bool

    init(onStart: @escaping (ReminderPlan) -> Void = { _ in }) {
        self.onStart = onStart
    }

    private var selectedDistanceKilometers: Double? {
        selectedDistance.kilometers ?? Double(customDistance)
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

    var body: some View {
        NavigationStack {
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
                    onStart(plan)
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
                applyPreset(for: distance.kilometers)
            }
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

}
