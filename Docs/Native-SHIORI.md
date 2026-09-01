# Native SHIORI / SAORI

UtataneがmacOS上でSHIORI・SAORIを実行する仕組みと、実装済みの範囲をまとめます。既知のSHIORIはWineを使わない内蔵実装を優先し、それ以外はmacOS用モジュールまたは設定済みWineへ渡します。

## 対応方式の一覧

| SHIORI | 実行方式 | SAORI | 状態 |
| --- | --- | --- | --- |
| YAYA / AYA（文） | 同梱ネイティブ実装 | 共通SAORIブリッジ | 対応 |
| 里々（SATORI） | 同梱ネイティブ実装 | 共通ブリッジ、SSUは里々内蔵 | 対応 |
| 華和梨（KAWARI） | 同梱ネイティブ実装 | 共通SAORIブリッジ | 対応 |
| 美坂（MISAKA） | Swift実装 | 共通SAORIブリッジ | 対応 |
| 灯（AKARI） | Swift実装 | 共通SAORIブリッジ | 実験的 |
| ese-shiori | Swift実装 | 呼び出し構文は未実装 | 対応 |
| 偽栞（NiseShiori） | Swift実装 | 呼び出し構文は未実装 | 対応 |
| 忍（Shino） | Swift実装 | 共通SAORIブリッジ | 対応 |
| 翡翠（Hisui） | Swift実装 | 呼び出し構文は未実装 | 実験的 |
| FIRST（さくら） | 専用Swift人格 | 対象外 | 対応版限定 |
| kagari | 同梱macOSモジュール | kagari / Lua側で管理 | 対応 |
| 蒼空（Aosora） | 利用者が用意するmacOSモジュール | Aosora側で管理 | 実験的 |
| SHIOLINK | 利用者が設定する外部プロセス | 外部SHIORI側で管理 | 対応 |
| その他のmacOS SHIORI | 標準SHIORI ABI | 外部SHIORI側で管理 | 互換経路 |
| その他のWindows SHIORI | 設定済みWine + DLLホスト | 外部SHIORI側で管理 | 互換経路 |

「共通SAORIブリッジ」は、Utatane内蔵SHIORIのうちSAORI呼び出し構文を実装しているものが使う経路です。外部SHIORIの内部動作を横取りするものではありません。

## SHIORIの選択

識別子、別名、代表的なDLL名、実行方式、追加ランタイムの要否は`UtataneCore`のSHIORIカタログで管理しています。設定の「SHIORI対応状況」も同じ情報を表示します。UtataneはSHIORIの検索・ダウンロード・更新は行いません。

既知の名前に一致しない`.dylib`、`.so`、`.bundle`は標準SHIORI ABIの`load`・`request`・`unload`で読み込みます。未知の`.dll`は、Wineと汎用DLLホストが設定済みの場合だけ実行します。SHIOLINKはSHIORI本体ではなく外部プロセスへの接続方式です。似非shioriはese-shioriの別名で、`niseshiori.dll`を使う偽栞とは別物です。

## 共通SAORIブリッジ

`UtataneNativeSaori`はSHIORIから独立したレジストリです。YAYA / AYA、里々、華和梨、美坂、灯、忍は、それぞれの辞書言語にあるSAORI構文をこのレジストリへ接続します。

- `mciaudior.dll`: `load`、`play`、`loop`、`stop`
- `wmove.dll`: `MOVETO`、`MOVETO_INSIDE`、`GET_POSITION`、`GET_DESKTOP_SIZE`
- `textcopy2.dll`: macOSのクリップボードへの書き込み
- `saori_cpuid.dll`: macOS、CPU、メモリ情報の取得
- `kenonoke.dll`: 同じディレクトリの`keyword.txt`による分類

内蔵実装にないモジュールは、macOS用なら標準SAORI ABIで読み込みます。Windows用`.dll`はWineと汎用DLLホストが設定済みの場合だけ同じABIで実行します。相対パスは`ghost/master`内に制限します。

