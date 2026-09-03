# Utatane対応ガイド（ゴースト・SHIORI・SAORI制作者向け）

Utataneで動くコンテンツを新しく作る場合と、SSPなどで動いている既存コンテンツを対応させる場合の入口をまとめます。Utatane専用形式へ作り直す必要はありません。まず一般的な伺かのディレクトリ構成と電文を保ち、macOSで実行できない部分だけを切り分けてください。

Utataneは開発中で、SSPの全機能を再現しているわけではありません。対応の有無は[ゴースト互換状況](Compatibility.md)、[Native SHIORI / SAORI](Native-SHIORI.md)、[UKADOC互換表](UKADOC-Text-File-Compatibility.md)から確認できます。

## 最初に選ぶ経路

| 作るもの | 新規に作る場合 | SSP向けの既存資産がある場合 |
| --- | --- | --- |
| ゴースト | Utatane内蔵のYAYA、里々、華和梨、美坂などを使うと、Windows DLLを同梱したままでも辞書をmacOS上で実行できる | 構成を変えずにNARまたはSSPフォルダから取り込み、内蔵SHIORIで動く範囲を先に確認する |
| SHIORI | 辞書型の既知SHIORIを使うか、標準SHIORI ABIのmacOS用dylib、またはSHIOLINK外部プロセスとして作る | Windows固有コードを分離してmacOS用dylibを追加する。未移植DLLは設定済みWineでの互換確認に限られる |
| SAORI | 既存の内蔵SAORIを使うか、標準SAORI ABIのmacOS用dylibとして作る | SHIORIから送るSAORI/1.0電文を維持し、Windows API部分だけをmacOS向けに移植する |

「Windows版を残しつつUtataneにも対応する」なら、OSごとに配布物を完全分離する前に、同じ辞書・設定を両方で使えるか試すのが近道です。Utataneの内蔵SHIORIは、代表的なWindows DLL名と辞書構成を見てネイティブ実装を選びます。

## ゴーストを新しく作る

最低限、次の形で用意します。実際には使用するSHIORIの辞書やシェル定義も必要です。

```text
example-ghost/
├── descript.txt
├── ghost/
│   └── master/
│       ├── descript.txt
│       ├── 使用するSHIORIの設定・辞書
│       └── SHIORI名.dll（内蔵SHIORIでは識別用。実行はしない場合がある）
└── shell/
    └── master/
        ├── descript.txt
        ├── surfaces.txt
        └── surface0.png
```

`ghost/master/descript.txt`の`shiori`には使用するモジュール名を書きます。古いゴーストとの互換用に`alias.txt`の指定も読みますが、新規作成では`descript.txt`へ明記してください。

最初は次の小さい動作だけを作り、順番に増やすと原因を分けやすくなります。

1. `OnBoot`で短いSakuraScriptを返す
2. `OnClose`、`OnAITalk`を返す
3. `OnMouseDoubleClick`と`OnChoiceSelect`を追加する
4. サーフェス、SERIKO、着せ替えを追加する
5. SAORI、ネットワーク更新、ゴースト間通信など外部要素を追加する

SakuraScriptやイベントごとの差は、[SakuraScript互換表](UKADOC-SakuraScript-Compatibility.md)と[SHIORIイベント互換表](UKADOC-SHIORI-Event-Compatibility.md)で確認してください。

## 既存のSSP向けゴーストを対応させる

最初からUtatane専用の分岐を足さず、元のNARをインストールするか、「SSPフォルダから取り込む」で確認します。次の順で問題を分けます。

1. ゴースト一覧に名前が出るか
2. `OnBoot`の会話とサーフェスが出るか
3. ランダムトーク、クリック、選択肢が動くか
4. 終了と再読み込み後に変数が保たれるか
5. 追加シェル、バルーン、着せ替え、更新が動くか
6. SAORIや外部プログラムを使う機能だけを個別に試す

起動しない場合は、まず`ghost/master/descript.txt`の`shiori`、ファイル名の大文字小文字、辞書の文字コードを確認します。macOSのファイルシステムでは、配布先によって大文字小文字の違いが問題になることがあります。

Windows DLL、EXE、COM、レジストリ、Windowsのウィンドウハンドルに依存する機能は、そのままでは動きません。内蔵互換実装があるSAORIへ置き換える、該当機能を使わない代替分岐を用意する、macOS版モジュールを追加する、の順で検討してください。Wine経路は利用者側の追加設定が必要なので、通常機能の唯一の実装にはしないほうが安全です。

SSPとUtataneで応答を変える必要がある場合でも、まず実際に異なる項目だけに限定してください。OS判定、HWND、プロセス操作などは互換値や未対応値になることがあります。共通のSHIORIイベントとSakuraScriptで済む処理は共通化します。

## SHIORIを対応させる

### 既知の辞書型SHIORI

YAYA / AYA、里々、華和梨、美坂などはUtataneの内蔵実装を優先します。既存ゴーストはWindows用DLLを識別名として残したまま動かせる場合があります。対応する辞書形式、制約、実験的機能は[Native SHIORI / SAORI](Native-SHIORI.md)を参照してください。

