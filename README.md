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
- MateriaのFIRSTを設定したWine経由で実行（開発用）
- `config.txt`形式のHEADLINEセンサーをネイティブ実行し、独自Windows DLLはWineへフォールバック
- SSTP (over HTTP)、RSSへの対応

一般のWindows向けDLLの直接実行や、Windows固有のFMOには対応していません（一部例外）。プラグインもDLLやexeを扱うものについては対応していません。ゴーストによっては表示や動作に互換性の問題があります。

## インストール

1. [Releases](../../releases)から最新のpre-releaseにある`Utatane-macOS.zip`をダウンロードする
2. ZIPを展開し、`Utatane.app`を「アプリケーション」フォルダへ移動する
3. Utataneを起動する

現在のpre-releaseは未署名です。macOSに起動を止められた場合は、Utataneを一度起動したあと「システム設定」→「プライバシーとセキュリティ」から実行を許可してください。（または、アプリケーションのディレクトリで`sudo xattr -rc Utatane.app`を実行）

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

<details>
<summary>元祖さくらとうにゅを追加する</summary>

これは一般のWindowsゴースト互換機能ではなく、Materiaに付属するFIRST専用の実験的な機能です（~~動くとは言っていない~~）。32-bit Windowsアプリを実行できるWine環境と、正規に入手したMateria一式が必要です。

1. Utataneを一度起動し、右クリックメニューからコンテンツフォルダをFinderで開く
2. 元の`materia.exe`を次の場所へコピーする

   ```text
   ~/Library/Application Support/Utatane/Compatibility/Materia/materia.exe
   ```

3. Materiaに付属するFIRSTを、次の構成になるようコピーする

   ```text
   ~/Library/Application Support/Utatane/Ghosts/first/
   ├── ghost/master/first.dll
   └── shell/master/
   ```

4. 必要なバルーンも`~/Library/Application Support/Utatane/Balloons/`へコピーする
5. Utataneの「設定 → 詳細 → Windows SHIORI」で、Wine実行ファイルと専用のWINEPREFIXを指定する
6. ゴースト一覧からFIRSTを選択する

配布版にはUtatane側のWindows SHIORIホストが同梱され、初回利用時に`Compatibility/Materia/Host/`へ自動配置されるため、ホストを手動で置く必要はありません。Wine実行ファイルはWindows exeのパスを引数として受け取れるものを指定してください。他のWindowsアプリと状態や終了処理が干渉しないよう、WINEPREFIXはFIRST専用にすることを推奨します。

ソースからのDebugビルドでは、ローカル検証データを次のように配置します。

```text
Content/Local/
├── materia.exe
├── Ghosts/first/
└── MateriaBridge/materia.exe
```

最後の`MateriaBridge/materia.exe`は、`tools/materia-shiori-host/README.md`の手順でビルドします。

</details>

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

## MCPサーバー

配布版のUtataneには、起動中のゴーストをAIクライアントから操作するstdio形式のMCPサーバーが同梱されています。Utataneを「アプリケーション」フォルダへ置いた場合は、MCPクライアントへ次のように登録します。

```json
{
  "mcpServers": {
    "utatane": {
      "command": "/Applications/Utatane.app/Contents/Helpers/utatane-mcp"
    }
  }
}
```

Utataneを先に起動しておく必要があります。`get_active_ghost_list`、`get_expression_table`、`SakuraScript`の3ツールが利用できます。接続はlocalhostのSSTP over HTTPだけを使用します。

ソースからMCPサーバーだけをビルドする場合は、次を実行し、生成された実行ファイルの絶対パスを`command`へ指定します。

```sh
swift build --package-path packages -c release --product utatane-mcp
```

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
