# SHIORI・SAORIの利用

SHIORIごとの実行方式・制約とビルド手順は、[Utatane Modulesの資料](https://github.com/opera7133/utatane-modules/blob/main/docs/native-shiori.md)を参照してください。

初回起動時にYAYAと里々の共通導入版をカタログから取得します。既に導入済みなら再取得せず、カタログへ接続できなくても起動できます。共通導入版の更新後、起動中のゴーストには再読み込みが必要です。カタログの「導入済み」は共通導入版の状態であり、ゴースト同梱版から切り替わったことを示しません。

## SHIORIの選択

ゴーストの`shiori.macos`に指定されたモジュールを優先します。対応する同梱ライブラリの破損や必要な関数の欠落を検出すると、同じSHIORIの共通導入版へ切り替えます。設定の「SHIORI対応状況」でオフにできます。辞書・保存データのエラーでは切り替えません。各SHIORIの配布版は、ゴースト内、共通導入先の順に探します。`ese-shiori.dll`など、対応済みのDLL名が`shiori`にある場合、同じフォルダにdylibを置くだけでUtataneが検出します。

Windows DLLだけを持つゴーストは、辞書や設定を判別し、対応するモジュールを導入済みなら接続します。設定の「SHIORI対応状況」で判定を確認できます。動かない場合は「情報」→「SHIORI読み込み診断…」と[診断・報告の手順](Troubleshooting.md#診断と報告)を使ってください。

YAYA は 5 系と 6 系を別々に導入できます。ゴーストに `yaya.dll` がある場合は、その Windows バージョン情報の `FileVersion` を読み、6 系なら YAYA 6、5 系または判定不能なら YAYA 5 を選びます。`ProductVersion` は 6 系でも 5 と記録されるため、判定には使いません。ゴーストが `shiori.macos` で `libyaya-6.dylib` を指定している場合は、その明示指定を優先します。

YAYA 6 でハッシュや入れ子の変数を保存した後に 5 系へ戻すと、その変数の保存内容が崩れることがあります。切り替える前にゴーストの保存データをバックアップしてください。

同梱する側の配置・指定方法は[SHIORI開発ガイド](../Creators/SHIORI-Development.md)、各配布物の導入手順は[Utatane Modules](https://github.com/opera7133/utatane-modules)にあります。

通常のmacOS用SHIORIは、ゴースト・プラグインごとに別プロセスで実行します。応答停止や異常終了を検出した場合、実行済みの処理を重複させないため、自動で要求を再送しません。

## 共通SAORIブリッジ

Utataneが提供するSAORIと対応する命令は、[共通SAORIブリッジの一覧](https://github.com/opera7133/utatane-modules/blob/main/docs/native-shiori.md#共通saoriブリッジ)を参照してください。独自の外部SHIORIが読み込むSAORIは、そのSHIORI側で管理します。