`wmove.dll`はWindows HWNDの代わりにUtataneのサーフェスへ接続します。`MOVE`、`ZMOVE`、`WAIT`、`NOTIFY`、`CLEAR`、`STANDBY`などは未実装です。SSUは里々に含まれる実装を使います。

## 内蔵SHIORI

### YAYA / AYA（文）

`yaya.txt`を持つゴーストは内蔵YAYAで実行します。`aya5.txt`または`aya.txt`もWindows DLLを使わず読み込みます。AYA設定では対応する変数ファイルを読み書きし、手動トークは`OnAITalk`の空応答時だけ`OnAiTalk`を試します。

文5.8「紺野あやめ」で、起動・トーク・メニュー・終了・保存と再読込を確認しています。旧AYAの全版との完全互換は保証しません。

### 里々（SATORI）

同梱ネイティブ実装をSwiftから利用します。SAORI要求は共通ブリッジへ渡し、SSUだけは里々内蔵実装を使います。

### 華和梨（KAWARI）

64-bit macOS向け修正を含むforkの`utatane-macos`ブランチをsubmoduleとして利用します。

```sh
git submodule update --init --recursive
mise run test --filter NativeKawariSessionTests
```

### 美坂（MISAKA）

`misaka.dll`をロードせず、Shift_JIS辞書をSwiftで解釈します。配列、採用条件、選択方式、整数演算、変数保存、自発会話、プロパティハンドラ、主要システム変数に対応しています。

ログと変数はApplication Supportへ保存します。`daysfromlastupdate`はmasterの更新日時による近似値、`hwnd.*`は互換用ダミー値です。暗号化辞書`.__1`は未対応です。

### 灯（AKARI、実験的）

`akari.dll`をロードせず、`res/*.txt`、`.azr`、`amb.exe` 1.1形式の`main.amb`を解釈します。イベント、トーク、ジャンプ、単語群、変数、主要な制御文・式・組み込み関数に対応しています。

ファイル操作はゴースト領域からの読み込みとApplication Support内への書き込みに制限します。`_saoriload`、`_saorirequest`、`_saoriunload`は共通SAORIブリッジへ接続します。例外、クラス、SSTP、プロセス・スレッド、FTP・メールなどは未対応です。

### ese-shiori（似非SHIORI）

`eseai.ini`がある場合は`ese-shiori.dll`よりSwift実装を優先します。難読化・平文辞書、イベント、レスポンス、条件、変数・スタック、定期会話、ゴースト間会話を扱い、状態と書き込み先はApplication Supportへ分離します。

偽さくら Rebirth 2.008で主要操作と再読込、Materia形式ニュースを確認しています。現行の辞書評価器にはSAORI呼び出し構文を実装していません。

### 偽栞（NiseShiori）

`niseshiori.dll`と`ai*.txt`または`ai*.dtx`を持つゴーストではSwift実装を優先します。複数の文字コードと暗号化形式を読み、イベント、条件、ランダムトーク、ニュース、主要メタ文字列を評価します。状態はApplication Supportへ保存します。

単語間チェイン、`\ft`による文章分解、TEACH全体、Windows固有情報などは完全互換ではありません。現行の辞書評価器にはSAORI呼び出し構文を実装していません。

### 忍（Shino）

`shino.dll`をロードせず、Shift_JISの`ai*.txt`からイベント、ジャンプ、リソース、ユーザ関数、単語群を読みます。条件分岐、変数、選択肢、サブルーチン、ランダムトーク、主要システム関数に対応し、状態はApplication Supportへ保存します。

`%saori`と`%saoriresult`は共通SAORIブリッジへ接続します。こだま（`kodama_alpha`）で起動、偽AIトーク、クリック、メニュー、選択肢ジャンプを自動テストし、Debug版での会話も確認されています。

一部コマンド、日時判定書式、ビットシフト、Windowsのプロセス・HWND・詳細なシステム情報は未対応です。

### 翡翠（Hisui、実験的）

