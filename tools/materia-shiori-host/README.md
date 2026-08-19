# Materia SHIORI probe

`first.dll`を32-bit Windows環境でロードする検証ツール兼、Utatane接続用の常駐ホスト。

## Build

```sh
zig cc -target x86-windows-gnu -Os \
  tools/materia-shiori-host/main.c \
  -o Content/Local/MateriaBridge/materia.exe
```

実行ファイル名は必ず`materia.exe`にする。元の`materia.exe`と衝突させないため、次の配置を前提にする。

```text
Content/Local/
├── materia.exe                  original Materia
├── Ghosts/first/ghost/master/
│   ├── first.dll
│   └── misaki.dll
└── MateriaBridge/
    └── materia.exe              this probe
```

引数なしで起動すると、元のMateriaと`first.dll`を上の相対位置から探す。起動時に元のMateriaのDLLリソース102と104を`mai.dll`、`sayuri.dll`として同じディレクトリへ抽出する。

結果は`MateriaBridge/probe.log`へUTF-8で書き出す。

`serve [original-materia.exe shiori.dll]`を指定すると、標準入出力の常駐IPCモードになる。起動完了時に長さ0のフレームを返し、以後は「4バイトlittle-endian長 + SHIORIデータ」のフレームを送受信する。診断ログは`MateriaBridge/host.log`へ出力し、標準出力にはフレーム以外を書かない。

ReleaseビルドではGitHub ActionsがこのホストをPE32としてビルドし、アプリのResourcesへ同梱する。実行時は書込み可能な`~/Library/Application Support/Utatane/Compatibility/Materia/Host/`へコピーし、そこで補助DLLとログを管理する。元のMateria本体は同梱せず、ユーザーが`Compatibility/Materia/materia.exe`へ配置する。

## Current scope

- 引数なしの検証モードでは、固定のSHIORI/3.0 `OnBoot`要求を送る。
- 常駐モードでは、Wineプロセスが終了するまで複数のSHIORI要求を処理する。
- 元のMateriaとゴーストはローカル検証データとして扱い、リポジトリへ追加しない。
