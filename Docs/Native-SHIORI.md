# Native SHIORI / SAORI

なるべくWineを使わずにゴーストを動かすための話です。KAWARIはアプリへ静的リンク、Aosoraは外部のmacOS用dynamic libraryを読み込みます。

## 共通ネイティブSAORI

`UtataneNativeSaori`はSHIORIから独立したSAORIレジストリです。ネイティブMISAKA、YAYA、SATORI、KAWARIは、それぞれの既存SAORI呼び出し構文を変えずに同じレジストリへ要求を渡します。

- `mciaudior.dll`: `load`、`play`、`loop`、`stop`
- `wmove.dll`: `MOVETO`、`MOVETO_INSIDE`、`GET_POSITION`、`GET_DESKTOP_SIZE`
- `textcopy2.dll`: macOSのクリップボードへの書き込み

`wmove.dll`のWindows HWNDは使用せず、さくら側をスコープ0、相方側をスコープ1としてUtataneのサーフェスウィンドウへ接続します。未実装なのは`MOVE`、`ZMOVE`、`WAIT`、`NOTIFY`、`CLEAR`、`STANDBY`などです。

SSUはSATORIに同梱された既存実装を使います。`saori_cpuid.dll`と`kenonoke.dll`も、実ゴーストで検証済みの多値返却とShift_JIS辞書処理を保つため、現時点ではSATORI側に残しています。

外部macOS SHIORIやWindows DLLホストへ任意のSAORIを注入する機構ではありません。ここでいう共通対応は、Utatane内蔵のネイティブSHIORI経路が対象です。

## MISAKA

MISAKAは`misaka.dll`をロードせず、Shift_JIS辞書をSwift実装で解釈します。配列、採用条件、`#_Common`、`nonoverlap`、`sequential`、整数演算、変数の自動保存、`$_talkinterval`による自発会話、プロパティハンドラ、主要システム変数を実装しています。

`misaka.ini`の`debug`、`debugsaori`、`error`も扱います。ログはゴーストの配布物を変更しないよう、変数JSONと同じUtataneのApplication Support内へ出力します。`daysfromlastupdate`はUtataneの更新履歴をSHIORIへ直接渡していないため、現在はmasterディレクトリの更新日時による近似値です。Windows HWNDは存在しないため、`hwnd.*`は互換用のダミー値です。

未対応なのは`misakac.exe`が生成する暗号化辞書`.__1`です。

## Materia first (さくら)

「さくらとうにゅう」のオリジナル版firstには専用のネイティブ人格実装があります。`first.dll`をmacOSでロードしたり実行したりせず、利用者が配置したDLLから次のデータだけを読み取ります。

- Delphi形式で埋め込まれたCP932文字列
- PEリソース`AITXT/101`に入っている会話用レコード
- `ghost/master/var/first.txt`の`mastertalkinterval`と`energy`初期値

Utatane自身は`first.dll`、会話本文、Materiaの実行ファイルを同梱・再配布しません。会話は起動時に利用者のDLLから取り出し、解析済みの制御フローに沿って組み立てます。

現在は以下を実装しています。

- 時刻別の起動会話、通常のランダムトーク、終了会話
- さくら・うにゅうのダブルクリック、さくらの胸クリック
- 選択肢のキャンセルとタイムアウト、マウス操作説明、ゲーム、眠気レベル
- ゴースト、シェル、バルーンの変更とfirst側の反応
- 眠気、睡眠、起床、夜間の入浴と状態別サーフェス・メニュー
- `mastertalkinterval`に基づく自発会話
- energyと最終入浴日をUtataneのApplication Supportへ分離保存

ゴースト・シェル・バルーンの選択はMateria固有のウィンドウを再現せず、Utataneの独立したmacOS選択ウィンドウへ接続しています。ネットワーク更新もUtataneの更新機能を利用します。

解析済みの版かどうかはPEヘッダーのtimestamp、image size、file sizeで厳密に判定します。一致しないDLLには既知アドレスを適用しません。配布版はMateria用Wine互換ホストを含まないため、ネイティブ非対応版のFIRSTは起動できません。

未対応または対象外なのは、Materia本体に依存するニュース・おすすめ・ポータル・メール・利用率グラフ、Windowsの最小化・終了・再起動などです。一般のWindows SHIORIをこの仕組みで動かせるわけではありません。

Wine経路と`tools/materia-shiori-host`は、実物の挙動を観測して解析を続けるための開発用ツールとしてソースだけを残しています。ローカルで明示的にビルドし、環境変数で指定することはできますが、製品機能としての互換性は保証しません。

## KAWARI

KAWARIはsubmoduleです。`packages/kawari-native/Sources/CKawariNative/Vendor/KAWARI`にいます。

```sh
git submodule update --init --recursive
mise run test --filter NativeKawariSessionTests
```

64-bit macOS向け修正はforkの`utatane-macos`ブランチにあります。

## Aosora（実験的）

Aosoraのソースはライセンスが未設定で、上流READMEでは個人利用またはプロジェクト参加目的に用途が限定されています。なのでUtataneにはソースもsubmoduleもビルド済みモジュールも入れません。[上流リポジトリ](https://github.com/opera7133/aosora-shiori)を確認してください。

<details>
<summary>macOSでのローカルビルド手順</summary>

依存パッケージを入れて、上流をcloneして、付属スクリプトへ渡します。

```sh
brew install pkg-config openssl@3 jsoncpp
git clone --branch utatane-macos https://github.com/opera7133/aosora-shiori.git ~/src/aosora-shiori
tools/native-shiori/build-aosora-macos.sh ~/src/aosora-shiori
```

`utatane-macos`には、macOSで見つかった実行スタック初期化の修正が入っています。上流へ取り込まれたら普通の上流版へ戻す予定です。

標準の配置先は次の場所です。

```text
~/Library/Application Support/Utatane/NativeShiori/aosora/libaosora.dylib
```

別の場所へ置きたい場合は、`UTATANE_AOSORA_MODULE`へ絶対パスを指定します。

```sh
UTATANE_AOSORA_MODULE=/path/to/libaosora.dylib open Utatane.app
```

`Content/Local/Ghosts/demo`があれば、次のテストで起動とメニュー項目の応答まで確認できます。素材かモジュールがなければ何もせず終わります。

```sh
mise run test --filter 'installed Aosora demo answers OnBoot'
```

</details>