新規ゴーストでは、SSPでも同じ辞書を使える既知SHIORIを選ぶと一つの配布物にまとめやすくなります。ただし、内蔵実装が元のSHIORIの全機能を再現しているとは限りません。使う関数や構文は実際に両方で確認してください。

### 独自SHIORI

新しいネイティブモジュールは、標準の`loadu`（または`load`）、`request`、`unload`を公開するmacOS用`.dylib`、`.so`、`.bundle`として配置できます。`ghost/master/descript.txt`の`shiori`には、そのmacOS用ファイル名を指定します。

- `loadu`と電文はUTF-8を推奨
- SHIORI/3.0要求へ、ステータス行、`Charset`、必要なら`Value`を含む応答を返す
- 改行はCRLF、ヘッダー末尾には空行を置く
- arm64とx86_64の両方へ配布するならUniversal Binaryにする
- 設定や可変状態をゴースト本体へ書く前に、読み取り専用配置でも動くか確認する

外部プロセスとして実装したい場合はSHIOLINKも利用できます。実行ファイルの絶対パスが必要になるため、不特定の利用者へそのまま配布する用途より、開発・個別設定向けです。

既存のWindows SHIORIを移植するときは、辞書評価部を共有し、DLLのエントリポイント、文字コード変換、Windows APIの部分をmacOS用の薄い層へ分けます。Windows DLLしか入っていない場合、Utataneは設定済みWineとDLLホストへ渡せますが、補助DLLや独自UIまでの互換性は保証しません。

## SAORIを対応させる

まず[内蔵SAORIの一覧](Native-SHIORI.md#共通saoriブリッジ)に同じ機能がないか確認します。内蔵SHIORIが対応するSAORI構文から呼び出す場合、`mciaudior.dll`などの既知名はUtataneの実装へ接続されます。

独自SAORIは標準SAORI/1.0の電文と、SHIORIと同じ`loadu`（または`load`）、`request`、`unload`を持つmacOS用モジュールとして移植します。既存版と要求・応答の意味を揃え、ファイル、音声、クリップボードなどOS依存部分だけを差し替えると、呼び出す辞書を共通化できます。

注意点は次の通りです。

- モジュールと相対パスは`ghost/master`内へ置く
- macOS版はUTF-8の`loadu`を優先する
- `Result`、`Value`、`ArgumentN`など、元のSAORIが返すヘッダーをテストする
- 外部EXE、COM、独自ウィンドウ、Windows HWNDを前提にしない
- 失敗や未対応操作は、空の成功応答ではなく呼び出し側が判別できる応答にする

Windows版とmacOS版でファイル名を変える場合は、利用するSHIORI側でOSに応じてロード先を選ぶ必要があります。Utataneが任意のWindows SAORI名からmacOS版を自動推測するわけではありません。

## Utataneでの確認方法

配布前の確認には、NARを使う方法と展開済みフォルダを使う方法があります。

- 利用者と同じ条件: NARをUtataneへドラッグ＆ドロップして新規インストールする
- 既存環境から確認: Utataneの「SSPフォルダから取り込む」を使う
- 繰り返し編集: UtataneのコンテンツフォルダをFinderで開き、対象を編集して「現在のゴーストを再読み込み」する
- Utatane本体のDebugビルドで確認: `Content/Local/Ghosts/`へ置く（配布条件のある実物はコミットしない）

NARには一般的な`install.txt`を入れ、少なくとも`charset`、`type`、`name`、`directory`を設定します。Utatane専用のインストール定義は必要ありません。`refresh`、同梱シェル・バルーンなど対応済み項目と制約は[テキストファイル互換表](UKADOC-Text-File-Compatibility.md#installtxt)で確認してください。

問題が起きたらデバッグ画面のログをコピーし、次を一緒に残してください。

- UtataneのバージョンとmacOS、CPU（Apple Silicon / Intel）
- ゴースト、SHIORI、SAORIの名前とバージョン
- 新規インストールか、既存環境からの取り込みか
- 再現に必要な操作と、期待した結果、実際の結果
- SHIORI要求・応答、モジュールの読み込み失敗、文字コード変換失敗が分かるログ

状態ファイルが影響する問題は、新規インストール時と継続利用時を分けて確認します。Utataneの内蔵実装は、元のゴーストを不用意に変更しないため、可変状態をApplication Support側へ分離して保存するものがあります。

## 配布前チェックリスト

- SSPとUtataneの両方を配布対象にする場合、完成したNARからそれぞれ新規インストールできる
- `OnBoot`、`OnClose`、ランダムトーク、マウス反応、選択肢を確認した
- 再読み込みとアプリ再起動後の状態を確認した
- ファイル名の大文字小文字と文字コードを確認した
- Windows専用機能に代替動作または分かる説明がある
- arm64 / x86_64を配布対象にする場合、macOSモジュールの両アーキテクチャを確認した
- 更新URLを使う場合、新規インストールだけでなく更新も確認した
- READMEにUtataneで確認したバージョン、対応範囲、既知の制約を書いた

完全互換を確認できていない場合は、「Utatane対応」とだけ書くより、確認済みの操作と動かない機能を具体的に記載してください。問題報告や対応追加の相談では、再配布できないゴースト本体をリポジトリへ追加せず、最小の再現データとログを添えると調査しやすくなります。
