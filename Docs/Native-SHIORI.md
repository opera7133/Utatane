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

## ネイティブMAKOTO

`ghost/master`に`makoto.dll`があり、`makoto.ini`に`[ParticleMakoto]`セクションがある場合は、DLLをロードせずSwift実装を使います。SHIORIが返したSakuraScriptへ、韓国語の語末にパッチムがあるかを判定して`[은]/는`、`[을]/를`、`[이]/가`、`[와]/과`、`[으]로`、`[이]`を変換します。`Makoto1Compatible`で使われる`[은;는]`、`[이;가]`などの旧記法、数字・英字の判定もParticleMakoto 2.3の実DLL応答と照合しています。

現時点ではこのゴースト側ParticleMakotoだけが対象です。任意のMAKOTO DLL、シェル側MAKOTO、`OnTranslate`との組み合わせは未対応です。

## 外部SHIORI

ネイティブ対応に該当しないSHIORIも、macOS用の`.dylib`、`.so`、`.bundle`なら標準ABIで読み込みます。Windowsの`.dll`は`UTATANE_WINE_EXECUTABLE`、`UTATANE_WINE_PREFIX`、`UTATANE_WINDOWS_DLL_HOST`（Debug版では`Content/Local/WindowsDLLBridge/utatane-dll-host.exe`も可）が揃う場合にWineへ渡します。

この経路は一般的なSHIORI/3.0とSAORI/1.0の電文、および標準エントリポイントを扱うものです。Windows固有の補助DLL、レジストリ、COM、別プロセスなどへ依存するモジュールまで動作を保証するものではありません。

## SHIOLINK（外部プロセス）

`descript.txt`の`shiori,shiolink.dll`を検出すると、Windows DLLではなく、設定したmacOSのコマンドへ標準入出力で接続します。DLL本体は不要です。Node.jsやRuby、栞本体は利用者が別途インストールします。Utataneはnpmを自動実行せず、ランタイムも同梱しません。

ゴーストの`ghost/master/SHIOLINK.INI`に設定します。Windows用の設定を残す場合は、優先して読み込む`SHIOLINK.utatane.ini`を同じ場所に置けます。

```ini
[SHIOLINK]
commandline = "/absolute/path/to/node" "./node_modules/miyojs/bin/miyo-shiolink.js" "./dic"
charmode = UTF-8
```

実行ファイルは実在する**絶対パス**に置き換えてください。作業ディレクトリは`ghost/master`です。引数内の相対パスもここを基準に解釈されます。空白を含むパスは引用符で囲みます。シェルは使わず、`~`、`$HOME`、パイプ等は展開しません。`charmode`は`UTF-8`、`ANSI`または`Shift_JIS`を指定します。省略時は元実装と同じ`ANSI`で、日本語Windows相当のShift_JISとして扱います。Node.jsでは`UTF-8`を明示してください。INIはUTF-8またはShift_JISで読み込みます。`LOGGING`や`viewconsole`、DLLの改名に応じたINI名などは再現していません。

### miyojsでの確認

