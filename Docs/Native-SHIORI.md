# Native SHIORI / SAORI

なるべくWineを使わずにゴーストを動かすための話です。既知のSHIORIとSAORIはUtataneのネイティブ実装を優先し、未知のモジュールには標準ABIのmacOS dynamic libraryと、設定済みWineホストによるWindows DLLの経路があります。

## 共通ネイティブSAORI

`UtataneNativeSaori`はSHIORIから独立したSAORIレジストリです。ネイティブMISAKA、YAYA、SATORI、KAWARIは、それぞれの既存SAORI呼び出し構文を変えずに同じレジストリへ要求を渡します。

- `mciaudior.dll`: `load`、`play`、`loop`、`stop`
- `wmove.dll`: `MOVETO`、`MOVETO_INSIDE`、`GET_POSITION`、`GET_DESKTOP_SIZE`
- `textcopy2.dll`: macOSのクリップボードへの書き込み
- `saori_cpuid.dll`: macOS、CPU、メモリ情報の取得
- `kenonoke.dll`: モジュールと同じディレクトリの`keyword.txt`による分類

`wmove.dll`のWindows HWNDは使用せず、さくら側をスコープ0、相方側をスコープ1としてUtataneのサーフェスウィンドウへ接続します。未実装なのは`MOVE`、`ZMOVE`、`WAIT`、`NOTIFY`、`CLEAR`、`STANDBY`などです。

SSUはSATORIに同梱された既存実装を使います。`saori_cpuid.dll`と`kenonoke.dll`はSATORI固有実装から共通レジストリへ移し、SATORIの既存呼び出し構文からも同じ実装を利用します。

内蔵実装にないSAORIは、`.dylib`、`.so`、`.bundle`なら標準の`loadu/load`・`request`・`unload` ABIで読み込みます。`.dll`はWineと汎用DLLホストを設定している場合だけ同じABIを介して実行します。相対パスはゴーストのmasterディレクトリ内に制限します。

## 外部SHIORI

ネイティブ対応に該当しないSHIORIも、macOS用の`.dylib`、`.so`、`.bundle`なら標準ABIで読み込みます。Windowsの`.dll`は`UTATANE_WINE_EXECUTABLE`、`UTATANE_WINE_PREFIX`、`UTATANE_WINDOWS_DLL_HOST`（Debug版では`Content/Local/WindowsDLLBridge/utatane-dll-host.exe`も可）が揃う場合にWineへ渡します。

この経路は一般的なSHIORI/3.0とSAORI/1.0の電文、および標準エントリポイントを扱うものです。Windows固有の補助DLL、レジストリ、COM、別プロセスなどへ依存するモジュールまで動作を保証するものではありません。

## MISAKA

MISAKAは`misaka.dll`をロードせず、Shift_JIS辞書をSwift実装で解釈します。配列、採用条件、`#_Common`、`nonoverlap`、`sequential`、整数演算、変数の自動保存、`$_talkinterval`による自発会話、プロパティハンドラ、主要システム変数を実装しています。

`misaka.ini`の`debug`、`debugsaori`、`error`も扱います。ログはゴーストの配布物を変更しないよう、変数JSONと同じUtataneのApplication Support内へ出力します。`daysfromlastupdate`はUtataneの更新履歴をSHIORIへ直接渡していないため、現在はmasterディレクトリの更新日時による近似値です。Windows HWNDは存在しないため、`hwnd.*`は互換用のダミー値です。

未対応なのは`misakac.exe`が生成する暗号化辞書`.__1`です。

## 灯（akari、実験的）

`shiori,akari.dll`を指定するゴーストは、Windows DLLを実行せずSwift実装のAKARIエンジンで読み込みます。平文の`res/*.txt`と`.azr`に加え、`amb.exe` 1.1で生成された`main.amb`にも対応しています。

### イベント資源と変数

イベント（`＊`）、トーク候補（`・`）、条件・無条件ジャンプ（`＞`）、単語群（`＠`）、`Reference`置換、話者区切り（`：`）、半角・全角のサーフェス番号を解釈します。SHIORIイベントと同名のAZR関数を直接呼び出す形式も扱います。

