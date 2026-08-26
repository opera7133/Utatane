# ネイティブプラグイン

Utataneは`Plugins/<plugin>/descript.txt`を読み、`filename`の実体と同じフォルダにあるSHIORI設定から実行方式を選びます。YAYA、AKARI、里々、華和梨、MISAKAで作られたプラグインは、対応する内蔵SHIORIを優先します。Windows用DLLをmacOSへ直接ロードすることはありません。

## macOS dylib ABI

`filename`が`.dylib`、`.so`、`.bundle`の場合は、まず一般的な伺かモジュールと同じexport名を探します。既存のオープンソースプラグインは、Windows固有処理とメモリ受け渡し部分だけを移植し、プラグイン本体のイベント処理を保ったままmacOS用`cdylib`としてビルドできます。

```c
#include <stdint.h>

int32_t loadu(void *plugin_directory, int32_t directory_length); /* または load */
int32_t unload(void);
void *request(void *request_message, int32_t *message_length);
```

`loadu`ではUTF-8、`load`ではプラグインの`charset`を前提にします。現状のUtataneはmacOSモジュールとのやり取りをUTF-8で行うため、`loadu`を推奨します。入力バッファの所有権は呼び出し時にモジュールへ移り、`request`が返すバッファはUtataneがコピー後にmacOSの`free`で解放します。長さにNULは含めません。

## Windows DLL

内蔵SHIORIとして認識できず、`filename`が`.dll`の場合だけ、汎用Windows DLLホストへ接続します。実行に必要なのはWine、`utatane-dll-host.exe`、対象プラグインDLLです。場所は`UTATANE_WINE_EXECUTABLE`、`UTATANE_WINE_PREFIX`、`UTATANE_WINDOWS_DLL_HOST`で指定できます。Debugビルドではホストの既定位置として`Content/Local/WindowsDLLBridge/utatane-dll-host.exe`も参照します。

この経路はWindowsプラグイン一般の互換性を保証しません。外部EXE、COM、独自UIなどへ依存するプラグインは動作しない場合があります。また、Wineの初回設定が完了するまで起動に時間がかかることがあります。
