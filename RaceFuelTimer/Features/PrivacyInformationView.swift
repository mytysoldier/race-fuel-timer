import SwiftUI

struct PrivacyInformationView: View {
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
