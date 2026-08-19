# Utatane

Utataneは、伺か（デスクトップマスコット）をmacOSで動かすための本体アプリです。

現在は開発中です。既存のゴーストとの互換性を少しずつ広げていますが、SSPのすべての機能にはまだ対応していません。

## 主な機能

- ゴースト、シェル、バルーンの読み込みと切り替え
- 複数キャラクター、サーフェス、アニメーションの表示
- SakuraScriptによる会話、選択肢、リンクの再生
- クリック、ダブルクリック、撫でなどのマウス操作
- キャラクターの位置やゴーストごとの設定の保存
- NARからのインストール
- YAYA / SATORIを使うゴーストのネイティブ実行
- SSTP (over HTTP)、RSSへの対応

Windows向けDLLの直接実行や、Windows固有のFMOには対応していません。ゴーストによっては表示や動作に互換性の問題があります。

## 必要な環境

- macOS 14以降
- Xcode 26以降
- [mise](https://mise.jdx.dev/)

## ビルド

```sh
git submodule update --init --recursive
mise install
mise run generate
mise run build
```

生成された`Utatane.xcodeproj`をXcodeで開いて実行することもできます。

テストを実行する場合は次のコマンドを使います。

```sh
mise run test
```

cloneするときに`--recurse-submodules`を指定した場合、最初のsubmodule更新は不要です。

## ゴーストを試す

Debugビルドでは、次の場所にローカルコンテンツを配置できます。

```text
Content/Local/Ghosts/       ゴースト
Content/Local/Balloons/     バルーン
Content/Local/Headline/     HEADLINEモジュール
```

アプリ起動後は、キャラクターの右クリックメニューからNARをインストールすることもできます。

## リポジトリ構成

```text
apps/Utatane/       macOSアプリ
packages/           パーサー、ランタイム、表示、人格エンジン
Content/Local/      開発用のローカルコンテンツ
Design/             デザイン素材
```

Xcodeプロジェクトは`project.yml`からXcodeGenで生成します。`Utatane.xcodeproj`は生成物のため、Gitには含めません。

## ライセンス

Utatane本体は[MIT License](LICENSE)で公開しています。

submoduleとして利用しているYAYAはBSD 3-Clause License、SATORIはBSD 2-Clause Licenseに従います。ゴースト、シェル、バルーンなどの素材には、それぞれの配布元の利用条件が適用されます。
