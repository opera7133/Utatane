# SHIORI開発者向け：Utatane対応ガイド

自作SHIORIを新しく作る人と、既存のWindows向けSHIORIをUtataneでも動かしたい人向けの手順です。ゴーストの構成・NARの作成は[コンテンツ制作ガイド](Content-Authoring.md)、既存エンジンの対応範囲は[Native SHIORI / SAORI](../Support/Native-SHIORI.md)を参照してください。

ここで説明する関数の型と通信条件は、現在のUtatane実装に基づきます。kagari・蒼空の専用ABIと、独自SHIORI用の汎用ABIは別です。Utataneへの接続を確認できても、SSPとの完全互換を確認したことにはなりません。

## 新しく作る場合

まず、辞書評価部とベースウェアへの接続部分を分けます。入力をSHIORI電文、出力をSHIORI応答として扱えるようにすると、Windows DLL、macOSモジュール、外部プロセスで同じ評価部を使えます。

| 方式 | 向いている用途 | Utataneで必要なもの |
| --- | --- | --- |
| macOS用モジュール | C / C++などで実装し、ゴーストに同梱して配布します | Mach-Oの`.dylib`、`.so`、`.bundle`と、以下の汎用ABI |
| SHIOLINK | スクリプト言語や別プロセスで開発・検証します | 実行可能なプログラム、SHIOLINK通信、利用者ごとのコマンド設定 |
| Windows DLL | Windows版の先行開発 | WineとDLLホストの追加設定。通常のmacOS向け配布には別途移植を検討 |

`.dll`を`.dylib`へ改名しても動きません。`.so`でもmacOS用の実体が必要です。新しい独自SHIORIには独自の名前を付け、既知SHIORIのDLL名・辞書ファイル名を識別用に流用しないでください。Utataneは汎用モジュールの読み込みより先に、内蔵エンジンや専用経路を判定します。

## 既存SHIORIを対応させる場合

1. SHIORI電文の解析と辞書評価を、Windows API・DLLエントリポイントから分離します。
2. Windows用の`HGLOBAL`などを使う受け渡し部分を、macOS用のC ABIに置き換えます。
3. レジストリ、COM、HWND、外部EXE、依存SAORIを洗い出し、macOS用実装または代替動作を用意します。
4. 最初はmacOS用ファイル名を明示したテスト用ゴーストで、読み込みと短い応答を確認します。
5. 同じ辞書・状態データを両OSで使えるか確認し、最後に配布構成を決めます。

両OS向け配布は、次の`shiori.macos`指定でロード先を分けられます。SHIOLINKならWindows用の`SHIOLINK.INI`を残し、Utatane用の`SHIOLINK.utatane.ini`で起動設定を分けられます。

## WindowsとmacOSを同じゴーストで配布する

`shiori.macos`はUtatane 0.2.4以降で利用できます。配布するゴーストのREADMEにも、必要なUtataneのバージョンを書いてください。

`ghost/master/descript.txt`にWindows用の`shiori`を残し、Utatane向けの追加指定を書きます。

```text
charset,UTF-8
shiori,example.dll
shiori.macos,libexample.dylib
```

```text
ghost/master/
├── descript.txt
├── example.dll          Windows用
├── libexample.dylib     macOS用（arm64 / x86_64）
└── dictionary.txt      共通の辞書
```

`shiori.macos`はUtataneの拡張です。Windows側には従来どおり`shiori`でDLLを指定します。SSP側の読み込みと辞書の文字コードは、完成した配布物で別途確認してください。

