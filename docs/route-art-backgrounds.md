# ルートアート同梱背景

2026-11-15確認。写真3点はいずれも、各ファイルのWikimedia Commons説明ページで、2017-06-05より前にUnsplashでCC0として公開されたと記載されている。CC0は商用利用・改変・再配布を許容するが、著作権以外の権利まで保証するものではない。人物・ロゴ・建物等が画面の主体に含まれない風景を選んだ。写真はランの実際の景色ではない。

| アプリ内の背景 | 写真家 | 出典・条件 | 同梱画像SHA-256 |
| --- | --- | --- | --- |
| 海辺 | Jakob Owens | [The Coast](https://commons.wikimedia.org/wiki/File:The_Coast_(Unsplash).jpg)、2017-03-19、CC0 | `1d44c5485c69592c8407df87fbf134f5b4074bed2b2847cdf77e5dc5b3e55403` |
| 森 | Ben Blennerhassett | [Sun over a forest road](https://commons.wikimedia.org/wiki/File:Sun_over_a_forest_road_(Unsplash).jpg)、2016-03-08、CC0 | `a6e729ad74329ba20911bd34a0c47fd3b8deb7567d55ed9269284c5573240071` |
| 夕暮れ | Adriel Kloppenburg | [Sunset with mountain landscape](https://commons.wikimedia.org/wiki/File:Sunset_with_mountain_landscape._(Unsplash).jpg)、2015-04-15、CC0 | `ed0dbe78b9af32d5ccc27694b8f248d7211a2d7ae240c94f38f9ae71b61e84ee` |

元写真をImageIOで最大辺2200ピクセルに縮小しJPEG品質0.84で再生成。元画像のメタデータは引き継いでいない。3枚のImageIOプロパティを検査しGPS辞書がないことを確認した。これはあらゆる形式の位置情報の不存在や、写真の内容から撮影地を推測できないことを保証しない。著作権表示はCC0の条件では必須ではないが、出どころをここに記録する。

作品画像はルート・日時などから場所が推測され得る。開始・終了付近を隠す設定は匿名化を保証せず、保存・共有前に画像を確認する。写真・HealthKit由来情報を任意の共有先やiCloudバックアップへ渡す場合のAppleの条件は、公開前の未解決事項として [App Privacy 回答案](app-store-privacy.md) を参照する。

## Simulatorでの確認

専用iPhone 17 / iOS 26.2 Simulatorと一時的なUIテストターゲットを使用。Simulator内の架空HealthKitランを読み込み、3背景を順に選んでアプリ内へ保存した。3枚とも1080×1350ピクセルでImageIOのGPS辞書はなく、白い実線と文字が写真に重なることを確認した。架空作品は専用Simulatorに残る。確認は1件の架空ルート・白い実線に限り、実ルート、他の線色、実機、写真ライブラリや共有先での変換は未確認。