`hisui.dll`をロードせずSwift実装を使います。現時点では`gosji_06`の辞書読込と起動応答を中心に対応しており、言語機能の網羅は未完了です。SAORI呼び出し構文もまだ実装していません。

### FIRST（さくら）

「さくらとうにゅう」のオリジナル版firstには専用人格を使います。利用者が配置した`first.dll`からCP932文字列、PEリソース`AITXT/101`、初期値だけを読み取り、DLL自体は実行しません。会話本文やMateria本体は同梱しません。

起動、ランダムトーク、終了、クリック、選択肢、ゲーム、睡眠・入浴状態、着せ替え、更新などをUtataneのUIへ接続しています。対応版はPE情報で判定します。Materia依存のニュース、メール、利用率グラフ、Windows操作などは対象外です。

## 外部・モジュール型SHIORI

以下はSHIORI自身がSAORIをロードします。Utataneの共通SAORIブリッジへ自動転送はしません。

### kagari（Lua）

`shiori,kagari.dll`またはmaster内の`kagari.dll`を検出し、同梱したmacOS用kagariへ接続します。Debugは対象CPU、配布版はarm64 / x86_64向けにビルドします。master、Application Support、アプリ内の順で検索し、`UTATANE_KAGARI_MODULE`でも上書きできます。`mise run test-kagari`で同梱物と実ロードを検査します。

kagari / kotoriのSAORIローダーはLua側の仕組みで、共通SAORIブリッジとは別です。Windows用C拡張やSAORI DLLをそのまま実行できるわけではありません。Luaはサンドボックス化されません。

### 蒼空（Aosora、実験的）

上流のライセンス条件により、ソースやビルド済みモジュールは同梱しません。利用者がmacOS用モジュールを用意し、標準では次へ配置します。

```text
~/Library/Application Support/Utatane/NativeShiori/aosora/libaosora.dylib
```

別の場所は`UTATANE_AOSORA_MODULE`で指定できます。ビルド補助は`tools/native-shiori/build-aosora-macos.sh`にあります。詳細は[上流リポジトリ](https://github.com/opera7133/aosora-shiori)を確認してください。

### SHIOLINK

`shiori,shiolink.dll`を検出すると、`SHIOLINK.INI`または優先される`SHIOLINK.utatane.ini`のコマンドへ標準入出力で接続します。

```ini
[SHIOLINK]
commandline = "/absolute/path/to/node" "./node_modules/miyojs/bin/miyo-shiolink.js" "./dic"
charmode = UTF-8
```

実行ファイルは絶対パスで指定します。作業ディレクトリは`ghost/master`で、シェル展開は行いません。要求待ちは最大10秒、電文は約8 MiBまでです。miyojs 2.0.3と最小YAML辞書で日本語応答を確認しています。外部プロセスはサンドボックス化されません。

### 汎用モジュール

macOS用SHIORIは標準ABIで直接読み込みます。Windows用SHIORI / SAORIは、`UTATANE_WINE_EXECUTABLE`、`UTATANE_WINE_PREFIX`、`UTATANE_WINDOWS_DLL_HOST`が揃う場合にWineへ渡します。Debug版では`Content/Local/WindowsDLLBridge/utatane-dll-host.exe`も利用できます。

標準的なSHIORI/3.0・SAORI/1.0の電文とエントリポイントが対象です。補助DLL、レジストリ、COM、別プロセスなどWindows固有機能までは保証しません。

## MAKOTO

`makoto.dll`と`makoto.ini`の`[ParticleMakoto]`を検出すると、DLLをロードせずSwift実装を使います。韓国語のパッチムを判定し、助詞記法をSHIORI応答上で変換します。現時点ではゴースト側ParticleMakotoだけが対象です。

## 検証範囲

自動テストはパーサー、イベント応答、状態分離、SAORIブリッジ、外部ABIなどを対象にしています。実ゴースト名を記した項目以外は、すべての辞書分岐や外部モジュールを実機操作で確認したという意味ではありません。Wine、利用者が用意するモジュール、ネットワーク、macOS UIとの結合は別途実行時の確認が必要です。
