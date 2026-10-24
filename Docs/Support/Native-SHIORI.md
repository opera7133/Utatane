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

## 内蔵SAORI

Utatane 0.2.17以降と、YAYA 5 Tc574-11-r2・YAYA 6 Tc607-2-r2・里々 Mc205-4-r2・華和梨9.1.0-r4以降を組み合わせると、ゴーストへDLLを置かずに次の機能を呼べます。共通導入版を更新した後、起動中のゴーストを再読み込みしてください。以前の本体やModulesにはこの接続がありません。

以下の表は開発中の次回版の追加分を含みます。0.2.17の`internal_data`はConvertのtext（UTF-8）・hex・base64・base64urlまでです。
圧縮・追加形式・文字コード指定、ファイルハッシュ・Compareと`internal_file`は次回版で追加します。

| モジュール | 対応関数 | 制限 |
| --- | --- | --- |
| `internal_system` | `ListModules`、`ListFunctions` | 対応しているモジュール・関数だけを返す |
| `internal_time` | `Format`、`Add`、`Diff` | エポック秒、ISO日時、HTTP IMF-fixdate。local・UTC・±18時間以内のオフセット・macOSのIANAゾーンに対応。Windows名は未対応 |
| `internal_text` | `Normalize` | NFC、NFD、NFKC、NFKD |
| `internal_random` | `Bytes`、`Number`、`UUID` | Bytesは1〜1024バイト、NumberはInt64の閉区間、UUIDはv4/v7 |
| `internal_data` | `Convert`、`Compress`、`Decompress` | text、hex/HEX、base64/base64url、base32、url、bech32。圧縮・展開はgzip/zlib/deflate。brotli/zstdは未対応 |
| `internal_file` | `MediaInfo` | 音声・画像・動画の種類とメタデータ。取得できる項目はmacOSの対応形式による |
| `internal_crypto` | `Digest`、`HMAC`、`Compare` | Digestはmd5/sha1/sha256/sha384/sha512、HMACはsha256/sha384/sha512。dataのfile入力に対応。暗号化・鍵生成等は未対応 |

