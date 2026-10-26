# Live Activity 検証アプリ（Issue #75）

本番アプリとは別のアプリ・Bundle ID。#69の完成実装ではなく、ロック中の日時表示と予定データ更新の境界を調べるための最小構成です。本番の設定・通知・補給記録は読み書きしません。

## ビルド・起動

```sh
xcodebuild -project spikes/LiveActivityProbe/LiveActivityProbe.xcodeproj \
  -scheme LiveActivityProbe -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/LiveActivityProbe build CODE_SIGNING_ALLOWED=NO
xcrun simctl install 159D6FCC-F4BD-48FA-A3A9-B6B2C7BFCF55 \
  build/LiveActivityProbe/Build/Products/Debug-iphonesimulator/LiveActivityProbe.app
xcrun simctl launch 159D6FCC-F4BD-48FA-A3A9-B6B2C7BFCF55 \
  com.mytysoldier.RaceFuelTimer.LiveActivityProbe
```

実機では `LiveActivityProbe.xcodeproj` を開き、両ターゲットに自分のDevelopment Teamを選び、接続したiPhoneを実行先にしてRunしてください。Teamや端末識別子はコミットしません。配布・審査用のアプリではありません。

## 操作

- 1分×3回・10分×3回・3時間×3回から選択。通知も予約する場合は開始前にオンにする。
- 開始後はホームへ移動し、Device > Lockでロック画面を表示する。Live Activityの許可表示があれば許可する。
- 予定時刻の前後で、経過表示、カウントダウン、送信した予定番号、最終送信時刻、更新期限の警告、届いた通知番号を記録する。画面を点灯する操作とアプリを前面に戻す操作を区別する。
- 前面でのみ1秒ごとに次の予定を計算し、予定番号が変わる時だけActivityKitへ更新する。アプリがバックグラウンドで実行時間を得ることは前提にしない。通常の予約通知はアプリを起こしてActivityKitを更新する処理を持たない。
- 一時停止で経過時間・残り時間を固定し通知を取り消す。再開で停止時間を除いて通知を再予約する。終了は `.immediate` で表示を消す。
- 完全終了後のセッション復元はしない。次回起動で既存Activityと通知を削除する。強制終了直後に消えるかはOS上で別途観測する。
- 通知オフ・補給予定なしでも開始可能。Live Activity無効／開始失敗時もアプリ内経過表示を継続する。
- 「検証ログを共有」で前面の送信履歴を取り出せる。ログはメモリ内のみで、完全終了前に保存する。ロック中のスクリーンショットとセットで記録する。

## 本番との境界

短時間検証の予定は60秒間隔3回という検証専用の固定値です。既存の `Session`、通知1本化、記録済み予定の除外を再実装して本番へ組み込むものではありません。#68の `Session.nextReminder(at:)` / `elapsedSeconds(at:)` / `totalPausedSeconds` を#69の入力にする案は、#75の結論確定後に検討します。

8時間制限は3時間間隔モードで実時間8時間を越えて観察します。端末時計の変更や古い開始日時による表示は、OSのActivity継続時間の検証になりません。

検証項目と結果の一次記録は [../../docs/live-activity-spike.md](../../docs/live-activity-spike.md) を参照してください。
