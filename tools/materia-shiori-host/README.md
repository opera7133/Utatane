# Materia SHIORI probe

`first.dll`を32-bit Windows環境でロードする検証ツール兼、Utatane接続用の開発用常駐ホスト。かなり専用品。

解析済みのオリジナル版FIRSTは`packages/first-native`でWineなしに動くため、このホストは通常利用には不要。現在は本物のSHIORI応答を隔離環境で観測する場合だけに残しており、リリース版には同梱しない。

## Build

```sh
zig cc -target x86-windows-gnu -Os \
  tools/materia-shiori-host/main.c \
  -o Content/Local/MateriaBridge/materia.exe
```

実行ファイル名は必ず`materia.exe`にする。`first.dll`がそういうものだと思っているので仕方ない。元の`materia.exe`とは衝突させず、次の配置にする。

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

ローカルで常駐モードを試す場合は`UTATANE_MATERIA_HOST`、`UTATANE_MATERIA_EXE`、`UTATANE_WINE_EXECUTABLE`、`UTATANE_WINE_PREFIX`を明示する。元のMateria本体、FIRST、生成したホストはすべてローカル検証データとして扱い、配布物へ入れない。

## Current scope

- 引数なしの検証モードでは、固定のSHIORI/3.0 `OnBoot`要求を送る。
- 常駐モードでは、Wineプロセスが終了するまで複数のSHIORI要求を処理する。
- 元のMateriaとゴーストはローカル検証データとして扱い、リポジトリへ追加しない。