`res/init.txt`とAZRのグローバル変数を読み込み、整数、実数、文字列、配列、辞書、nilを区別して保持します。配列リテラル`{...}`と辞書リテラル`${$(key,value),...}`はネストでき、関数引数や保存値にも使用できます。

変更された変数はゴースト本体へ書き戻さず、UtataneのApplication Support内にJSONで保存します。次回起動時は初期値へ保存値を重ねて復元し、時刻など実行時に更新される変数は保存対象から除外します。

### AZR

関数定義、型付き引数、ローカル・グローバル・`static`変数、代入、`return`、`if / else`、`for`、`while`、`switch / case / default`、`break / continue`を解釈します。制御文の本体は波括弧の有無を問いません。関数呼び出しとループには実行上限があり、終了しないスクリプトを打ち切ります。

式は算術、比較、論理、三項・ビット演算、文字列結合、キャスト、`++ / --`、複合代入、配列・辞書の添字参照と代入を扱います。組み込み関数は文字列、配列・辞書、乱数、数学、時刻、JSON、Base64、MD5、正規表現、全半角変換、書式化、トークナイズなど、ゴーストで利用される副作用の小さい処理を中心に実装しています。`_fncstr`による動的関数呼び出しと、ゴースト領域内に限定した`_script_load`にも対応しています。

### `main.amb`

平文スクリプトがない場合は`main.amb`を読み込みます。対応形式は、バージョン1と`AZ-MaterialBox`ヘッダーに続き、埋め込みパスとzlib圧縮データがEOFまで並ぶコンテナです。暗号化された形式ではありません。

`amb.exe` 1.1による単一・複数エントリを実測し、AZRのみ、TXTとAZRの混在、空ファイルを含む構成で確認しています。読み込み時はエントリ数、パス長、圧縮・展開サイズ、zlibのAdler-32を検証し、展開した`.txt`と`.azr`だけを通常のパーサーへ渡します。埋め込みパスは拡張子の判定にのみ使い、ホスト側のファイルアクセスには使用しません。

### 外部機能と安全境界

ファイル関数は`_readtext`、`_writetext`、`_isfile`、`_fenum`、`_abspath`、`_readcsv`、`_savecsv`、`_vsave`、`_vload`とコピー・移動・作成・削除に対応しています。相対パスはゴーストmasterから読み、変更分はApplication Support内の専用領域へ保存します。絶対パス、ドライブ指定、`..`、領域外を指すシンボリックリンクは拒否し、ゴーストの配布物へ直接書き込みません。削除と移動は専用領域にある項目だけが対象です。テキストはUTF-8とShift_JIS、改行はLFとCRLFを扱います。

`_saoriload`、`_saorirequest`、`_saoriunload`は他のネイティブSHIORIと同じSAORIレジストリへ接続します。IDを付けたuniversal SAORIと、パスを直接指定するbasic SAORIの呼び出し形式を扱い、結果を`Result`と`ValueN`の辞書で返します。内蔵実装にないモジュールは、上記の外部SAORI経路を利用できます。

`_httpget`はHTTP/HTTPSの2xx応答を同期取得し、Shift_JIS、UTF-8、EUC-JP、ISO-2022-JPを行配列へ変換します。本文は1MB、待機は15秒までです。`_http_download`は8MBまで取得し、ファイル関数と同じApplication Support内の専用領域へ保存します。リダイレクト後もHTTP/HTTPS以外は拒否します。

例外、クラスなどの構文、SSTP、プロセス・スレッド、FTP・メールなどの副作用を持つ関数は未対応です。未知のインライン関数や未対応文を含む処理は、途中までの結果を返さず、グローバル変数の変更も巻き戻して応答なしにします。

`main.amb`を含む基本的な読み込み経路は実装済みですが、すべての灯ゴーストや灯製プラグインとの完全互換を保証するものではありません。特に外部DLLやWindows固有機能へ依存するコンテンツは対象外です。

