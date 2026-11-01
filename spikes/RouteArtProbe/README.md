# Route Art Probe（#105）

本番アプリとは独立した検証用アプリ。2枚のAI生成背景、架空の線、背景切替、HealthKitからの読み取りを試す。Simulator専用ボタンは架空のワークアウトとルートをSimulatorのHealthKitに追加するため、書き込み権限を要求する。本番機能の仕様ではない。

```sh
xcodebuild -project spikes/RouteArtProbe/RouteArtProbe.xcodeproj -scheme RouteArtProbe -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/RouteArtProbe build CODE_SIGNING_ALLOWED=NO
```

動作確認は専用Simulatorで行い、架空のランを追加後に「HealthKitのランを読み込む」を選ぶ。ルートなし、長いルート、途中で離れた点を含むルートの生成もSimulatorでのみ行える。追加のたびSimulatorのHealthKitに新しいランが残る。データの追加・読み取りの成否は別途記録する。実データを持つ端末に架空データを書き込まないよう、追加ボタンはSimulatorに限定する。

試作の制限: 最新30件のみ検索、ルートの追加・変更の追跡なし、複数ルート未対応。分断は仮の閾値による候補で、誤検出・見逃しがあり得る。未読込時はサンプル線を表示し、読み込み後の空や失敗時は線を出さず保存・共有を無効にする。バックグラウンド移行時に読み取り済みのルートを消し、前景復帰時に再取得する方式は検証用であり、本番の操作感や実機での挙動は未確定。線の色・見た目と画像の写真保存・共有は検証用。開始・終了地点周囲を隠す200mの試案は匿名化を保証しない。作品のアプリ内永続化は未実装。表示は実装の成立を保証しない。
