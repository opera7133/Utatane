# ネイティブプラグイン

Utataneは`Plugins/<plugin>/descript.txt`を読み、`filename`の実体と同じフォルダにあるSHIORI設定から実行方式を選びます。YAYA、AKARI、里々、華和梨、MISAKA、KAGARIで作られたプラグインは、対応する同梱または導入済みのdylibを使用します。Windows用DLLをmacOSへ直接ロードすることはありません。

Windows版とmacOS版を同梱する場合は、SSP向けの`filename`を残して、Utatane向けの`filename.macos`を追加できます。

```text
filename,plugin.dll
filename.macos,libplugin.dylib
```

空でない`filename.macos`は、辞書からのSHIORI自動判定より優先されます。指定したファイルがない、または読み込めない場合も`filename`へ黙って戻らないため、配布前にmacOS版の同梱を確認してください。`filename.macos`はUtatane独自の項目です。

## macOS dylib ABI

選択された`filename`または`filename.macos`が`.dylib`、`.so`、`.bundle`の場合は、まず一般的な伺かモジュールと同じexport名を探します。既存のオープンソースプラグインは、Windows固有処理とメモリ受け渡し部分だけを移植し、プラグイン本体のイベント処理を保ったままmacOS用`cdylib`としてビルドできます。

```c
#include <stdint.h>

int32_t loadu(void *plugin_directory, int32_t directory_length); /* または load */
int32_t unload(void);
void *request(void *request_message, int32_t *message_length);
```

`loadu`ではUTF-8、`load`ではプラグインの`charset`を前提にします。現状のUtataneはmacOSモジュールとのやり取りをUTF-8で行うため、`loadu`を推奨します。入力バッファの所有権は呼び出し時にモジュールへ移り、`request`が返すバッファはUtataneがコピー後にmacOSの`free`で解放します。長さにNULは含めません。

KAGARIの`kagari.dll`・`libkagari.dylib`・`libkagari.so`は、上記とは異なるインスタンス単位のABIを使うため、専用の接続で読み込みます。`filename.macos,libkagari.dylib`の指定時も同じです。保存先はKAGARIの辞書が指定する場所で、本体の`State/Plugins`へ自動移動するものではありません。

## PLUGIN電文と配送

要求は`PLUGIN/2.0`です。`Language`は`Japanese`などの英語表記の言語名を送ります。ホストからの通知では`Sender`を省略し、ゴーストからの呼び出しではそのゴーストの名前を送ります。`version`の成功応答に有効な`Charset`があれば、次の要求ヘッダへ反映します。macOSのネイティブABIで受け渡すバイト列はUTF-8です。

応答の`Target`は起動中のゴースト名・キャラクター名などに照合し、`__SYSTEM_ALL_GHOST__`なら全ゴーストへ配送します。省略時または一致しない場合は、呼び出し元、なければメインなどの起動中ゴーストを一つ選びます。`Event`に対してゴーストが返したスクリプトを優先し、無応答ならプラグインの`Script`を使います。`EventOption: notify`ではゴーストへNOTIFYし、その返答は再生しません。`ScriptOption`はプラグインの`Script`だけに適用します。

`descript.txt`の`otherghosttalk,true|before|after`で会話通知を購読できます。`true`は再生後です。同じプラグイン自身が返したスクリプトは、そのプラグインへ再通知しません。`othersurfacechange,true`ではサーフェス変更を通知します。

プラグイン由来の`inputbox`・`passwordinput`・`textareabox`は、入力・キャンセル・時間切れを発信元プラグインへ返します。呼び出しゴーストの画面でも、その画面の入力コントローラーを使います。割り込み時のすべてのイベントをプラグインへ中継する機能は未対応です。

## Windows DLL

対応するdylibを見つけられず、選択された`filename`または`filename.macos`が`.dll`の場合だけ、汎用Windows DLLホストへ接続します。実行に必要なのはWine、`utatane-dll-host.exe`、対象プラグインDLLです。場所は`UTATANE_WINE_EXECUTABLE`、`UTATANE_WINE_PREFIX`、`UTATANE_WINDOWS_DLL_HOST`で指定できます。Debugビルドではホストの既定位置として`Content/Local/WindowsDLLBridge/utatane-dll-host.exe`も参照します。

この経路はWindowsプラグイン一般の互換性を保証しません。外部EXE、COM、独自UIなどへ依存するプラグインは動作しない場合があります。また、Wineの初回設定が完了するまで起動に時間がかかることがあります。

## BalloonSelector

