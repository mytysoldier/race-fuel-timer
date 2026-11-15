import SwiftUI

struct PrivacyInformationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("プライバシー") {
                    Text("このアプリは、通知設定と終了したランの日時・経過時間・補給記録をこの端末内に保存します。履歴はアプリ内で削除できます。")
                    Text("ルートアートを利用する場合、許可されたヘルスケアのランと経路を読み取ります。完成した作品は操作した場合のみ端末内に保存し、写真への保存や共有も任意です。経路の形などから場所が推測されることがあります。アプリがデータを外部サーバーへ送信・販売することはありません。")
                }

                Section("権限") {
                    Text("通知権限は、給水・補給の予定時刻をローカル通知で知らせるためにのみ使用します。現在地の位置情報権限は要求しません。ルートアートはヘルスケアの読み取りと写真への追加の許可を使用します。")
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
