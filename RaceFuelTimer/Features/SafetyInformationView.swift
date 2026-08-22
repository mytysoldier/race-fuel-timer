import SwiftUI

struct SafetyInformationView: View {
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
