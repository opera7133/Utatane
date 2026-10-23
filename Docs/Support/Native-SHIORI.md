# SHIORI・SAORIの利用

SHIORIごとの実行方式・制約とビルド手順は、[Utatane Modulesの資料](https://github.com/opera7133/utatane-modules/blob/main/docs/native-shiori.md)を参照してください。

初回起動時にYAYAと里々の共通導入版をカタログから取得します。既に導入済みなら再取得せず、カタログへ接続できなくても起動できます。共通導入版の更新後、起動中のゴーストには再読み込みが必要です。カタログの「導入済み」は共通導入版の状態であり、ゴースト同梱版から切り替わったことを示しません。

## SHIORIの選択

ゴーストの`shiori.macos`に指定されたモジュールを優先します。対応する同梱ライブラリの破損や必要な関数の欠落を検出すると、同じSHIORIの共通導入版へ切り替えます。設定の「SHIORI対応状況」でオフにできます。辞書・保存データのエラーでは切り替えません。各SHIORIの配布版は、ゴースト内、共通導入先の順に探します。`ese-shiori.dll`など、対応済みのDLL名が`shiori`にある場合、同じフォルダにdylibを置くだけでUtataneが検出します。

Windows DLLだけを持つゴーストは、辞書や設定を判別し、対応するモジュールを導入済みなら接続します。設定の「SHIORI対応状況」で判定を確認できます。動かない場合は「情報」→「SHIORI読み込み診断…」と[診断・報告の手順](Troubleshooting.md#診断と報告)を使ってください。

YAYAは6系を既定で使います。`yaya.dll`・`aya.dll`・`aya5.dll`のバージョン情報に関係なく、YAYA 6を選びます。6系が未導入なら導入を案内し、5系へ自動では切り替えません。`shiori.macos`の明示指定は引き続き優先します。

この版で初めてYAYA 6を読み込む前に、`ghost/master/`直下の`*_variable.cfg`を`Utatane-YAYA-backup/`へコピーします。既存のバックアップは上書きしません。ゴースト独自の保存ファイルは別途バックアップしてください。

5系は互換用として導入できます。使う場合は5系の`libyaya.dylib`を`ghost/master/`へ置き、`descript.txt`に`shiori.macos,libyaya.dylib`を指定してください。6系でハッシュや入れ子の変数を保存した後に5系へ戻すと、保存内容が崩れることがあります。Utataneを終了して、切り替え前の`*_variable.cfg`をバックアップから戻してから5系を使ってください。復元するとバックアップ後の進行状況は失われます。

同梱する側の配置・指定方法は[SHIORI開発ガイド](../Creators/SHIORI-Development.md)、各配布物の導入手順は[Utatane Modules](https://github.com/opera7133/utatane-modules)にあります。

通常のmacOS用SHIORIは、ゴースト・プラグインごとに別プロセスで実行します。応答停止や異常終了を検出した場合、実行済みの処理を重複させないため、自動で要求を再送しません。

## 内蔵SAORI（開発版）

本体と、内蔵SAORI接続を追加した改修版のYAYA・里々・華和梨を組み合わせると、ゴーストへDLLを置かずに次の機能を呼べます。現在の公開版Utatane 0.2.16および従来のModules配布物にはこの接続はありません。カタログの公開・更新前は、ローカルでビルドした両方を使う必要があります。

| モジュール | 対応関数 | 制限 |
| --- | --- | --- |
| `internal_system` | `ListModules`、`ListFunctions` | 対応しているモジュール・関数だけを返す |
| `internal_text` | `Normalize` | NFC、NFD、NFKC、NFKD |
| `internal_random` | `Bytes`、`Number`、`UUID` | Bytesは1〜1024バイト、NumberはInt64の閉区間、UUIDはv4/v7 |
| `internal_data` | `Convert` | text（UTF-8）、hex、base64、base64url。圧縮・展開、他の形式は未対応 |
| `internal_crypto` | `Digest`、`HMAC` | Digestはmd5/sha1/sha256/sha384/sha512、HMACはsha256/sha384/sha512。ファイル入力、暗号化・鍵生成等は未対応 |

引数・返却値の基準は[UKADOCのSAORI over DirectSSTP](https://ssp.shillest.net/ukadoc/manual/spec_saori_ex.html)です。YAYAでは`LOADLIB`／`REQUESTLIB`、里々では`＠SAORI`による登録または`（internal_text、Normalize、NFKC、ｶﾞｲﾄﾞ）`のようなモジュール名の呼び出し、華和梨では`$(callsaori internal_text Normalize NFKC ｶﾞｲﾄﾞ)`を使えます。通常のSAORIでは、引き続きmacOS用モジュールが必要です。

`--async=識別子`をオプションに加えると即座に204を返し、結果を`OnInternalSaoriComplete`／`OnInternalSaoriFailure`へGETで通知します。識別子が`On`で始まる場合は、その名前／末尾に`Failure`を加えた名前を使います。Reference0は識別子、1は結果または失敗理由、2はモジュール名、3は関数名、成功時の4以降はValue0以降です。終了・SHIORI再読み込み後には配送しません。同時処理は2〜4件、保留はセッションあたり64件までです。

macOSでは、SHIORIの専用ホストと本体を結ぶ非公開の親子プロセス通信を使用します。WindowsのHWND／WM_COPYDATA、外部XPC、Socket／HTTP経由のSAORI実行には対応していません。UTF-8とShift_JIS（CP932）、最大256引数、8MiBの要求・応答を扱います。未対応の方式や不正な引数は400、処理失敗は500を返します。表示できないバイト列や改行はbase64等で渡してください。

合成辞書と実SHIORIを使用した自動テストで検証しています。配布ゴーストの画面・会話を使った利用者の実機確認は未実施です。

## 共通SAORIブリッジ

Utataneが提供するSAORIと対応する命令は、[共通SAORIブリッジの一覧](https://github.com/opera7133/utatane-modules/blob/main/docs/native-shiori.md#共通saoriブリッジ)を参照してください。独自の外部SHIORIが読み込むSAORIは、そのSHIORI側で管理します。
