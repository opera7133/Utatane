# Windows DLL host

伺か系のWindows DLLをWine内でロードし、DLL共通仕様の`load`、`request`、`unload`を標準入出力越しに呼ぶ汎用ホスト。Wineは最後の手段。FIRST固有の面倒はMateriaホストへ隔離している。

```sh
Scripts/build-windows-dll-host.sh \
  Content/Local/WindowsDLLBridge/utatane-dll-host.exe
```

ホストはCランタイムをリンクせず、Windows APIだけを利用する。PEのtimestampには`SOURCE_DATE_EPOCH`を使い、未指定時は現在のGitコミット時刻を採用するため、同じコミットとZig版から同じバイナリを再生成できる。

引数に対象DLLのWindowsパスを1つ指定する。

```text
utatane-dll-host.exe Z:\\path\\to\\plugin.dll
```

起動完了時に長さ0のフレームを返し、以後は「4バイトlittle-endian長 + DLL要求データ」のフレームを送受信する。
