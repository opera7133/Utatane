# Utatane

Utataneは、伺かをmacOSで動かすための本体アプリです。

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

## インストール

1. [Releases](../../releases)から最新のpre-releaseにある`Utatane-macOS.zip`をダウンロードする
2. ZIPを展開し、`Utatane.app`を「アプリケーション」フォルダへ移動する
3. Utataneを起動する

現在のpre-releaseは未署名です。macOSに起動を止められた場合は、Utataneを一度起動したあと「システム設定」→「プライバシーとセキュリティ」から実行を許可してください。将来の配布ではDeveloper IDによる署名とnotarizationを予定しています。

## 最初のゴーストを追加する

Utataneにはゴーストやバルーンを同梱していません。初回起動時に表示される案内から、次のいずれかを選べます。

- 配布されているゴーストのNARをインストールする
- 展開済みのSSPフォルダから`ghost`と`balloon`を取り込む
- UtataneのコンテンツフォルダをFinderで表示する

SSPから取り込む場合は、SSP本体のZIPを別途ダウンロードして展開し、そのフォルダを「SSPフォルダから取り込む」で選択してください。同名のコンテンツは上書きしません。

インストールしたコンテンツは次の場所に保存されます。

```text
~/Library/Application Support/Utatane/Ghosts
~/Library/Application Support/Utatane/Balloons
~/Library/Application Support/Utatane/Headline
```

## ソースからビルド

必要な環境:

- macOS 14以降
- Xcode 26以降
- [mise](https://mise.jdx.dev/)

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

## 開発用コンテンツ

Debugビルドでは、次の場所にローカルコンテンツを配置できます。

```text
Content/Local/Ghosts/       ゴースト
Content/Local/Balloons/     バルーン
Content/Local/Headline/     HEADLINEモジュール
```

アプリ起動後は、初回案内またはキャラクターの右クリックメニューからNARをインストールすることもできます。

## リポジトリ構成

```text
apps/Utatane/       macOSアプリ
packages/           パーサー、ランタイム、表示、人格エンジン
Content/Local/      開発用のローカルコンテンツ
Design/             デザイン素材
```

## ライセンス

Utatane本体は[MIT License](LICENSE)で公開しています。

submoduleとして利用しているYAYAはBSD 3-Clause License、SATORIはBSD 2-Clause Licenseに従います。ゴースト、シェル、バルーンなどの素材には、それぞれの配布元の利用条件が適用されます。
