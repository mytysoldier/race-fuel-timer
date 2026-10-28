import SwiftUI

struct PrivacyInformationView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("プライバシー") {
                    Text("このアプリは、通知設定と終了したランの日時・経過時間・補給記録をこの端末内に保存します。履歴はアプリ内で削除できます。")
                    Text("位置情報、連絡先、健康データなどは取得しません。データを外部サーバーへ送信・共有・販売することもありません。")
                }

                Section("権限") {
                    Text("通知権限は、給水・補給の予定時刻をローカル通知で知らせるためにのみ使用します。位置情報の権限は要求しません。")
                }

                Section("サポート") {
                    Link("サポートページを開く", destination: URL(string: "https://mytysoldier.github.io/app-privacy/support/race-fuel-timer/")!)
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
