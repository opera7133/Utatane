# SHIORI・SAORIの利用

SHIORIごとの実行方式・制約とビルド手順は、[Utatane Modulesの資料](https://github.com/opera7133/utatane-modules/blob/main/docs/native-shiori.md)を参照してください。

## SHIORIの選択

### 共通導入版と同梱版

初回起動時にYAYAと里々の共通導入版をカタログから取得します。既に導入済みなら再取得せず、カタログへ接続できなくても起動できます。共通導入版の更新後、起動中のゴーストには再読み込みが必要です。カタログの「導入済み」は共通導入版の状態であり、ゴースト同梱版から切り替わったことを示しません。

ゴーストの`shiori.macos`に指定されたモジュールを優先します。対応する同梱ライブラリの破損や必要な関数の欠落を検出すると、同じSHIORIの共通導入版へ切り替えます。設定の「SHIORI対応状況」でオフにできます。辞書・保存データのエラーでは切り替えません。各SHIORIの配布版は、ゴースト内、共通導入先の順に探します。`ese-shiori.dll`など、対応済みのDLL名が`shiori`にある場合、同じフォルダにdylibを置くだけでUtataneが検出します。

開発版では真絵の`mae_corpus.txt`、D.N.Proxyの`dnproxy.ini`または`dnproxy.dll.config`も判別します。`shiori.dll`という汎用名でも対応する共通導入版を選べます。D.N.Proxyには別途.NET 10ランタイムが必要で、C#ソースの実行時コンパイルにはSDKが必要です。対応範囲はModulesの案内を確認してください。

ゴースト内の`shiori.dylib`も探索します。蒼空などの手動導入は、共通導入先の`<名前>/lib/lib<名前>.dylib`または`<名前>/lib<名前>.dylib`を確認するため、`module.json`がなくても実行を止めません。カタログの版・更新判定にはmanifestが必要です。

真絵で「話すネタが思いつかない」という台詞が繰り返される場合は、mae 0.1.0-r3以降へ更新してください。未定義の翻訳・バルーン終了イベントを発話へ置き換える問題を修正しています。ゴースト内に旧版の`libmae.dylib`がある場合はそちらが優先されるので、同梱版も置き換えてから再読み込みしてください。

Windows DLLだけを持つゴーストは、辞書や設定を判別し、対応するモジュールを導入済みなら接続します。設定の「SHIORI対応状況」で判定を確認できます。動かない場合は「情報」→「SHIORI読み込み診断…」と[診断・報告の手順](Troubleshooting.md#診断と報告)を使ってください。

同梱する側の配置・指定方法は[SHIORI開発ガイド](../Creators/SHIORI-Development.md)、各配布物の導入手順は[Utatane Modules](https://github.com/opera7133/utatane-modules)にあります。

通常のmacOS用SHIORIは、ゴースト・プラグインごとに別プロセスで実行します。応答停止や異常終了を検出した場合、実行済みの処理を重複させないため、自動で要求を再送しません。

### YAYA 5と6の切り替え

YAYAは6系を既定で使います。`yaya.dll`・`aya.dll`・`aya5.dll`のバージョン情報に関係なく、YAYA 6を選びます。6系が未導入なら導入を案内し、5系へ自動では切り替えません。`shiori.macos`の明示指定は引き続き優先します。

YAYA 6を初めて読み込む前に、`ghost/master/`直下の`*_variable.cfg`を`Utatane-YAYA-backup/`へコピーします。既存のバックアップは上書きしません。ゴースト独自の保存ファイルは別途バックアップしてください。

5系は互換用として導入できます。使う場合は5系の`libyaya.dylib`を`ghost/master/`へ置き、`descript.txt`に`shiori.macos,libyaya.dylib`を指定してください。6系でハッシュや入れ子の変数を保存した後に5系へ戻すと、保存内容が崩れることがあります。Utataneを終了して、切り替え前の`*_variable.cfg`をバックアップから戻してから5系を使ってください。復元するとバックアップ後の進行状況は失われます。

## 共通SAORIブリッジ

通常のmacOS用SAORIはdylibです。Windows DLLをそのままmacOSへ読み込むことはありません。

Utataneが提供するSAORIと対応する命令は、[共通SAORIブリッジの一覧](https://github.com/opera7133/utatane-modules/blob/main/docs/native-shiori.md#共通saoriブリッジ)を参照してください。独自の外部SHIORIが読み込むSAORIは、そのSHIORI側で管理します。

### 共通導入できるSAORI

次の表は、このページで扱う主な共通SAORIです。`PlayWavSound`・`totp_saori`・`XPath`・`timebkn`は、0.2.19向けModulesで追加しました。本体0.2.19ではこれらの不足検出・導入案内にも対応します。

| モジュール | 対応内容 | 制限・補足 |
| --- | --- | --- |
| `clipcopy` | 全引数を改行で結合してコピー。文字列中の`\n`も改行へ変換 | macOSのクリップボードを使用 |
| `textcopy` / `textcopy2` | 第1引数をコピー。第2引数が数値で非ゼロなら元の文字列を返す | 第3引数があれば、その区切りをコピー先で改行へ置換 |
| `saori-ip` | `GetLocalIP`・`GetLocalHostname` | `saori_ip.dll`・原作配布名の`ip.dll`に対応。`GetInternetIP`は非対応（501） |
| `httpc` | HTTPの取得・保存・文字列抽出・非同期通知 | 次節に必要な版と制限を記載 |
| `PlayWavSound` | WAVE効果音の再生 | 一部のWindowsシステム音名をmacOSの音へ対応付け。実際の音声出力は手動確認が必要 |
| `totp_saori` | HMAC-SHA1のワンタイムコード | 引数・鍵の形式・桁数等の制限はModulesの資料を参照 |
| `XPath` | XML文書管理・XPathによる取得 | DTD・外部実体は非対応。文書・結果・計算量に上限あり |
| `timebkn` | 通常の日時処理 | `qreki`（旧暦・六曜）は未対応で501を返す |

`saori-ip`のローカルIPは有効な非ループバックIPv4の先頭で、複数NICではWindowsと選択が異なる場合があります。

原版との違い、システム音の対応付け、引数・返却値・制限の詳細は[ModulesのSAORI資料](https://github.com/opera7133/utatane-modules/blob/main/docs/saori.md)を参照してください。原作の全機能との一致を示すものではありません。

### 共有配置と診断に必要なModules

共有配置の名前解決と、SHIORI内部から呼ぶ通常SAORIの診断には、SHIORI側の対応版が必要です。

| SHIORI | 共有配置の名前解決 | 通常SAORIの診断 |
| --- | --- | --- |
| YAYA 5 / 6 | r4以降 | r3以降 |
| 里々 | Mc205-5-r2以降 | Mc205-5-r1以降 |
| 華和梨 | 9.2.0-r2以降 | 9.2.0-r1以降 |
| 忍・灯 | r4以降 | r3以降 |

共通導入版を更新した後は、起動中のゴーストを再読み込みしてください。診断の使い方と対象外の経路は、後述の「通常SAORIの呼び出し記録」を参照してください。

### httpc互換モジュール（0.2.18以降）

`httpc.dll`を使うゴースト・プラグイン向けに、Modulesの`httpc`を共通導入できます。

#### 同期処理

| 引数 | 処理 |
| --- | --- |
| 引数なし | 接続状態の確認 |
| URL | 本文を文字列として取得 |
| URL、保存先 | バイナリのまま保存。相対保存先はSAORIの配置フォルダ基準 |
| URL、開始文字列、終了文字列 | 一致箇所を先頭から最大254件抽出。最初をResult、残りをValue0以降へ返す |

#### 非同期処理

本体0.2.18とhttpc 0.1.0-r4以降では、先頭に`bg`、識別子を付けると非同期で実行します。受付時は空の結果を返し、完了時に呼び出したゴースト・プラグインへ`OnHttpcNotify`を送ります。

| 参照値 | 内容 |
| --- | --- |
| Reference0 | 識別子 |
| Reference1 | `-`（原作readmeの空欄ではなく、原作ソースの実際の通知に合わせる） |
| Reference2 | 同期呼び出しの最初の結果 |
| Reference3以降 | 複数箇所を抽出した場合の残りの結果 |

ゴーストの終了・再読み込み、SAORIのアンロード後には通知しません。通常のUtataneネイティブホスト経由で利用でき、Windows DLLホスト経由は対象外です。

#### HTMLの簡易変換

httpc 0.1.0-r5では、URLの前に`erase_tag`（タグ除去）・`translate_tag`（原作の簡易SakuraScript変換）を文字コード指定と並べられます。両方ある場合は変換が優先です。非同期の`bg`では識別子の後へ置きます。

変換対象は改行・水平線・リンク・画像の代替テキストと一部の文字参照で、完全なHTML解析ではありません。変換結果は原作同様に半角48桁換算・120行を上限に切り詰めます。保存モードはタグ処理せず、元のバイト列を保存します。

#### 制限と必要な版

- ダウンロードは32MB、文字列結果はUTF-8で2MBまで、同時受付はホストごとに64件までです。
- 華和梨は9.1.0-r5以降へ更新してください。古い版では、元のWindows DLLがないとhttpcなどを内蔵機能と誤認する場合があります。

引数・返却値の詳細は[ModulesのSAORI手順](https://github.com/opera7133/utatane-modules/blob/main/docs/saori.md)を参照してください。

## 内蔵SAORI

Utatane 0.2.17以降と次のModulesを組み合わせると、ゴーストへDLLを置かずに内蔵機能を呼べます。以前の本体やModulesにはこの接続がありません。

| SHIORI | 内蔵SAORIの接続に必要な版 |
| --- | --- |
| YAYA 5 | Tc574-11-r2以降 |
| YAYA 6 | Tc607-2-r2以降 |
| 里々 | Mc205-4-r2以降 |
| 華和梨 | 9.1.0-r4以降 |

共通導入版を更新した後は、起動中のゴーストを再読み込みしてください。

### 対応関数

以下はUtatane 0.2.18以降の対応です。0.2.17の`internal_data`はConvertのtext（UTF-8）・hex・base64・base64urlまでです。圧縮・追加形式・文字コード指定、ファイルハッシュ・Compareと`internal_file`は0.2.18で追加しました。


| モジュール| 対応関数 | 制限 |
| --- | --- | --- |
| `internal_system` | `ListModules`、`ListFunctions` | 対応しているモジュール・関数だけを返す |
| `internal_time` | `Format`、`Add`、`Diff` | エポック秒、ISO日時、HTTP IMF-fixdate。local・UTC・±18時間以内のオフセット・macOSのIANAゾーンに対応。Windows名は未対応 |
| `internal_text` | `Normalize` | NFC、NFD、NFKC、NFKD |
| `internal_random` | `Bytes`、`Number`、`UUID` | Bytesは1〜1024バイト、NumberはInt64の閉区間、UUIDはv4/v7 |
| `internal_data` | `Convert`、`Compress`、`Decompress` | text、hex/HEX、base64/base64url、base32、url、bech32。圧縮・展開はgzip/zlib/deflate。brotli/zstdは未対応 |
| `internal_file` | `MediaInfo` | 音声・画像・動画の種類とメタデータ。取得できる項目はmacOSの対応形式による |
| `internal_crypto` | `Digest`、`HMAC`、`Compare` | Digestはmd5/sha1/sha256/sha384/sha512、HMACはsha256/sha384/sha512。dataのfile入力に対応。暗号化・鍵生成等は未対応 |

### 呼び出し方法

引数・返却値の基準は[UKADOCのSAORI over DirectSSTP](https://ssp.shillest.net/ukadoc/manual/spec_saori_ex.html)です。YAYAでは`FUNCTIONEX`または`LOADLIB`／`REQUESTLIB`、里々では`＠SAORI`による登録または`（internal_text、Normalize、NFKC、ｶﾞｲﾄﾞ）`のようなモジュール名の呼び出し、華和梨では`$(callsaori internal_text Normalize NFKC ｶﾞｲﾄﾞ)`を使えます。通常のSAORIでは、引き続きmacOS用モジュールが必要です。

### 非同期通知

`--async=識別子`をオプションに加えると即座に204を返し、結果を`OnInternalSaoriComplete`／`OnInternalSaoriFailure`へGETで通知します。識別子が`On`で始まる場合は、その名前／末尾に`Failure`を加えた名前を使います。Reference0は識別子、1は結果または失敗理由、2はモジュール名、3は関数名、成功時の4以降はValue0以降です。終了・SHIORI再読み込み後には配送しません。同時処理は2〜4件、保留はセッションあたり64件までです。

### 通信方式と上限

macOSでは、SHIORIの専用ホストと本体を結ぶ非公開の親子プロセス通信を使用します。WindowsのHWND／WM_COPYDATA、外部XPC、Socket／HTTP経由のSAORI実行には対応していません。UTF-8とShift_JIS（CP932）、最大256引数、8MiBの要求・応答を扱います。未対応の方式や不正な引数は400、処理失敗は500を返します。表示できないバイト列や改行はbase64等で渡してください。

### データ変換と圧縮

0.2.18以降では`--charset=`でデータの文字コードを指定できます（要求の`Charset`とは別）。
`--out=HEX`は大文字、`--out=hex`は小文字です。同じオプションを複数指定した場合は最後の値を使います。
Base64は通常形式・URL形式、パディングあり・なしを受け付けます。bech32出力はConvertの`--hrp=`が必要です。

`Compress`は方式とデータを位置引数に取り、既定ではBase64を返します。
`Decompress`は方式と圧縮データを取り、既定ではBase64から文字列へ戻します。
`--data-in=`と`--out=`で入出力形式を変えられます。gzipの連結メンバーを読み、
壊れた入力・途中切れ・余分な末尾をエラーにします。展開後も合計8MBが上限です。

### メディア情報

`internal_file`の`MediaInfo`はパス、その後に取得するキーを1〜11個渡します。
`Result`は`audio`/`video`/`image`、`Value0`以降は指定した順の値です。
キーは`title`、`artist`、`albumartist`、`album`、`genre`、`comment`、`year`、`track`、
`duration`（ミリ秒）、`width`、`height`。取れない値や未知のキーは空になります。
相対パスは呼び出したゴーストの`ghost/master`基準です。開発用パレットの単体テストでは絶対パスを使ってください。
改行はバイト値1、NULは除去して返します。未対応形式は種類と値が空です。
この関数の契約は[OurinのMediaInfo提案](https://github.com/eightman999/Ourin/pull/158)も参照しています。

### ハッシュと比較

`internal_crypto`のDigest/HMACで`--data-in=file`を指定すると、データ引数をファイルパスとして読みます。
相対パスは呼び出したゴーストの`ghost/master`基準です。ゴーストなしの単体テストでは絶対パスを使ってください。
ファイルは64KBずつ読み、通常のデータ引数の8MB上限は適用しません。大きなファイルには`--async=識別子`を付けてください。
ファイルが存在しない場合は400 `file not found`、読み取りに失敗した場合は500 `file read failed`です。
読み取り中の切り詰め・サイズや更新時刻の変更も失敗として扱います。
非同期処理中にゴーストを終了・SHIORIを再読み込みすると、読み取りを中断して結果を配送しません。
`file`を使えるのはDigest/HMACのデータ入力だけで、鍵の入力やConvert、Compareには使えません。

`Compare`は2つのデータをOSの内容非依存の比較処理で照合し、一致なら`1`、不一致なら`0`を返します。
`--a-in=hex --b-in=hex`などで入力形式を指定できます。例えば16進の署名は、文字の大小に左右されず照合できます。

## 日時計算と開発用の確認

### 日時計算

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

### 内蔵SAORIの単体テスト

開発用パレットの「内蔵SAORI」で、モジュールと1行1引数を入力して単体テストできます。空行は空引数です。応答全文と所要時間を画面へ表示しますが、要求や結果本文を自動ログには保存しません。この単体テストは本体を直接呼び、SHIORI接続の検証やゴーストへのイベント送信は行いません。`--async`はghost requiredになります。

### 内蔵SAORIの呼び出し記録

「内蔵SAORIの呼び出しを記録」をオンにすると、その後の呼び出しをInternalSAORIカテゴリへ記録します。同期応答・非同期受付・非同期処理結果について、セッション識別子、モジュール、関数、状態コード、所要時間、応答バイト数を確認できます。引数、結果本文、非同期識別子は記録しません。記録は初期状態でオフです。通常SAORIは別の診断設定を使います。

### 通常SAORIの呼び出し記録

「通常SAORIの呼び出しを記録」をオンにすると、SAORIカテゴリで呼び出し元のフォルダ、選択したモジュールのパス、読み込み／呼び出し／終了の状態、所要時間、応答バイト数を確認できます。通常はmacOS用dylibで、Wineが設定されている場合は本体が呼び出すWindows SAORI DLLも対象です。引数・結果本文は記録せず、初期状態はオフです。

既に起動しているセッションでも、その後の要求から切り替わります。独自SHIORIや、Wine内のWindows SHIORIが直接読み込むDLLの内部呼び出しは対象外です。状態`1`／`0`は読み込み・終了の成功／失敗、呼び出しはSAORI応答コードです。本体管理の外部接続の終了など、実際の状態コードを取得できない場合は`unknown`となります。

### 検証範囲

合成辞書と実ゴーストの一時コピーを使い、同期呼び出し・非同期通知・結果イベントの利用をテストしています。元の辞書・保存データは変更しません。各ゴーストの全機能や、両CPUの画面操作を保証するものではありません。

## メーター・システム情報の表示

Utatane 0.2.18では、カラー合成と画像の切り抜きを使うメーター表示を改善しました。CPU・メモリ使用率と空き物理メモリの概算も取得できます。

暦などのデータを外部サイトから取得する場合、表示にはゴースト側の対応も必要です。華和梨の`textload_charset`で文字コードを指定して読み込む辞書には、華和梨9.2.0以降を使用してください。9.1.0ではこの関数を利用できません。