[miyojs](https://github.com/Narazaka/miyojs/blob/master/Readme.ja.md) 2.0.3のCLIと、最小のYAML辞書による日本語の連続応答を確認しています。配布されている各Miyoゴーストの画面操作は未確認です。

検証時は`js-yaml`の新しい版で`jsyaml.safeLoad is not a function`という起動エラーが発生しました。miyojs 2.0.3が古いAPIを利用しているためです。新規の検証用ディレクトリでは、次の組み合わせで動作しました。

```sh
npm install --ignore-scripts miyojs@2.0.3 js-yaml@3
```

既存ゴーストには固有の依存関係やlockfileがある場合があります。このコマンドで一律に上書きせず、ゴーストの導入手順を優先してください。古い依存ライブラリを利用する構成であり、安全性や他のNode.jsバージョンとの互換を保証するものではありません。

### 通信と制限

[ShiolinkJS](https://github.com/Narazaka/shiolinkjs/blob/master/lib/shiolink.ts)の`*L:`、`*S:`、`*U:`プロトコルでload・SHIORI/3.0要求／応答・unloadを行います。通信はUIとは別の専用キューで直列処理します。応答待ちは要求ごとに最大10秒、電文は約8 MiBまでです。異常やタイムアウトで接続を閉じ、同期が崩れたプロセスを再利用しません。再度使うにはゴーストを再読み込みします。

ゴースト終了時はunloadを送って最大1秒待ち、終了しない子プロセスを停止します。標準出力にはプロトコル以外を出せません。診断出力は標準エラーを使います。外部栞のSAORIやWindows固有機能を自動でmacOS対応にする機能ではありません。

**外部プロセスを制限するサンドボックスではありません。** 栞は利用者の権限でファイル操作等を実行できます。保存先も栞側の実装に従います。信頼できるゴースト・コマンドのみ指定し、動作確認にはコピーを使ってください。

## AYA（文）をYAYAで実行

`ghost/master`に`aya5.txt`または`aya.txt`があれば、内蔵YAYAで読み込みます。設定や辞書を`yaya.txt`へ変換する必要はありません。WindowsのAYA DLLは実行しません。YAYA設定が存在する場合はそちらを優先します。

AYA設定で読み込んだ場合は、設定名に対応する`aya5_variable.cfg`または`aya_variable.cfg`を読み書きします。手動ランダムトークではまず`OnAITalk`を送り、成功応答に台詞がなかった場合だけ`OnAiTalk`を試します。通常のYAYA設定ではこの再試行をしません。

作者配布の文5.8「紺野あやめ」で、辞書無改変の起動・トーク・メニュー・終了応答を確認しました。設定名ごとの保存と再読込もテストしていますが、旧AYA全版や全ゴースト、既存の保存ファイル形式すべてとの互換を保証するものではありません。画面操作や外部SAORIの互換性は別途確認が必要です。

## kagari（Lua、実験的）

`shiori,kagari.dll`を指定するゴースト、またはmasterに`kagari.dll`があるゴーストを、macOS用kagariへ接続します。`index.lua`だけでは判定しません。tkytkとは別の経路です。

アプリのDebug／Releaseビルドに、[kagariフォーク](https://github.com/opera7133/kagari_shiori/tree/utatane-macos)とLua共有ライブラリを自動で組み込みます。利用者による追加ビルドは不要です。kagariはsubmoduleの固定コミットを使い、Lua 5.4.9とsol2 3.5.0は固定URLから取得してSHA-256を検証します。

Xcodeのビルドフェーズから`tools/native-shiori/bundle-kagari.py`を実行するため、`mise run build`、Xcodeからのビルド、ローカルReleaseビルド、GitHub Actionsで同じ処理を使います。Debugは対象CPU、配布版はarm64／x86_64の両方をビルドします。初回はネットワーク接続が必要で、ソースのアーカイブとビルド結果は`.generated-native-shiori/`へキャッシュします。取得・検証・ビルドの失敗はアプリのビルド失敗として扱い、同梱を省略して続行しません。

配置先は`Utatane.app/Contents/Resources/NativeShiori/kagari/`です。`libkagari.dylib`、`liblua5.4.dylib`と、kagari・Lua・sol2の著作権表示およびライセンス本文を同梱します。Luaは`@loader_path`基準で読み込むため、Homebrewや開発機の絶対パスには依存しません。

自前のライブラリを優先したい場合は、従来の手動ビルドも利用できます。

```sh
git submodule update --init --recursive
sh tools/native-shiori/build-kagari-macos.sh /path/to/lua-5.4.9 /path/to/sol2-3.5.0
```

手動ビルドでは`~/Library/Application Support/Utatane/NativeShiori/kagari/`へ配置します。既定ではホストのCPU向けにビルドし、`KAGARI_ARCHS="arm64 x86_64"`で両CPU向けにできます。別の出力先は第3引数に指定できます。Utataneはmaster、上記Application Support、アプリ内の順に検索します。`UTATANE_KAGARI_MODULE`でライブラリの絶対パスを最優先に指定することもできます。

`index.lua`は`load`、`request`、`unload`を持つテーブルを返します。純Luaモジュールと、同じLua 5.4 ABI・CPU向けにビルドされたC拡張が必要です。Windows用C拡張DLLをそのまま使えるわけではありません。Lua共有ライブラリはkagariと同じフォルダに置いてください。

`mise run test-kagari`はReleaseアプリ内の両CPU対応、署名、依存パス、ライセンス収録を検査し、別ディレクトリへコピーしたライブラリでSwiftからのロード・日本語応答・複数インスタンス・終了と異常系をテストします。GitHub Actionsでも配布前に同じ検査を実行します。実ロードは実行ホストのCPUで行い、反対側のCPUでの実行まで保証するものではありません。

配布ゴーストやkotori全体の動作は未確認です。Luaの`os`／`io`等は使用可能で、サンドボックスや強制タイムアウトはありません。信頼できるゴーストだけを使ってください。

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