BalloonSelectorのmacOS移植版は、Utatane Modulesの[導入手順](https://github.com/opera7133/utatane-modules/blob/main/docs/balloonselector.md)に沿ってNARを生成します。この対応にはUtatane 0.2.16以降とmacOS版YAYAが必要です。Modulesからのプラグイン自動導入にはまだ対応していません。

macOS版YAYAをModulesから導入し、生成したNARをUtataneへインストールします。右クリックメニューのプラグインからBalloonSelectorを実行すると、バルーンのプレビュー付き一覧を開きます。原版の3×3配置の代わりに、1ページ9件の一列リストで表示します。プラグインIDと、選択・キャンセル時にゴーストへ送るイベントは原版と同じです。

プラグインの初期化時とメニューを開く前に、Utataneは`installedballoonname`・`balloonpathlist`・`pluginpathlist`をNOTIFYします。プラグイン由来のスクリプトでは、`get,property`の結果をそのプラグインへ返します。`currentghost.balloon.scope(N).validwidth`／`validheight`は、現在のバルーン書式の文字領域を返します。

選択肢・アンカーには発信元プラグインを保持します。最初の選択時はゴーストとプラグインへ同じイベントを送り、プラグインの応答を優先して再生します。通常のゴーストが作った選択肢は従来どおりです。`ScriptOption: notranslate`はデフォルトスクリプトの翻訳を省き、`nobreak`は再生待ち行列へ入れます。

画像の絶対パスはゴーストの素材フォルダと、アプリが指定したバルーン格納先だけを読み込みます。シンボリックリンクで格納先の外へ出る画像は読み込みません。

移植NARの辞書を一時フォルダへコピーし、実YAYA・PLUGIN電文・本体の再生処理を通す検証は次で実行できます。テスト用バルーンは合成した画像を使います。

```sh
sh Scripts/build-native-shiori-host.sh .generated-hosts/utatane-shiori-host
UTATANE_BALLOONSELECTOR_PLUGIN=/path/to/extracted-port \
UTATANE_YAYA_MODULE=/path/to/libyaya.dylib \
UTATANE_NATIVE_SHIORI_HOST="$PWD/.generated-hosts/utatane-shiori-host" \
swift test --package-path packages --filter BalloonSelectorIntegrationTests
```

この検証は実辞書のページ送り・全件列挙・画像表示・選択とキャンセルの通知を対象にします。利用中のゴーストでの実際のマウス操作は別途確認が必要です。

## 実プラグインの回帰確認

`Scripts/test-real-plugins.py`は、上記のBalloonSelector移植版とDBdiary 1.0.1を一時コピーで動かし、元データを変更せずに削除まで確認します。プラグインそのものをテストfixtureへ同梱しません。BalloonSelectorは上記のコミットをcheckoutし、DBdiaryは[原版の1.0.1 NAR](https://github.com/ambergon/UkagakaPlugin_DBdiary/releases/tag/1.0.1)を取得します。NARのSHA-256は`afd10bc9eda37b408b21b5facbc3e74f269824e72ce91d89728e502b87f51489`で固定しています。

```sh
python3 Scripts/test-real-plugins.py \
  --modules /path/to/utatane-modules \
  --balloonselector-source /path/to/balloonselector-port-source \
  --dbdiary-nar /path/to/UkagakaPlugin_DBdiary.nar \
  --yaya-module /path/to/libyaya-6.dylib \
  --host "$PWD/.generated-hosts/utatane-shiori-host" \
  --report /tmp/utatane-plugin-report.json
```

DBdiaryでは元の辞書を変更せず、入力命令から日本語の日記の保存、取得、再読み込み後の取得を確認します。入力画面への入力はテストで代行するため、手動の画面操作を確認した意味ではありません。`--kagari-module /path/to/libkagari.dylib`を追加すると、合成Lua辞書でPLUGIN電文・複数インスタンスの分離・終了時保存・再読み込みも確認します。JSONレポートには取得元、入力ファイルのハッシュ、実行したスイート、一時コピーの削除結果を残し、同名の`.log`に出力を保存します。

## SAORI BASICの音声タグ取得

Modulesの[proxy_ex移植版](https://github.com/opera7133/utatane-modules/blob/main/docs/proxy-ex.md)は、
共通SAORI格納先へ導入して使います。ゴーストごとの辞書変更は不要です。
`proxy_ex.dll`経由の`mp3tag.exe`要求を同梱のmacOS用ヘルパーで処理し、タイトルや長さを読み取ります。
音声を再生して長さを調べることはありません。華和梨では9.1.0-r3以降を使用してください。
対応形式はAudioToolbox/AVFoundationに依存します。日本語タグを取得できても、ゴースト自身の画像フォントに字形がない場合は表示できません。

音声の`--spectrum`指定は本体が処理し、`OnSoundSpectrum`を指定間隔で送ります。
帯域数は0・5・10・15・31、ピーク保持は`--spectrum-hold`で指定します。
左右などチャンネル別のレベルと、帯域別のレベル、再生位置を取得できます。
一時停止中は通知を止め、停止時はゼロのレベルを返します。音量設定を掛ける前の波形を解析します。
MIDI・CD・動画の解析と、SSPとの数値の完全一致は未対応です。