- 空でない`shiori.macos`があると、Utataneはその指定を内蔵エンジン・辞書形式の自動判定より優先します。
- 指定できるのは汎用ABIのmacOS用`.dylib`、`.so`、`.bundle`、またはSHIOLINKの`shiolink.dll`です。kagari・蒼空の専用ABIを汎用ABIとして読み込む指定には使えません。
- macOS用モジュールはmaster内の相対パスで指定します。例えば`modules/libexample.dylib`です。絶対パスやmaster外へのパスは使えません。
- 指定先が存在しない・読み込みに失敗する場合はエラーになります。Windows DLLや内蔵エンジンへ自動的に戻りません。
- 指定がない、または空の場合は従来の`shiori`（旧形式では`alias.txt`）と内蔵エンジンの判定を使います。
- `example.dll`から`example.dylib`や`libexample.dylib`を推測する探索は行いません。

Windowsの32-bit DLLとmacOSの64-bitモジュールでも、辞書とSHIORI電文の意味は共有できます。文字コード・整数の幅・保存データの形式をOSごとに変えていないか確認してください。macOS用SHIORIを同梱しても、Windows専用SAORIや外部EXEが自動的に移植されるわけではありません。

## Windows環境しか持っていない場合のビルド

### GitHub ActionsのmacOS環境で作る

手元で編集してGitHubへソースを送れば、macOSランナー上でビルドし、成果物をWindowsからダウンロードできます。Macを所有していなくてもこの経路を使えます。ランナーのラベルとCPUの対応は[GitHubの公式一覧](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)で確認してください。

ただし、Windows APIに依存するソースがそのまま通るわけではありません。先にmacOS用ABIとOS依存部分を実装します。C / C++なら、例えば共通の辞書評価部とOS別の受け渡し部分を次のように分けられます。

```text
src/
├── core.cpp             電文解析・辞書評価
├── shiori_windows.cpp   Windows用DLL ABI
└── shiori_macos.cpp     このページのmacOS用ABI
```

この構成に合わせた`CMakeLists.txt`の例です。実際のファイル名・依存ライブラリ・エクスポート設定は自分のプロジェクトに合わせます。

```cmake
cmake_minimum_required(VERSION 3.20)
project(example LANGUAGES CXX)
if(WIN32)
  add_library(example SHARED src/core.cpp src/shiori_windows.cpp)
  set_target_properties(example PROPERTIES PREFIX "")
elseif(APPLE)
  add_library(example SHARED src/core.cpp src/shiori_macos.cpp)
else()
  message(FATAL_ERROR "This example supports Windows and macOS")
endif()
target_compile_features(example PRIVATE cxx_std_17)
```

次の例を、制作者のリポジトリの`.github/workflows/build-shiori-macos.yml`へ置きます。ビルドしたファイルはActionsからダウンロードでき、リリースとしては公開しません。

これは設定の雛形です。自分のソースや依存ライブラリに合わせて調整し、Actions上で成功することを確認してください。掲載例のGitHub上での実行は未確認です。

```yaml
name: Build macOS SHIORI
on:
  workflow_dispatch:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v6
      - name: Configure
        run: >-
          cmake -S . -B build-macos
          -DCMAKE_BUILD_TYPE=Release
          '-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64'
          -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
      - name: Build
        run: cmake --build build-macos --config Release
      - name: Inspect
        run: |
          lipo -archs build-macos/libexample.dylib
          nm -gU build-macos/libexample.dylib
          otool -L build-macos/libexample.dylib
      - uses: actions/upload-artifact@v7
        with:
          name: example-macos
          path: build-macos/libexample.dylib
          if-no-files-found: error
```