## Materia first (さくら)

「さくらとうにゅう」のオリジナル版firstには専用のネイティブ人格実装があります。`first.dll`をmacOSでロードしたり実行したりせず、利用者が配置したDLLから次のデータだけを読み取ります。

- Delphi形式で埋め込まれたCP932文字列
- PEリソース`AITXT/101`に入っている会話用レコード
- `ghost/master/var/first.txt`の`mastertalkinterval`と`energy`初期値

Utatane自身は`first.dll`、会話本文、Materiaの実行ファイルを同梱・再配布しません。会話は起動時に利用者のDLLから取り出し、解析済みの制御フローに沿って組み立てます。

現在は以下を実装しています。

- 時刻別の起動会話、通常のランダムトーク、終了会話
- さくら・うにゅうのダブルクリック、さくらの胸クリック
- 選択肢のキャンセルとタイムアウト、マウス操作説明、ゲーム、眠気レベル
- ゴースト、シェル、バルーンの変更とfirst側の反応
- 眠気、睡眠、起床、夜間の入浴と状態別サーフェス・メニュー
- `mastertalkinterval`に基づく自発会話
- energyと最終入浴日をUtataneのApplication Supportへ分離保存

ゴースト・シェル・バルーンの選択はMateria固有のウィンドウを再現せず、Utataneの独立したmacOS選択ウィンドウへ接続しています。ネットワーク更新もUtataneの更新機能を利用します。

解析済みの版かどうかはPEヘッダーのtimestamp、image size、file sizeで厳密に判定します。一致しないDLLには既知アドレスを適用しません。配布版はMateria用Wine互換ホストを含まないため、ネイティブ非対応版のFIRSTは起動できません。

未対応または対象外なのは、Materia本体に依存するニュース・おすすめ・ポータル・メール・利用率グラフ、Windowsの最小化・終了・再起動などです。一般のWindows SHIORIをこの仕組みで動かせるわけではありません。

Wine経路と`tools/materia-shiori-host`は、実物の挙動を観測して解析を続けるための開発用ツールとしてソースだけを残しています。ローカルで明示的にビルドし、環境変数で指定することはできますが、製品機能としての互換性は保証しません。

## KAWARI

KAWARIはsubmoduleです。`packages/kawari-native/Sources/CKawariNative/Vendor/KAWARI`にいます。

```sh
git submodule update --init --recursive
mise run test --filter NativeKawariSessionTests
```

64-bit macOS向け修正はforkの`utatane-macos`ブランチにあります。

## Aosora（実験的）

Aosoraのソースはライセンスが未設定で、上流READMEでは個人利用またはプロジェクト参加目的に用途が限定されています。なのでUtataneにはソースもsubmoduleもビルド済みモジュールも入れません。[上流リポジトリ](https://github.com/opera7133/aosora-shiori)を確認してください。

<details>
<summary>macOSでのローカルビルド手順</summary>

依存パッケージを入れて、上流をcloneして、付属スクリプトへ渡します。

```sh
brew install pkg-config openssl@3 jsoncpp
git clone --branch utatane-macos https://github.com/opera7133/aosora-shiori.git ~/src/aosora-shiori
tools/native-shiori/build-aosora-macos.sh ~/src/aosora-shiori
```

`utatane-macos`には、macOSで見つかった実行スタック初期化の修正が入っています。上流へ取り込まれたら普通の上流版へ戻す予定です。

標準の配置先は次の場所です。

```text
~/Library/Application Support/Utatane/NativeShiori/aosora/libaosora.dylib
```

別の場所へ置きたい場合は、`UTATANE_AOSORA_MODULE`へ絶対パスを指定します。

```sh
UTATANE_AOSORA_MODULE=/path/to/libaosora.dylib open Utatane.app
```

`Content/Local/Ghosts/demo`があれば、次のテストで起動とメニュー項目の応答まで確認できます。素材かモジュールがなければ何もせず終わります。

```sh
mise run test --filter 'installed Aosora demo answers OnBoot'
```

</details>
