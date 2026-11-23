import SwiftUI

struct PrivacyInformationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("プライバシー") {
                    Text("このアプリは、通知設定と終了したランの日時・経過時間・補給記録をこの端末内に保存します。履歴はアプリ内で削除できます。")
                    Text("ルートアートを利用する場合、許可されたヘルスケアのランと経路を読み取ります。完成した作品は操作した場合のみアプリ内または写真に保存します。写真は端末のiCloud写真設定に従います。経路の形などから場所が推測されることがあります。アプリがデータを外部サーバーへ送信・販売することはありません。")
                    Text("背景に写真を選ぶと、選んだ写真だけを作品の描画に使用します。iCloud上の写真を選んだ場合、端末にダウンロードされることがあります。元の写真の位置情報などのメタデータは作品に含めません。")
                    Link("プライバシーポリシーを開く", destination: URL(string: "https://mytysoldier.github.io/app-privacy/privacy/race-fuel-timer/")!)
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
