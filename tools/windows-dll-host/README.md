# Windows DLL host

伺か系のWindows DLLをWine内でロードし、DLL共通仕様の`load`、`request`、`unload`を標準入出力越しに呼ぶ汎用ホスト。Wineは最後の手段。FIRST固有の面倒はMateriaホストへ隔離している。

```sh
zig cc -target x86-windows-gnu -Os \
  tools/windows-dll-host/main.c \
  -o Content/Local/WindowsDLLBridge/utatane-dll-host.exe
```

引数に対象DLLのWindowsパスを1つ指定する。起動完了時に長さ0のフレームを返し、以後は「4バイトlittle-endian長 + DLL要求データ」のフレームを送受信する。
