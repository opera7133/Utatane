# SHIORI・SAORIの利用

SHIORIごとの実行方式・制約とビルド手順は、[Utatane Modulesの資料](https://github.com/opera7133/utatane-modules/blob/main/docs/native-shiori.md)を参照してください。

## SHIORIの選択

ゴーストの`shiori.macos`に指定されたモジュールを優先します。対応する同梱ライブラリの破損や必要な関数の欠落を検出すると、同じSHIORIの共通導入版へ切り替えます。設定の「SHIORI対応状況」でオフにできます。辞書・保存データのエラーでは切り替えません。各SHIORIの配布版は、ゴースト内、共通導入先の順に探します。`ese-shiori.dll`など、対応済みのDLL名が`shiori`にある場合、同じフォルダにdylibを置くだけでUtataneが検出します。

Windows DLLだけを持つゴーストは、辞書や設定を判別し、対応するモジュールを導入済みなら接続します。設定の「SHIORI対応状況」で判定を確認できます。動かない場合は「情報」→「SHIORI読み込み診断…」と[診断・報告の手順](Troubleshooting.md#診断と報告)を使ってください。

同梱する側の配置・指定方法は[SHIORI開発ガイド](../Creators/SHIORI-Development.md)、各配布物の導入手順は[Utatane Modules](https://github.com/opera7133/utatane-modules)にあります。

通常のmacOS用SHIORIは、ゴースト・プラグインごとに別プロセスで実行します。応答停止や異常終了を検出した場合、実行済みの処理を重複させないため、自動で要求を再送しません。

## 共通SAORIブリッジ

Utataneが提供するSAORIと対応する命令は、[共通SAORIブリッジの一覧](https://github.com/opera7133/utatane-modules/blob/main/docs/native-shiori.md#共通saoriブリッジ)を参照してください。独自の外部SHIORIが読み込むSAORIは、そのSHIORI側で管理します。
