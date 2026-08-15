# バックグラウンド計測・音声・振動通知 技術Spike

Issue [#2](https://github.com/mytysoldier/race-fuel-timer/issues/2) の調査結果。2026-08-14 時点の公式資料を基に、Issue #3 で初期リリース要件と技術スタックを決めるための判断材料を整理する。

## 結論

- **時間通知は初期リリースで成立可能**。セッション開始時にOSのローカル通知を先行予約し、バックグラウンドや画面ロック中の表示・同梱音声・システム通知の振動をOSに委ねる。
- 「音声」はバックグラウンドで任意の読み上げ処理を起動するのではなく、**給水／ジェルを区別できる30秒未満の同梱済み短音声**を通知音に使う。フォアグラウンドでは同じ音源の再生とアプリ内ハプティクスを利用できる。
- 通知許可、音、振動、集中モード／Do Not Disturb、サイレント、端末・メーカーの省電力設定はユーザーとOSが最終制御する。したがって、**指定時刻の音声・振動を無条件には保証しない**。
- **距離通知は技術的には実現可能だが初期リリースから外すことを推奨**する。累積距離はジオフェンスでは判定できず、バックグラウンド位置更新、追加権限、AndroidのForeground Service、電池・精度評価、両ストアの審査対応が必要になる。強制終了後の継続も保証できない。
- 技術スタックはこのSpikeでは確定しない。現時点では **React Native + Expo development buildを最初の検証候補**、Flutterを比較候補、ネイティブを制約回避が必要な場合の候補とする。Expo Goは必要なバックグラウンド機能を検証できないため候補外とする。
- 公式資料でOS APIと候補フレームワークの成立条件を確認できたため、このIssueではプロトタイプを追加しない。実機固有の通知精度・省電力挙動は技術選定後の通知実装Issueと実走QAで確認する。

## 前提と用語

- 「バックグラウンド」: 別アプリが前面、または画面ロック中だがアプリプロセスはOS管理下にある状態。
- 「終了」: OSがプロセスを回収した状態を含む。ユーザーの強制終了／Androidの強制停止とは区別する。
- 「時間通知」: セッション開始時刻からの絶対時刻で、開始時に予約できる給水・ジェル通知。
- 「距離通知」: GPS等から得た位置列をアプリが積算し、設定距離の到達を判定する通知。特定地点への出入りを監視するジオフェンスとは異なる。
- 初期リリースは外部API、サーバープッシュ、クラウド処理を使わない。

## iOS / Android 機能可否マトリクス

記号は `○` がOSの正規APIで成立、`△` が条件付きまたは非保証、`×` が今回の方式では不可を表す。

| 状態・機能 | iOS | Android | 成立条件・制約 |
| --- | --- | --- | --- |
| 前面での経過時間表示 | ○ | ○ | `setInterval`の加算ではなく、開始時刻・停止時間から再計算する。 |
| 背面／ロック中の時間通知 | ○ | △ | iOSは事前予約したローカル通知をアプリ非実行時もOSが配信する。Androidで正確な時刻を求める場合はAlarmManagerのexact alarmと特別アクセスが必要。不許可時やinexact alarmは遅延し得る。 |
| OS回収後の予約済み時間通知 | ○ | △ | iOSは予約済み通知をOSが保持。AndroidはExpo Notificationsが再起動後の再設定用に`RECEIVE_BOOT_COMPLETED`を利用するが、強制停止やメーカー独自制限は保証外。 |
| ユーザー強制終了／強制停止後の予約済み時間通知 | ○ | × | iOSはアプリの実行状態と独立して、OSに登録済みの時間通知を配信する。ただし、アプリ内セッション状態、通知の取消・再予約、距離更新は継続しない。Androidの強制停止後はユーザーが再起動するまで通知継続を保証しない。 |
| 通知バナー／ロック画面表示 | △ | △ | 通知許可が必須。表示方法、プレビュー、チャンネル重要度はユーザー設定・OS制御。Android 13以降は`POST_NOTIFICATIONS`が必要。 |
| 同梱した短音声の通知音 | △ | △ | iOSのカスタム通知音は30秒未満。Android 8以降はNotification Channelに音を設定する。サイレント、Focus/DND、音量、チャンネル設定で鳴らない場合がある。 |
| バックグラウンドでの動的TTS | × | × | 予約時刻に任意コードを確実に起動できない。通知イベントを合図にTTSを開始する設計は初期リリースの保証対象にしない。 |
| 通知に伴う振動 | △ | △ | iOSは通知設定・端末状態に従う。Androidはチャンネルの振動パターンを設定できるが、作成後はユーザーが最終制御する。アプリ内ハプティクスAPIはバックグラウンド通知の代替ではない。 |
| Focus / DND中の割り込み | △ | △ | iOSのCritical Alertは申請制entitlementで初期リリース対象外。Time Sensitiveもユーザーが無効化可能。AndroidのDND迂回は追加アクセスが必要なため初期リリースでは要求しない。 |
| 背面／ロック中の連続距離更新 | △ | △ | iOSはLocation background modeと位置権限、Androidは位置権限とユーザー開始のlocation Foreground Serviceが必要。OS・省電力・精度の影響を受ける。 |
| 強制終了後の距離通知 | × | × | Expoの連続background locationはユーザー終了で停止し、Androidは自動再起動しない。OS差を吸収して継続保証できない。 |
| 距離到達時の音声・振動 | △ | △ | プロセスが位置更新を受けて到達判定できる場合のみ即時ローカル通知を出せる。位置更新が遅延・停止すれば通知も遅延・欠落する。 |

## 通知方式の比較

| 方式 | 背面・ロック | 終了後 | 正確性 | 初期リリース判断 |
| --- | --- | --- | --- | --- |
| JS/Dartのタイマーを動かし続ける | × | × | OSのサスペンドで停止 | 不採用 |
| OSローカル通知を開始時に先行予約 | ○ | 条件付き○ | OS・権限・省電力の範囲内 | **時間通知の採用候補** |
| Background Task / WorkManagerで時刻判定 | △ | △ | 実行時刻はOS判断。Expo BackgroundTaskも即時実行を保証しない | 通知時刻判定には不採用 |
| Android Foreground Serviceで常時タイマー | Androidのみ○ | △ | 継続通知が必須。開始制限・権限・Playポリシー対応が増える | 時間だけの初期リリースでは優先しない |
| バックグラウンド位置更新で累積距離判定 | △ | × | GPS精度・更新間隔・電池・OS終了に依存 | **初期リリース見送り推奨** |

### 時間通知の推奨フロー

1. 通知の用途と保証できない条件を説明し、許可を要求する。
2. 給水／ジェル別の通知チャンネル・短音声を設定する。
3. セッション開始時刻を永続化し、全予定を絶対時刻へ変換する。
4. OSローカル通知を予定ごとに予約する。iOSは保留件数上限を考慮し、予約件数を検証・制限する。
5. 一時停止・終了時は未配信通知をIDで取り消す。再開時は新しい絶対時刻で再予約する。
6. 復帰時は「現在時刻 − 開始時刻 − 停止時間」から表示を再計算し、配信済み／期限切れを再同期する。期限切れ通知を連打しない。
7. Androidでexact alarm特別アクセスを使うか、許可なし時の遅延を許容するかはIssue #3で決める。`USE_EXACT_ALARM`はPlayポリシーの対象となるため安易に採用しない。

## OS別の主な制約

### iOS

- 多くのアプリは背面移行後にサスペンドされる。任意のタイマーやTTSを動かし続ける設計ではなく、`UNUserNotificationCenter`へ先行予約する。
- ローカル通知はアプリが前面にいない、または実行されていない場合もOSが処理する。前面中はdelegateで表示・音の扱いを明示する。
- 通知許可はalert、sound等の状態が個別に変わり得るため、開始前に設定を確認する。
- 通常通知はサイレントやFocusを必ず突破できない。Critical Alertは特別なentitlementが必要であり、補給タイマーの初期リリースでは申請しない。
- カスタム通知音は端末内に事前配置し、30秒未満にする。動的TTSは予約通知の音源にできない。
- 連続距離計測にはCore Locationのbackground modeと適切な権限説明が必要。バックグラウンド位置はリアルタイムのフィットネス用途として正当化可能だが、App Review Guidelines 2.5.4 / 5.1.5に沿って目的を明示する。
- ユーザー終了や権限変更、OS判断による位置更新停止を前提とし、距離到達通知を確実とは表現しない。

### Android

- Android 13以降は通常通知に`POST_NOTIFICATIONS`の実行時許可が必要。Android 8以降は全通知をチャンネルへ所属させ、音・振動・重要度はチャンネルとユーザー設定が最終決定する。
- Doze中のinexact alarmは遅延する。Android 12以降でexact alarmを使うには「Alarms & reminders」の特別アクセス等が必要で、電池とPlayポリシーへの影響がある。
- 連続距離計測は、ユーザーが画面上で開始したlocation Foreground Serviceとして実行し、継続通知を表示する方式が基本。Android 14以降はservice typeと`FOREGROUND_SERVICE_LOCATION`等の宣言が必要。
- 通常のバックグラウンド位置更新はAndroid 8以降で1時間に数回程度まで制限され得るため、ランニング中の累積距離判定には不足する。
- `ACCESS_BACKGROUND_LOCATION`を使う場合、最小権限、目立つ事前開示、Privacy Policy、申告フォーム、動画等がGoogle Play審査で必要。Foreground ServiceもPlayの申告対象となる。
- 強制停止や一部メーカーの省電力制御後は、サービス、位置更新、通知の継続を保証しない。

## 技術スタック候補の比較

この比較はIssue #3への入力であり、採用決定ではない。

| 候補 | 時間ローカル通知 | 背景位置 | 音・振動 | 実装速度 | OS制約対応・保守 | 現時点の評価 |
| --- | --- | --- | --- | --- | --- | --- |
| React Native + Expo development build | `expo-notifications`で両OSを共通化。Android exact alarm設定も明記 | `expo-location` + `expo-task-manager`。権限、iOS background mode、Android FGS設定を提供 | 同梱音声、Android channel振動、前面`expo-haptics`を提供 | 高 | OS固有設定と実機検証は残る。必要ならprebuild/config pluginまたはnative moduleへ降りられる | **最初の検証候補**。時間通知の初期リリースと相性がよい |
| Flutter | Dart isolateの仕組みがあり、Flutter公式DocsからFlutter Community管理の`workmanager`への導線がある | 位置・ローカル通知は主にplugin選定とnative設定が必要 | plugin依存 | 中 | `workmanager`を含むcommunity pluginの管理主体・品質・更新追従をIssue #3で評価する必要 | 比較候補。採用済み資産がない現状ではExpoよりSpike量が増える |
| iOS / Androidネイティブ | UserNotifications / AlarmManagerを直接利用 | Core Location / Fused Location・FGSを直接利用 | OS APIを最大限制御 | 低（2実装） | 制約追従は明確だが、UI・ロジック・QAが二重化 | OS差を細かく制御する必要が判明した場合の候補 |

### 候補から外すもの

- **Expo Go**: AndroidのForeground / Background Locationが使えず、background locationはiOSでもdevelopment buildが必要。実機成立性を評価できない。
- **Web / PWAのみ**: iOS / Androidで画面ロック中の時間通知、同梱音声、振動、連続位置を同じ保証範囲で提供できない。
- **通常のBackground Taskによる秒・分単位タイマー**: OSが実行時刻を決めるため、補給予定時刻の通知源として使えない。

## 初期リリースで保証する範囲

### 保証する（必要条件を満たす場合）

- ユーザーがセッションを開始し、通知許可を付与している。
- アプリ前面では経過時間と次回予定を開始時刻基準で表示する。
- 背面・画面ロック中は、事前予約済みの時間通知をOSへ依頼する。
- 給水／ジェルを通知文と同梱済み短音声で区別する。
- 一時停止・終了時に未配信通知を取り消し、復帰時に状態を再計算する。
- 通知許可がない、または音が無効な場合、開始前に検出可能な範囲で警告し、設定画面への導線を出す。

ここで保証するのは「アプリが正しい予定を作成し、OSへ予約・取消を行うこと」であり、OSが必ず音・振動を提示することではない。

### 保証しない

- サイレント、Focus / DND、通知・チャンネル無効、音量ゼロでも必ず音が鳴ること。
- 全端末で同じ振動パターンになること。
- Androidのexact alarm特別アクセスがない場合の秒単位の配信時刻。
- ユーザー強制終了／強制停止後のセッション継続・自動復旧。
- OSやメーカーの省電力制御を回避すること。
- バックグラウンドで任意のTTSを起動すること。
- GPS距離と距離到達通知（初期リリース見送り推奨）。
- 医療・安全上の緊急通知。Critical Alert / DND迂回は使わない。

## 距離通知の初期リリース採否

**Issue #3への提案: 初期リリースは時間通知のみとし、距離通知は初期リリース後または別の実機Spike後に判断する。**

理由:

1. 時間通知は開始時に全予定を予約でき、アプリを継続実行する必要がない。
2. 距離通知は連続位置を受けて累積距離を計算する必要があり、OSローカル通知の位置トリガー（地点への出入り）では代替できない。
3. 両OSで追加権限、利用中表示、電池消費、拒否時UX、強制終了時の欠落が増える。
4. AndroidはForeground ServiceとGoogle Play申告、iOSはbackground location用途の説明・審査が必要になる。
5. GPS外れ値、停止中ドリフト、低精度、屋内、端末差を実走で評価する必要があり、「給水タイミング通知」の価値検証より先に大きな技術・審査リスクを背負う。
6. 時間通知だけでも「走行中に画面を見ず給水／ジェルを区別して知らせる」という中核体験を検証できる。

将来の距離Spikeでは、ユーザー開始のワークアウト中だけ位置取得すること、外部送信・ルート保存をしないこと、iOS background mode、Android location FGS、権限拒否時の時間通知への切替、実走距離誤差、1時間あたりの電池消費、強制終了時の表示を受け入れ条件にする。

## Issue #3で決めること

- 初期リリースを時間通知のみとするか。距離通知を残すなら、追加実機Spikeと審査コストを受け入れるか。
- React Native + Expo development build、Flutter、ネイティブのどれを採用するか。
- Androidでexact alarm特別アクセスを要求するか、一定の遅延を許容するか。許可拒否時のフォールバックをどう表示するか。
- 1セッションの最大時間・通知件数と、iOS保留通知上限に収める入力上限。
- 給水／ジェルの同梱音声、通知文、Androidチャンネル構成。
- 「通知はOS設定により鳴らない場合がある」ことを開始前・設定・オンボーディングのどこで説明するか。
- アプリ復帰時に期限切れ通知をどう扱うか（推奨: 最新1件だけ状態へ反映し、連打しない）。
- 対象OSバージョンと、実機QA対象端末。

## 後続Issueへの検証引き継ぎ

技術選定後、通知実装Issueと実走QAで最低限以下を実機確認する。

- iOS / Androidそれぞれで、前面、別アプリ前面、画面ロックの3状態。
- 通知許可あり／拒否、音あり／なし、Focus / DND、サイレント、Androidチャンネル無効。
- 一時停止、再開、終了、アプリ復帰、OSによるプロセス回収、ユーザー強制終了。
- Androidはexact alarm許可あり／なし、Doze、再起動、代表メーカーの省電力設定。
- 予定時刻との差、二重通知、終了後の残留通知、長時間セッションの予約件数。
- 距離通知を将来検証する場合は、屋外実走で距離誤差、ドリフト、低精度、電池消費、FGS表示、権限変更を追加する。

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

### Android / Google Play

- [Schedule alarms](https://developer.android.com/develop/background-work/services/alarms)
- [Optimize for Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)
- [Notification runtime permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission)
- [Create and manage notification channels](https://developer.android.com/develop/ui/compose/notifications/channels)
- [Access location in the background](https://developer.android.com/develop/sensors-and-location/location/background)
- [Foreground services overview](https://developer.android.com/develop/background-work/services/fgs)
- [Restrictions on starting a foreground service from the background](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
- [Foreground service changes](https://developer.android.com/develop/background-work/services/fgs/changes)
- [Google Play: Understanding location in the background permissions](https://support.google.com/googleplay/android-developer/answer/9799150)

### 候補フレームワーク

- [Expo Notifications](https://docs.expo.dev/versions/latest/sdk/notifications/)
- [Expo Location](https://docs.expo.dev/versions/latest/sdk/location/)
- [Expo BackgroundTask](https://docs.expo.dev/versions/latest/sdk/background-task/)
- [Expo Haptics](https://docs.expo.dev/versions/latest/sdk/haptics/)
- [Flutter: Background processes](https://docs.flutter.dev/packages-and-plugins/background-processes)
- [pub.dev: workmanager（publisher: fluttercommunity.dev）](https://pub.dev/packages/workmanager)
