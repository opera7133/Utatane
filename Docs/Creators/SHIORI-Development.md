# SHIORIの配布と開発

SHIORIの移植、dylibの入口、ビルドと検証、SHIOLINKの接続手順は、[Utatane Modulesの開発ガイド](https://github.com/opera7133/utatane-modules/blob/main/docs/shiori-development.md)にあります。

## WindowsとmacOSを同じゴーストで配布する

`ghost/master/descript.txt`でWindows用DLLとmacOS用dylibを指定します。

```text
shiori,example.dll
shiori.macos,libexample.dylib
```

Utataneは`shiori.macos`を優先します。macOS側に必要な依存ライブラリとライセンスも同梱してください。配布済みSHIORIを使う場合は[各モジュールの導入案内](https://github.com/opera7133/utatane-modules)に従います。

開発版では、既知のSHIORIを自動判別した場合にも、ゴースト内の`shiori.dylib`を探索します。指定したDLLがサブフォルダにある場合は、その横の同名dylibも候補になります。異なるSHIORIを併置する場合や確実に指定したい場合は、`shiori.macos`を使ってください。

ゴーストの構成とNARの作成は[コンテンツ制作ガイド](Content-Authoring.md)、イベントとスクリプトは[SHIORIイベント互換表](../Reference/UKADOC-SHIORI-Event-Compatibility.md)・[SakuraScript互換表](../Reference/UKADOC-SakuraScript-Compatibility.md)を参照してください。