引数・返却値の基準は[UKADOCのSAORI over DirectSSTP](https://ssp.shillest.net/ukadoc/manual/spec_saori_ex.html)です。YAYAでは`FUNCTIONEX`または`LOADLIB`／`REQUESTLIB`、里々では`＠SAORI`による登録または`（internal_text、Normalize、NFKC、ｶﾞｲﾄﾞ）`のようなモジュール名の呼び出し、華和梨では`$(callsaori internal_text Normalize NFKC ｶﾞｲﾄﾞ)`を使えます。通常のSAORIでは、引き続きmacOS用モジュールが必要です。

`--async=識別子`をオプションに加えると即座に204を返し、結果を`OnInternalSaoriComplete`／`OnInternalSaoriFailure`へGETで通知します。識別子が`On`で始まる場合は、その名前／末尾に`Failure`を加えた名前を使います。Reference0は識別子、1は結果または失敗理由、2はモジュール名、3は関数名、成功時の4以降はValue0以降です。終了・SHIORI再読み込み後には配送しません。同時処理は2〜4件、保留はセッションあたり64件までです。

macOSでは、SHIORIの専用ホストと本体を結ぶ非公開の親子プロセス通信を使用します。WindowsのHWND／WM_COPYDATA、外部XPC、Socket／HTTP経由のSAORI実行には対応していません。UTF-8とShift_JIS（CP932）、最大256引数、8MiBの要求・応答を扱います。未対応の方式や不正な引数は400、処理失敗は500を返します。表示できないバイト列や改行はbase64等で渡してください。

合成辞書に加え、手元のりあ・ももち・CLDSP2+の一時コピーへ検証用イベントを追加し、実際のフレームワークから同期呼び出し、非同期通知、結果イベントの利用をテストします。元の辞書・保存データは変更しません。開発版では、利用者がパレットの表示・成功と失敗の応答・呼び出しログ、および普段のゴーストの会話・メニュー・再読み込み・切り替えを確認済みです。各配布ゴーストの全機能や、両CPUの画面操作を保証するものではありません。

## 共通SAORIブリッジ

Utataneが提供するSAORIと対応する命令は、[共通SAORIブリッジの一覧](https://github.com/opera7133/utatane-modules/blob/main/docs/native-shiori.md#共通saoriブリッジ)を参照してください。独自の外部SHIORIが読み込むSAORIは、そのSHIORI側で管理します。

## 日時計算と開発用の確認

次回版では`--charset=`でデータの文字コードを指定できます（要求の`Charset`とは別）。
`--out=HEX`は大文字、`--out=hex`は小文字です。同じオプションを複数指定した場合は最後の値を使います。
Base64は通常形式・URL形式、パディングあり・なしを受け付けます。bech32出力はConvertの`--hrp=`が必要です。

`Compress`は方式とデータを位置引数に取り、既定ではBase64を返します。
`Decompress`は方式と圧縮データを取り、既定ではBase64から文字列へ戻します。
`--data-in=`と`--out=`で入出力形式を変えられます。gzipの連結メンバーを読み、
壊れた入力・途中切れ・余分な末尾をエラーにします。展開後も合計8MBが上限です。

`internal_file`の`MediaInfo`はパス、その後に取得するキーを1〜11個渡します。
`Result`は`audio`/`video`/`image`、`Value0`以降は指定した順の値です。
キーは`title`、`artist`、`albumartist`、`album`、`genre`、`comment`、`year`、`track`、
`duration`（ミリ秒）、`width`、`height`。取れない値や未知のキーは空になります。
相対パスは呼び出したゴーストの`ghost/master`基準です。開発用パレットの単体テストでは絶対パスを使ってください。
改行はバイト値1、NULは除去して返します。未対応形式は種類と値が空です。
この関数の契約は[OurinのMediaInfo提案](https://github.com/eightman999/Ourin/pull/158)も参照しています。

`internal_crypto`のDigest/HMACで`--data-in=file`を指定すると、データ引数をファイルパスとして読みます。
相対パスは呼び出したゴーストの`ghost/master`基準です。ゴーストなしの単体テストでは絶対パスを使ってください。
ファイルは64KBずつ読み、通常のデータ引数の8MB上限は適用しません。大きなファイルには`--async=識別子`を付けてください。
ファイルが存在しない場合は400 `file not found`、読み取りに失敗した場合は500 `file read failed`です。
読み取り中の切り詰め・サイズや更新時刻の変更も失敗として扱います。
非同期処理中にゴーストを終了・SHIORIを再読み込みすると、読み取りを中断して結果を配送しません。
`file`を使えるのはDigest/HMACのデータ入力だけで、鍵の入力やConvert、Compareには使えません。

`Compare`は2つのデータをOSの内容非依存の比較処理で照合し、一致なら`1`、不一致なら`0`を返します。
`--a-in=hex --b-in=hex`などで入力形式を指定できます。例えば16進の署名は、文字の大小に左右されず照合できます。

`internal_time`の`Format`は日時と書式、`Add`は日時・整数の量・単位、`Diff`は日時1・日時2・単位を取ります。`--tz=`は位置引数の後に置きます。Formatの書式を省略してオプションを渡す場合、空の位置引数を置いてください。

```text
Format / 0 / %Y/%m/%d %H:%M (%a) / --tz=+09:00
→ 1970/01/01 09:00 (Thu)
Add / 2024-01-31T12:00Z / 1 / month / --tz=UTC
→ 1709208000
Diff / 2026-12-20T10:00 / 2026-12-24 / day / --tz=UTC
→ 3
```

書式はiso8601・rfc3339・http・epoch・epochmsとUKADOCの%書式です。HTTP入力はIMF-fixdate形式に限ります。秒・分・時間は経過時間、日・週・月・年は指定ゾーンの暦で計算し、月末を丸めます。整数はUTCの西暦1〜9999年、文字列は1601年以降です。存在しない日付や夏時間開始時の存在しない時刻は400です。夏時間終了時の重複時刻はmacOSのCalendarが選ぶ時刻を使います。明確に指定する場合はUTCオフセットを付けてください。名前付きゾーンの過去の規則はmacOSの情報を使うため、Windowsと一致するとは限りません。`now`はOSの現在時刻で、開発用パレットの仮想時刻には連動しません。

開発用パレットの「内蔵SAORI」で、モジュールと1行1引数を入力して単体テストできます。空行は空引数です。応答全文と所要時間を画面へ表示しますが、要求や結果本文を自動ログには保存しません。この単体テストは本体を直接呼び、SHIORI接続の検証やゴーストへのイベント送信は行いません。`--async`はghost requiredになります。

「内蔵SAORIの呼び出しを記録」をオンにすると、その後の呼び出しをInternalSAORIカテゴリへ記録します。同期応答・非同期受付・非同期処理結果について、セッション識別子、モジュール、関数、状態コード、所要時間、応答バイト数を確認できます。引数、結果本文、非同期識別子は記録しません。記録は初期状態でオフです。従来のSAORI dylibとWindows DLLの呼び出しは記録対象外です。


### httpc互換モジュール（次回版）

`httpc.dll`を使うゴースト・プラグイン向けに、Utatane Modulesの`httpc`を共通導入できます。
引数なしの接続状態確認、URLからの同期文字列取得、URLと保存先を指定するバイナリ保存、
開始・終了文字列による複数箇所の抽出に対応します。保存先はSAORIの配置フォルダ基準です。
次回版の本体とhttpc 0.1.0-r4以降では、先頭に`bg`、識別子を付けると非同期で実行します。
受付時は空の結果を返し、完了時に呼び出したゴースト・プラグインへ`OnHttpcNotify`を送ります。
Reference0は識別子、Reference1は`-`、Reference2は同期呼び出しの最初の結果です。
抽出で複数箇所に一致した場合は、同期応答のValue0以降、非同期通知のReference3以降へ残りを返します。
抽出は1回の呼び出しで先頭から最大254件を返します。原作readmeのReference1は空欄ですが、原作ソースの実際の通知に合わせています。
ゴーストの終了・再読み込みやSAORIのアンロード後には通知しません。
通常のUtataneネイティブホスト経由で利用でき、Windows DLLホスト経由は対象外です。
華和梨は9.1.0-r5以降へ更新してください。古い版では、元のWindows DLLがないとhttpcなどを内蔵機能と誤認する場合があります。
ダウンロードは32MB、文字列結果はUTF-8で2MBまで、同時受付はホストごとに64件までです。
HTMLタグ変換は未対応です。詳細は[ModulesのSAORI手順](https://github.com/opera7133/utatane-modules/blob/main/docs/saori.md)を参照してください。
