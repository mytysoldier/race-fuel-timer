# ランニング補給タイマー

iPhone向けのランニング補給タイマーです。走行前に設定した時間ベースの給水・補給リマインダーを、端末内のローカル通知で届けます。

通知は補給量や医療・栄養上の判断を指示するものではありません。体調、製品表示、専門家の助言を優先してください。

## MVPの範囲

- 予定距離の選択と、距離帯に応じた時間通知の初期セット
- 給水・補給ごとの有効／無効、通知時刻・間隔・表示名の設定
- セッションの開始・一時停止・再開・終了
- 経過時間と次回予定の表示
- iOSのローカル通知、設定の端末内保存、VoiceOver対応

GPS距離計測・距離通知、地図、走行履歴、外部API、ログイン、クラウド同期、広告、解析SDK、課金はMVPに含めません。詳細な仕様は[docs/planning-template.md](docs/planning-template.md)、技術構成は[docs/architecture.md](docs/architecture.md)を参照してください。

## 技術方針

iOS 17以上のSwiftUIアプリとして、`UserNotifications` に時間ベースのローカル通知を事前予約し、設定だけを `UserDefaults` へ保存します。詳細なアーキテクチャは[docs/architecture.md](docs/architecture.md)に集約しています。

## 開発・検証手順

必要環境は Xcode 16 以降（iOS 17 Simulator を含む）です。依存する外部ライブラリはありません。リポジトリ直下で次の品質ゲートを実行できます。

```sh
make lint
make typecheck
make test
make build
```

`make lint` は Swift コンパイラの構文解析でソースの基本チェックを行います。`typecheck` はテスト用ビルド、`test` は iPhone 15 Pro Simulator 上の単体テスト、`build` は Simulator 向けアプリビルドです。品質ゲートはすべてローカルで実行します。

ローカルで起動するには、Xcode で `RaceFuelTimer.xcodeproj` を開き、iOS 17 以上の iPhone Simulator または実機を選び、`RaceFuelTimer` スキームを実行します。実機で実行する場合は、自分の Apple Developer Team を Signing & Capabilities で選択してください。

## 実装順序

1. #5: SwiftUIプロジェクトとローカル品質ゲートを初期化する
2. #6: 通知プランのデータモデルとスケジュール計算を実装する
3. #7: 設定画面と入力バリデーションを実装する
4. #8: 実行中タイマー画面と状態遷移を実装する
5. #10: 音声・振動・ローカル通知を接続する
6. #11: バックグラウンド移行・復帰時の整合性を実装する
7. #12: 設定保存と破損データからの復旧を実装する
8. #13: エラー状態・権限拒否・アクセシビリティを整備する
9. #14と#15: 回帰手順、および安全・権限・プライバシー文言を整備する
10. #16: TestFlightと実走でQAする
11. #17: App Storeへ公開する

距離通知のIssue #9は、時間通知のみとするMVP方針により対象外です。将来、別の実機Spikeで再評価します。

## 並列化の方針

#5〜#13は、同じSwiftUIアプリ基盤とセッション状態に順に依存するため直列で進めます。#14と#15は、#13完了後かつ通知実装（#10）の仕様が確定していれば、テスト・手順書と文言・静的コンテンツで変更対象を分けて並列化できます。#16と#17は公開品質に関わるため直列です。

## ドキュメント

- [MVP計画](docs/planning-template.md)
- [技術アーキテクチャ](docs/architecture.md)
- [補給・給水通知の調査](docs/research/fueling-hydration-notification-guidelines.md)
- [iOS通知・バックグラウンドSpike](docs/background-notification-spike.md)
- [iOS回帰チェックリスト](docs/ios-regression-checklist.md)