GitHubのActions画面で成功した実行を開き、`example-macos`のartifactをダウンロードして展開し、`ghost/master`へ入れます。CMakeのUniversal Binary指定は[CMAKE_OSX_ARCHITECTURES](https://cmake.org/cmake/help/latest/variable/CMAKE_OSX_ARCHITECTURES.html)、最低OS指定は[CMAKE_OSX_DEPLOYMENT_TARGET](https://cmake.org/cmake/help/latest/variable/CMAKE_OSX_DEPLOYMENT_TARGET.html)、成果物の受け取りは[upload-artifactの説明](https://github.com/actions/upload-artifact)を参照してください。

この例の14.0は現在のUtataneの最低OSに合わせた値です。依存ライブラリがより新しいOSを要求するなら、その条件も配布説明へ書きます。すべての依存ライブラリにも両アーキテクチャが必要です。単独のCPUでしか作れない依存がある場合は、CPUごとのビルドを用意してから配布形式を決めます。

### 手元のWindowsでクロスコンパイルする

macOS用のコンパイラ・リンカー・SDKを用意すればクロスコンパイルという選択肢もあります。例えば[OSXCross](https://github.com/tpoechtrager/osxcross)はLinux / BSD向けのmacOSクロスツールチェーンです。WSLなどを使う場合も、SDKの用意と依存ライブラリのクロスビルドが必要になります。

MSVCで作ったDLLの改名や、CPU指定の追加だけではmacOS用モジュールになりません。まずはmacOSランナーを使い、クロス環境の保守が必要になったときに検討すると手順を分けやすくなります。

### Macがなくても確認できる範囲

Windowsで共通の辞書評価部をテストし、macOSランナーでコンパイル・公開シンボル・依存ライブラリ・ABI呼び出しを検査できます。Apple SiliconとIntelの実行確認は、それぞれのCPUのランナーで別に行います。Universal Binaryをビルドしただけで両CPUで実行したことにはなりません。

Utataneでの表示、イベント順序、マウス操作、再読み込み、配布物の読み込みは、Mac利用者へテストを依頼するか、利用できるMac環境で確認します。依頼時は完成したNAR、Utataneの対象バージョン、確認する操作、期待する会話、ログの取得方法をまとめます。

## プログラミング言語ごとの接続方法

どの言語でも、公開する関数の型、整数の幅、メモリの受け渡しをUtataneに合わせる必要があります。ここが合っていれば、辞書を評価する処理には好きな言語を使えます。

以下は接続方法の一覧です。各言語のSHIORIをすべてUtataneで実行確認した一覧ではありません。

| 言語 | macOSモジュールとして作る場合 | 外部プロセスとして作る場合 |
| --- | --- | --- |
| C / C++ | macOSのClangで共有ライブラリを作ります。C++の公開関数には`extern "C"`を使い、例外はABIの外へ出しません。Windows用の受け渡し部分とは分けます | 通常の実行ファイルにSHIOLINKの入出力を追加します |
| Rust | `cdylib`と`extern "C"`を使います。整数は`i32`、応答はCの`malloc`で確保した領域にします。`Vec`や`CString::into_raw`をそのまま渡すことはできません | 通常のバイナリにSHIOLINKを実装します。C ABI向けのメモリ確保は不要です |
| Go | cgoと`-buildmode=c-shared`を使います。応答はC側のメモリへコピーし、Goが管理するポインタは返しません。クロスビルドにはCクロスコンパイラも必要です | 実行ファイルにSHIOLINKを実装し、純Goの処理とOS依存の処理を分けます |
| C# / .NET | Native AOTの共有ライブラリと`UnmanagedCallersOnly`を使う方式です。応答はmacOSの`free`と互換な領域へコピーします。通常の管理DLLは直接ロードできません | .NETランタイムを必要とする方式か、自己完結の実行ファイルかを選び、SHIOLINKを追加します |
| Swift | C互換の公開関数を用意します。Swiftの`String`や`Int`を直接公開せず、32-bit整数と生ポインタに変換します。C連携とランタイム依存の確認も必要です | macOS用の実行ファイルにSHIOLINKを追加します |
| Python / JavaScript / Luaなど | スクリプトを`.dylib`に改名しても読み込めません。直接ロードするなら、インタプリタを埋め込むC ABI層とランタイムの管理が必要です | インタプリタやパッケージ化した実行ファイルでSHIOLINKを実装します。実行ファイルの絶対パスと必要なランタイムを案内します |

Rustは[公式FFIガイド](https://doc.rust-lang.org/nomicon/ffi.html)、Goは[ビルドモード](https://go.dev/cmd/go/)と[cgoの制約](https://go.dev/cmd/cgo/)、.NETは[Native AOTライブラリ](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/libraries)と[ネイティブ連携](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/interop)、Swiftは[公式C連携の説明](https://developer.apple.com/documentation/swift/c-interoperability)を参照してください。関数名が公開できても、Utataneの所有権の契約を満たさなければ正常に動きません。

## macOS用モジュールの配置とABI

テスト用ゴーストの`ghost/master`へ配置し、同じ場所の`descript.txt`で指定します。ゴースト全体には通常のシェルなども必要です。

```text
ghost/master/
├── descript.txt
├── libexample.dylib
└── dictionary.txt
```

```text
charset,UTF-8
shiori,libexample.dylib
```

汎用ローダーは次のC互換関数を検索します。C++では`extern "C"`を使い、名前修飾されないシンボルを公開します。他の言語でも同じ呼び出し規約・型・メモリ所有権が必要です。

```c
#include <stdint.h>

int32_t loadu(void *directory, int32_t length);
/* loaduがない場合だけ、同じ型のloadを使用する */
int32_t unload(void);
void *request(void *message, int32_t *length);
```

| 関数 | 現在のUtataneからの呼び出し |
| --- | --- |
| `loadu` / `load` | UTF-8のmasterディレクトリと、そのバイト数を渡します。非0で成功、0で失敗 |
| `request` | UTF-8の要求を渡します。`*length`は入力時に要求のバイト数、出力時に応答のバイト数。応答バッファを返します |
| `unload` | セッション破棄時に呼びます。戻り値は現在使用しません |

**汎用経路では`load`を使ってもUTF-8です。** `loadu`がある場合はそちらを優先します。`load`・`request`・`unload`の呼び出し中は、作業ディレクトリも`ghost/master`になります。ただし、複数ゴーストを同時に動かせるよう呼び出し後は元へ戻すため、モジュールが独自に起動したバックグラウンド処理では`load`へ渡されたパスを使ってください。ディレクトリ文字列の末尾に`/`があることを前提にせず、パス結合で辞書を開くと安全です。

### バッファの所有権

- ディレクトリと要求は、Utataneが`malloc`で確保してモジュールへ所有権を渡します。モジュール側で読み取り後に`free`するか、保持して後で解放します。
- 入力のNUL終端は保証されません。`strlen`やNUL終端文字列用のコンストラクタで直接読まず、渡された長さでコピー・解析します。
- 応答は`malloc`など、macOSの`free`で解放できる領域に置きます。Utataneが読み取り後に解放します。静的領域、スタック、`new[]`で確保した領域を返さないでください。
- 長さは文字数ではなくバイト数です。応答にNULを付ける場合も、電文の長さにはそのNULを含めません。
- 会話がない場合も、NULLポインタではなく有効なSHIORI応答を返します。NULLは要求の失敗として扱われます。

呼び出しはセッション内で直列化されますが、同じモジュールの複数セッションを識別するIDは、この汎用ABIにはありません。静的・グローバル状態を使う実装は、複数ゴーストの同時利用と再読み込みで状態が混ざらないか確認してください。モジュールはアプリ内で実行されるため、クラッシュやメモリ破壊はUtatane本体へ影響します。

### ビルドと読み込みの確認

Utataneの「情報」→「SHIORI読み込み診断…」で、対象ゴーストの指定、CPU、公開シンボル、依存ライブラリと、このアプリ起動中の実際の初期化結果をまとめて確認できます。「再診断」は静的検査だけをやり直し、SHIORIを追加でロードしません。変更したモジュールの動作確認には「機能」→「復旧操作」→「現在のゴーストを再読み込み」を使います。[診断と報告](../Support/Troubleshooting.md#診断と報告)も参照してください。

Apple Siliconではarm64、Intelではx86_64が必要です。両方へ配布する場合はUniversal Binaryを作り、依存ライブラリも両方に対応させます。例えばCのソースをビルドする場合は次の形です。

```sh
clang -dynamiclib -arch arm64 -arch x86_64 example.c -o libexample.dylib
file libexample.dylib
lipo -archs libexample.dylib
nm -gU libexample.dylib
otool -L libexample.dylib
```

`nm`では`_loadu`（または`_load`）、`_request`、`_unload`を確認します。依存ライブラリが開発者のマシンだけにある絶対パスを参照していないかも確認してください。CPUが合うことやシンボルが見えることだけで、実際の読み込み成功までは確認できません。ダウンロード後の配布物でもテストします。

## 要求と応答をまず小さく動かす

通常のイベント要求では、`Charset`、`Sender`、`SecurityLevel`、`ID`、イベントに応じた`ReferenceN`が送られます。次は汎用macOS経路の起動要求の例です。表示上の改行は、実際にはCRLFにします。

```text
GET SHIORI/3.0
Charset: UTF-8
Sender: Utatane
SecurityLevel: local
ID: OnBoot

```

会話を返す最小の応答は次の形です。

```text
SHIORI/3.0 200 OK
Charset: UTF-8
Value: \0Utataneで起動しました。\e

```

両方とも最後のヘッダーの後に空行が必要です。つまり末尾は`\r\n\r\n`です。`Value`へ実際の改行を混ぜず、会話内の改行にはSakuraScriptの`\n`を使います。

会話がないイベントや未使用の通知には、例えば`SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n`を返せます。現在の外部SHIORI経路では2xx以外を要求失敗として扱います。`NOTIFY`も受信して応答できるようにし、`GET`と`OnBoot`だけを受け付ける実装にしないでください。

ヘッダー順やReferenceの個数を固定せず、未知のイベント・ヘッダーを受け取れるようにします。`SecurityLevel`も例の値で固定せず、受信値を処理します。Senderによる分岐は実際に違う動作だけに限定してください。

最初は`OnBoot`、`OnAITalk`、`OnClose`、次にマウス反応と`OnChoiceSelect`を確認します。終了会話の`OnClose`と、モジュールの後片付けの`unload`は役割が違います。状態保存が終了会話にだけ依存しないよう、再読み込みや異常終了も考慮します。

SHIORI/2.xへの再試行は汎用外部SHIORI経路にありますが、新規実装はSHIORI/3.0を基本にしてください。各イベントのReferenceと対応範囲は[SHIORIイベント互換表](../Reference/UKADOC-SHIORI-Event-Compatibility.md)、返すスクリプトは[SakuraScript互換表](../Reference/UKADOC-SakuraScript-Compatibility.md)で確認します。

すべてのSSPイベントやWindows由来の値が同じように提供されるわけではありません。

## SHIOLINKとして実装する

`ghost/master/descript.txt`へ`shiori,shiolink.dll`を指定し、同じ場所に次の設定を置きます。パスは自分の実行環境に合わせて変更します。

```ini
[SHIOLINK]
commandline = "/absolute/path/to/my-shiori" "./dictionary.txt"
charmode = UTF-8
```

Utataneは`SHIOLINK.utatane.ini`を`SHIOLINK.INI`より優先します。実行ファイルは絶対パス、作業ディレクトリは`ghost/master`です。シェルは起動しないため、`~`、環境変数、パイプなどの展開を前提にできません。UTF-8を明記しない場合の既定はShift_JISです。

単に標準入力でSHIORI電文を受け取るだけでは接続できません。現在のUtataneは次の同期手順を使います。

1. 起動後、Utataneから`*L:<masterの絶対パス>/\r\n`を受信します。
2. 要求ごとに`*S:<取引ID>\r\n`を受信し、同じ行を標準出力へ返してflushします。
3. 続いてSHIORI要求を空行まで読み、SHIORI応答をCRLFと終端空行付きで返してflushします。
4. 正常終了時の`*U:\r\n`を受信したら後片付けして終了します。入力のEOFでも終了できるようにします。

標準出力は通信専用です。起動メッセージやログを混ぜると取引IDの不一致や応答解析エラーになります。診断ログは標準エラーまたはファイルへ出します。現在の既定の要求待ちは10秒、フレームの上限は約8 MiBです。重い処理で同期応答を止めないようにしてください。

## SAORI・ファイル・状態保存

独自の外部SHIORIから呼ぶSAORIは、そのSHIORIが読み込みと呼び出しを管理します。Utatane内蔵エンジン用の共通SAORIブリッジへ自動転送されません。Windows SAORIを使う実装は、SHIORI本体だけを移植してもそのまま動くとは限りません。

辞書の読み込み先と可変状態の保存先を分け、読み取り専用のゴースト配置でも動く設計を検討してください。内蔵SHIORIの状態をApplication Supportへ分離する仕組みが、独自SHIORIにも自動適用されるわけではありません。保存先、ゴーストごとの識別、再読み込み時の読み書きは開発者側で設計します。

## 問題の切り分けと配布前の確認

| 症状 | 先に確認すること |
| --- | --- |
| モジュールが読み込まれない | `shiori`の指定、実ファイル、CPU、依存ライブラリ、公開シンボル、読み込みログ |
| 初期化が失敗する | ディレクトリの長さ付き解析、UTF-8、辞書のパス、`loadu/load`の戻り値 |
| 起動するが会話が出ない | 実際のID、応答ステータス、`Value`、CRLFと終端空行、SakuraScript |
| 日本語が壊れる | 電文・辞書それぞれの文字コード、文字数とバイト数の混同 |
| 再読み込みで落ちる・状態が混ざる | 入出力バッファの解放、後片付け、複数ゴーストのグローバル状態 |
| SHIOLINKが待ち続ける | `*S:`の返送とflush、標準出力の余分なログ、空行、プロセスの終了 |

確認用ゴーストは[制作ガイドの手順](Content-Authoring.md#utataneでの確認方法)でインストールし、「現在のゴーストを再読み込み」で繰り返し試せます。Utatane側のログに加え、SHIORI側でも受信ID・要求と応答のバイト数・初期化と終了を記録すると、読み込みと電文処理を分けて調べられます。

- 完成したNARから新規インストールし、日本語や空白を含む配置パスでも起動します。
- 会話、選択肢、通知、未知イベント、再読み込み、アプリ再起動を確認します。
- 複数ゴーストで利用し、状態が混ざらないことを確認します。
- 対象CPUごとに、同梱の依存ライブラリ・SAORIまで含めて確認します。
- 開発環境の絶対パスや追加ランタイムへ依存する場合は、必要な設定をREADMEに書きます。
- SSPも対象にする場合は、同じ配布物のWindows版経路も別途確認します。
- READMEに確認したUtataneのバージョン、対象CPU、確認済み操作、既知の制約を書きます。

## 実装を追う場合

- [汎用モジュールのローダー](../../packages/plugin/Sources/DynamicLibraryPluginTransport.swift)：関数の型、UTF-8、バッファの所有権
- [外部SHIORIのイベント処理](../../apps/Utatane/Sources/ExternalModuleRuntime.swift)：応答ステータス、SHIORI/2.x再試行
- [イベントから電文への変換](../../packages/shiori/Sources/GhostEventShioriAdapter.swift)：IDとReference、GET / NOTIFY
- [SHIOLINK設定](../../packages/shiori/external/posix/Sources/ShiolinkConfiguration.swift)と[セッション](../../packages/shiori/external/posix/Sources/ShiolinkSession.swift)：起動・同期・終了
