# Utatane

Utataneは、伺かをmacOSで動かすための本体アプリです。

![Utatane スクリーンショット](Design/SampleScreenShot.png)

まだ開発中です。既存ゴーストとの互換性を地道に増やしています。SSP全部入りではありません。

## だいたいできること

### ゴーストの表示と会話

- ゴースト、シェル、バルーンの読み込みと切り替え
- 複数キャラクター、サーフェス、SERIKOアニメーションの表示
- SakuraScriptによる会話、選択肢、リンクの再生
- クリック、ダブルクリック、撫で、ホイールなどのマウス操作
- 複数ゴーストの呼び出しとコミュニケーション
- キャラクターとバルーンの位置、選択中のシェルとバルーンをゴーストごとに保存

### インストールと設定

- NARのファイル選択、ドラッグ＆ドロップ、Finderからの「このアプリケーションで開く」によるインストール
- 展開済みSSPフォルダからのゴーストとバルーンの取り込み
- シェルとバルーンの個別倍率、連動倍率、バルーン文字倍率
- シェルの画面下固定と画面端補正をゴーストごとに切り替え
- 前回のゴースト、起動時選択、ランダムの3種類の起動方法
- システム設定に従う／ライト／ダークの外観切り替え
- ゴースト起動やシェル切り替えに時間がかかる場合の進行表示

### 人格とかネットワークとか

- YAYA / SATORIを使うゴーストのネイティブ実行
- KAWARIを使うゴーストのネイティブ実行
- SSU、`saori_cpuid`、`kenonoke`、`textcopy2`のネイティブSAORI互換
- ゴーストとバルーンの手動ネットワーク更新と、設定した日数ごとの自動更新
- SSTP over HTTP、RSS / Atom、HEADLINE/2.0
- `config.txt`形式のHEADLINEセンサーをネイティブ実行し、独自Windows DLLはWineへフォールバック
- MateriaのFIRSTを設定したWine経由で実行（開発用）

## まだ無理なこと

今のところは以下の通り。

- 一般のWindows向けSHIORI / SAORI / プラグインDLLやexeは直接実行できません
- Windows固有のFMOには対応していません
- SakuraScript、SERIKO、着せ替えなどは未対応の命令や定義があります
- ネットワーク更新はゴーストと単体バルーンが対象です。SSPの修復モードや、別配布のシェル・バルーンをまとめて更新する機能には未対応です
- ゴーストによっては表示、文字コード、イベントの互換性に問題があります

<details>
<summary>実験的な機能</summary>

- 利用者がビルドしたAosoraのmacOS用モジュールを外部から読み込めます
- MateriaのFIRSTは専用ホストとWineを設定した場合のみ起動できます
- 独自Windows HEADLINE DLLはWineへフォールバックできます

詳しくは[Native SHIORI / SAORI](Docs/Native-SHIORI.md)を参照してください。

</details>

## とりあえず使う

1. [Releases](../../releases)から最新のpre-releaseにある`Utatane-macOS.zip`をダウンロードする
2. ZIPを展開し、`Utatane.app`を「アプリケーション」フォルダへ移動する
3. Utataneを起動する

初回起動時から、同梱ゴースト「りあ」と専用バルーン「Ria」を利用できます。りあは時間帯や曜日に応じた会話、マウス操作、着せ替え、短い外出、現在地の天気確認などに対応しています。

現在のpre-releaseは未署名です。macOSに止められたら、一度起動を試してから「システム設定」→「プライバシーとセキュリティ」で許可してください。アプリケーションのディレクトリで`sudo xattr -rc Utatane.app`でも構いません。

## ほかのゴーストを追加する

同梱のりあ以外にも、次の方法でゴーストやバルーンを追加できます。

- 配布されているゴーストのNARをインストールする
- 展開済みのSSPフォルダから`ghost`と`balloon`を取り込む
- UtataneのコンテンツフォルダをFinderで表示する

SSPから持ってくる場合は、SSP本体のZIPを展開して、そのフォルダを「SSPフォルダから取り込む」で選びます。同名のものは上書きしません。

インストールしたコンテンツは次の場所に保存されます。

```text
~/Library/Application Support/Utatane/Ghosts
~/Library/Application Support/Utatane/Balloons
~/Library/Application Support/Utatane/Headline
```

<details>
<summary>元祖さくらとうにゅうをどうしても動かす</summary>

これは一般のWindowsゴースト互換機能ではなく、Materia付属のFIRST専用です。32-bit Windowsアプリを実行できるWineと、正規に入手したMateria一式が要ります。

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

配布版にはWindows SHIORIホストが入っています。初回利用時に`Compatibility/Materia/Host/`へ勝手に出てくるので、手動配置は不要です。Wine実行ファイルには、Windows exeのパスを引数に取れるものを指定してください。WINEPREFIXはFIRST専用がおすすめです。

ソースからのDebugビルドでは、ローカル検証データを次のように配置します。

```text
Content/Local/
├── materia.exe
├── Ghosts/first/
└── MateriaBridge/materia.exe
```

最後の`MateriaBridge/materia.exe`は、`tools/materia-shiori-host/README.md`の手順でビルドします。

</details>

## もう少し詳しい話

- [開発・ビルド](Docs/Development.md)
- [ゴースト互換状況](Docs/Compatibility.md)
- [Native SHIORI / SAORI](Docs/Native-SHIORI.md)

## ライセンス

Utatane本体は[MIT License](LICENSE)で公開しています。

submoduleのYAYAはBSD 3-Clause License、SATORIはBSD 2-Clause License、KAWARIは修正BSD Licenseです。ゴースト、シェル、バルーンは各配布元のルールに従ってください。

同梱ゴースト「りあ」のシェルには、ボトル猫さんの「p016（寝不足）」を使用しています。専用バルーン「Ria」は、ろすえんさんの「[something like Template](https://github.com/lost-nd-xxx/something_like_balloon)」を元に制作しています。詳しい規約とクレジットは、それぞれの同梱READMEを参照してください。
