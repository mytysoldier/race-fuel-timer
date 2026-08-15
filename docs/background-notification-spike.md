# バックグラウンド計測・音声・振動通知 技術Spike（iOS）

Issue [#2](https://github.com/mytysoldier/race-fuel-timer/issues/2) の調査結果。2026-08-15 時点のApple公式資料を基に、Issue #3で初期リリース要件と技術スタックを決めるための判断材料を整理する。

## 結論

- **時間通知は初期リリースで成立可能**。大会の開始予定時刻と補給間隔を事前設定し、OSのローカル通知を絶対時刻で先行予約する。バックグラウンドや画面ロック中の表示・同梱音声・システム通知の振動はiOSに委ねるため、当日の開始操作は必須ではない。
- 「音声」はバックグラウンドで任意の読み上げ処理を起動するのではなく、**給水／ジェルを区別できる30秒未満の同梱済み短音声**を通知音に使う。フォアグラウンドでは同じ音源の再生とアプリ内ハプティクスを利用できる。
- 通知許可、音、振動、Focus、サイレント、端末設定はユーザーとiOSが最終制御する。したがって、**指定時刻の音声・振動を無条件には保証しない**。
- **距離通知は技術的には実現可能だが初期リリースから外すことを推奨**する。累積距離はジオフェンスでは判定できず、Core Locationのバックグラウンド位置更新、追加権限、電池・精度評価、App Store審査対応が必要になる。ユーザー終了後の継続も保証できない。
- 技術スタックはこのSpikeでは確定しない。現時点では **React Native + Expo development buildを最初の検証候補**、Flutterを比較候補、iOSネイティブを制約回避が必要な場合の候補とする。Expo Goは必要なバックグラウンド機能を検証できないため候補外とする。
- 公式資料でiOS APIと候補フレームワークの成立条件を確認できたため、このIssueではプロトタイプを追加しない。通知精度・位置更新・省電力挙動は技術選定後の通知実装Issueと実走QAで確認する。

## 前提と用語

- 「バックグラウンド」: 別アプリが前面、または画面ロック中だがアプリプロセスはiOS管理下にある状態。
- 「終了」: iOSがプロセスを回収した状態、またはユーザーがアプリを終了した状態。
- 「時間通知」: 大会の開始予定時刻を基準とした絶対時刻で、事前に予約できる給水・ジェル通知。
- 「距離通知」: GPS等から得た位置列をアプリが積算し、設定距離の到達を判定する通知。特定地点への出入りを監視するジオフェンスとは異なる。
- 初期リリースでは、時間通知の配信可否を外部API、サーバープッシュ、クラウド処理に依存させず、端末内のローカル通知で完結させる。外部APIは別用途で利用できる。

## iOS 機能可否マトリクス

記号は `○` がiOSの正規APIで成立、`△` が条件付きまたは非保証、`×` が今回の方式では不可を表す。

| 状態・機能 | iOS | 成立条件・制約 |
| --- | --- | --- |
| 前面での経過時間表示 | ○ | `setInterval`の加算ではなく、開始予定時刻・停止時間から再計算する。 |
| 背面／ロック中の時間通知 | ○ | 事前予約したローカル通知をアプリ非実行時もiOSが配信する。通知許可と通知設定が必要。 |
| OS回収後の予約済み時間通知 | ○ | 予約済み通知はiOSが保持する。ただし、アプリ内状態の更新や通知の再予約は行えない。 |
| ユーザー終了後の予約済み時間通知 | ○ | iOSはアプリの実行状態と独立して、OSに登録済みの時間通知を配信する。ただし、アプリ内セッション状態、通知の取消・再予約、距離更新は継続しない。 |
| 通知バナー／ロック画面表示 | △ | 通知許可が必須。表示方法とプレビューはユーザー設定・OS制御。 |
| 同梱した短音声の通知音 | △ | カスタム通知音は30秒未満。サイレント、Focus、音量、通知設定で鳴らない場合がある。 |
| バックグラウンドでの動的TTS | × | 予約時刻に任意コードを確実に起動できない。通知イベントを合図にTTSを開始する設計は初期リリースの保証対象にしない。 |
| 通知に伴う振動 | △ | 通知設定・端末状態に従う。アプリ内ハプティクスAPIはバックグラウンド通知の代替ではない。 |
| Focus中の割り込み | △ | Critical Alertは申請制entitlementで初期リリース対象外。Time Sensitiveもユーザーが無効化可能。 |
| 背面／ロック中の連続距離更新 | △ | Location background modeと位置権限が必要。OS・省電力・精度の影響を受ける。 |
| ユーザー終了後の距離通知 | × | アプリの位置更新・距離判定は継続しない。 |
| 距離到達時の音声・振動 | △ | プロセスが位置更新を受けて到達判定できる場合のみ即時ローカル通知を出せる。位置更新が遅延・停止すれば通知も遅延・欠落する。 |

## 通知方式の比較

| 方式 | 背面・ロック | 終了後 | 正確性 | 初期リリース判断 |
| --- | --- | --- | --- | --- |
| JS/Dartのタイマーを動かし続ける | × | × | iOSのサスペンドで停止 | 不採用 |
| OSローカル通知を開始予定時刻に先行予約 | ○ | ○ | OS・権限・設定の範囲内 | **時間通知の採用候補** |
| Background Taskで時刻判定 | △ | △ | 実行時刻はOS判断。Expo BackgroundTaskも即時実行を保証しない | 通知時刻判定には不採用 |
| バックグラウンド位置更新で累積距離判定 | △ | × | GPS精度・更新間隔・電池・終了に依存 | **初期リリース見送り推奨** |

### 時間通知の推奨フロー

1. 大会の開始予定時刻、補給間隔、通知の用途と保証できない条件を設定画面で確認する。
2. 通知許可を要求し、給水／ジェル別の通知内容と短音声を設定する。
3. 開始予定時刻を永続化し、全予定を絶対時刻へ変換する。
4. OSローカル通知を予定ごとに予約する。iOSの保留件数上限を考慮し、予約件数を検証・制限する。
5. アプリ内で予定を変更、または終了を操作したときは、未配信通知をIDで取り消し、必要な予定だけ再予約する。ユーザーがアプリを終了した場合は、取消・再予約を行えない。
6. アプリ復帰時は「現在時刻 − 開始予定時刻 − 停止時間」から表示を再計算し、配信済み／期限切れを再同期する。期限切れ通知を連打しない。

## iOSの主な制約

- 多くのアプリは背面移行後にサスペンドされる。任意のタイマーやTTSを動かし続ける設計ではなく、`UNUserNotificationCenter`へ先行予約する。
- ローカル通知はアプリが前面にいない、または実行されていない場合もiOSが処理する。前面中はdelegateで表示・音の扱いを明示する。
- 通知許可はalert、sound等の状態が個別に変わり得るため、開始予定時刻を有効化する前に設定を確認する。
- 通常通知はサイレントやFocusを必ず突破できない。Critical Alertは特別なentitlementが必要であり、補給タイマーの初期リリースでは申請しない。
- カスタム通知音は端末内に事前配置し、30秒未満にする。動的TTSは予約通知の音源にできない。
- 連続距離計測にはCore Locationのbackground modeと適切な権限説明が必要。バックグラウンド位置はリアルタイムのフィットネス用途として正当化可能だが、App Review Guidelines 2.5.4 / 5.1.5に沿って目的を明示する。
- ユーザー終了や権限変更、OS判断による位置更新停止を前提とし、距離到達通知を確実とは表現しない。

## 技術スタック候補の比較

この比較はIssue #3への入力であり、採用決定ではない。

| 候補 | 時間ローカル通知 | 背景位置 | 音・振動 | 実装速度 | iOS制約対応・保守 | 現時点の評価 |
| --- | --- | --- | --- | --- | --- | --- |
| React Native + Expo development build | `expo-notifications`でiOS通知を実装。iOS固有設定はdevelopment buildで検証 | `expo-location` + `expo-task-manager`。位置権限とbackground mode設定が必要 | 同梱音声と前面`expo-haptics`を提供 | 高 | 必要ならprebuild/config pluginまたはnative moduleへ降りられる | **最初の検証候補**。時間通知の初期リリースと相性がよい |
| Flutter | iOS向け通知pluginとnative設定が必要 | 位置機能もplugin選定とiOS設定が必要 | plugin依存 | 中 | pluginの管理主体・品質・更新追従をIssue #3で評価する必要 | 比較候補。採用済み資産がない現状ではExpoよりSpike量が増える |
| iOSネイティブ | UserNotificationsを直接利用 | Core Locationを直接利用 | OS APIを最大限制御 | 中 | iOS制約の追従は明確だが、SwiftでUI・ロジックを実装する必要がある | OS差を吸収する必要がないため、制約を細かく制御したい場合の候補 |

### 候補から外すもの

- **Expo Go**: background locationはiOSでもdevelopment buildが必要であり、必要な実機成立性を評価できない。
- **Web / PWAのみ**: iOSで画面ロック中の時間通知、同梱音声、振動、連続位置を必要な保証範囲で提供できない。
- **通常のBackground Taskによる秒・分単位タイマー**: OSが実行時刻を決めるため、補給予定時刻の通知源として使えない。

## 初期リリースで保証する範囲

### 保証する（必要条件を満たす場合）

- ユーザーが大会の開始予定時刻を設定し、通知許可を付与している。
- アプリ前面では経過時間と次回予定を開始予定時刻基準で表示する。
- 背面・画面ロック中は、事前予約済みの時間通知をiOSへ依頼する。
- 給水／ジェルを通知文と同梱済み短音声で区別する。
- アプリ内で予定を変更、または終了を操作したときに、未配信通知を取り消し、必要な予定だけ再予約する。
- 通知許可がない、または音が無効な場合、開始前に検出可能な範囲で警告し、設定画面への導線を出す。

ここで保証するのは「アプリが正しい予定を作成し、iOSへ予約・取消を行うこと」であり、iOSが必ず音・振動を提示することではない。

### 保証しない

- サイレント、Focus、通知無効、音量ゼロでも必ず音が鳴ること。
- 全端末で同じ振動パターンになること。
- ユーザー終了後のセッション継続・自動復旧。
- iOSの省電力制御を回避すること。
- バックグラウンドで任意のTTSを起動すること。
- GPS距離と距離到達通知（初期リリース見送り推奨）。
- 医療・安全上の緊急通知。Critical Alert / Focus迂回は使わない。

## 距離通知の初期リリース採否

**Issue #3への提案: 初期リリースは時間通知のみとし、距離通知は初期リリース後または別の実機Spike後に判断する。**

理由:

1. 時間通知は開始予定時刻から全予定を予約でき、アプリを継続実行する必要がない。
2. 距離通知は連続位置を受けて累積距離を計算する必要があり、OSローカル通知の位置トリガー（地点への出入り）では代替できない。
3. 位置権限、利用中表示、電池消費、拒否時UX、ユーザー終了時の欠落が増える。
4. iOSはbackground location用途の説明・審査が必要になる。
5. GPS外れ値、停止中ドリフト、低精度、屋内、端末差を実走で評価する必要があり、「給水タイミング通知」の価値検証より先に大きな技術・審査リスクを背負う。
6. 時間通知だけでも「走行中に画面を見ず給水／ジェルを区別して知らせる」という中核体験を検証できる。

将来の距離Spikeでは、ユーザー開始のワークアウト中だけ位置取得すること、外部送信・ルート保存をしないこと、iOS background mode、権限拒否時の時間通知への切替、実走距離誤差、1時間あたりの電池消費、ユーザー終了時の表示を受け入れ条件にする。

## Issue #3で決めること

- 初期リリースを時間通知のみとするか。距離通知を残すなら、追加実機Spikeと審査コストを受け入れるか。
- React Native + Expo development build、Flutter、iOSネイティブのどれを採用するか。
- 1セッションの最大時間・通知件数と、iOS保留通知上限に収める入力上限。
- 給水／ジェルの同梱音声と通知文。
- 「通知はiOS設定により鳴らない場合がある」ことを開始前・設定・オンボーディングのどこで説明するか。
- アプリ復帰時に期限切れ通知をどう扱うか（推奨: 最新1件だけ状態へ反映し、連打しない）。
- 対象iOSバージョンと、実機QA対象端末。

## 後続Issueへの検証引き継ぎ

技術選定後、通知実装Issueと実走QAで最低限以下を実機確認する。

- iOSで、前面、別アプリ前面、画面ロックの3状態。
- 通知許可あり／拒否、音あり／なし、Focus、サイレント。
- 予定変更、終了、アプリ復帰、OSによるプロセス回収、ユーザー終了。
- 予定時刻との差、二重通知、終了後の残留通知、長時間セッションの予約件数。
- 距離通知を将来検証する場合は、屋外実走で距離誤差、ドリフト、低精度、電池消費、権限変更を追加する。

## 参照資料

### Apple

- [Scheduling a notification locally from your app](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
- [Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
- [Handling notifications and notification-related actions](https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions)
- [UNNotificationSound](https://developer.apple.com/documentation/usernotifications/unnotificationsound)
- [Critical Alerts entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.critical-alerts/)
- [Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [App Review Guidelines 2.5.4 / 5.1.5](https://developer.apple.com/app-store/review/guidelines/)
- [Local and Remote Notification Programming Guide（保留通知数の制約）](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html)

### 候補フレームワーク

- [Expo Notifications](https://docs.expo.dev/versions/latest/sdk/notifications/)
- [Expo Location](https://docs.expo.dev/versions/latest/sdk/location/)
- [Expo BackgroundTask](https://docs.expo.dev/versions/latest/sdk/background-task/)
- [Expo Haptics](https://docs.expo.dev/versions/latest/sdk/haptics/)
