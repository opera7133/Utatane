# Changelog

## [0.1.0-alpha.11] - 2026-08-25

### 追加

- SSTP互換状況の文書を追加。Socket SSTP・SSTP over HTTP・各メソッドとEXECUTE commandの対応範囲を整理
- SSTPレスポンスに任意ヘッダーと追加データを付与できるようにし、UKADOC仕様どおり空行に続けてデータを返せるようにした
- SakuraScriptにオンラインモード、ユーザー割り込み禁止モード、誘導・受動インタラクションモード、コリジョン表示モード、同期オブジェクトの命令を追加
- SakuraScriptでキャラクターを絶対座標へ移動する`setPosition`と`resetPosition`を追加
- SakuraScriptの再生をキューイングする`enqueue`メソッドを追加し、`Option: nobreak`で実行中の再生完了後へ続けられるようにした
- surfaces.txtのdescriptブロックで`maxwidth`・`collision-sort`・`animation-sort`を読み取るようにした
- surfaces.txtのサーフェス定義で`name`・`balloonoffset`・`point`・`icon`などのフィールドを読み取るようにした
- NARのinstall.txtで`type,package`を扱い、パッケージ内の複数コンテンツをまとめてインストールできるようにした
- NARのinstall.txtで`accept`フィールドを読み取り、指定外のゴーストへのインストールを拒否するようにした
- NARを圧縮する際に`.narignore`・`.narinclude`と`developer_options.txt`の`nonar`オプションを反映してファイルを除外するようにした
- `descript.txt`を参照してゴースト・シェル・バルーンのREADMEファイルを解決する`ReadmeResolver`を追加
- 同梱ゴースト「りあ」にスリープ・復帰イベントへの応答と、脚のダブルクリック時の着せ替え会話の条件を修正

### 変更

- SakuraScriptのバルーン位置計算にサーフェスの`balloonoffset`を反映するようにした
- SSTPのバージョン検証を強化し、`Charset`ヘッダーの有無も確認するようにした
- 未知のSSTPメソッドに501を返すようにした

## [0.1.0-alpha.10] - 2026-08-24

### 追加

- SHIORIイベントの発行範囲を拡充。時刻、スリープ、表示状態、画面構成、システム負荷、キーボード、ゲームパッド、マウス、ドラッグ＆ドロップ、サーフェス変更、サウンド再生などをゴーストへ通知できるようにした
- SakuraScriptから使える入力ボックス、教示ボックス、コミュニケートボックスと、ゴースト・シェル・バルーン選択ダイアログを追加
- バルーンの`descript.txt`にあるフォント名、太字、斜体、下線、打ち消し線、縁取り、影の設定を表示へ反映
- ネットワーク更新の`updates2.dau`でsize、date、charsetの拡張フィールドを扱い、ダウンロードサイズも検証するようにした
- ネットワーク更新後に`delete.txt`で指定されたファイルを安全に削除できるようにした
- UKADOCに対するSHIORIイベントとテキストファイルの互換状況を文書化
- 同梱ゴースト「りあ」に眼鏡の着せ替えと対応する会話を追加

### 変更

- 同時に複数表示されていた入力・選択ダイアログを、要求を順番に処理する単一のウインドウへ整理
- 更新定義の生成形式をCRLFへ揃え、size、更新日時、charsetを出力するようにした
- SakuraScript互換状況の文書名を、他のUKADOC互換表と区別できる名前へ変更

## [0.1.0-alpha.9] - 2026-08-23

### 追加

- KAWARIを使うゴーストをネイティブ実行する経路を追加
- アプリと設定画面の日本語・英語ローカライズ用リソースを追加
- 同梱ゴースト「りあ」の日常、趣味、技術系の会話とシステムイベントへの応答を追加

### 修正

- KAWARIの辞書読み込み、リクエスト処理、文字コード処理の互換性を改善
- ランダムトークの発生条件を修正
- リリース時のVirusTotal結果の取り扱いを修正

## [0.1.0-alpha.8] - 2026-08-23

### 追加

- OpenAI、Anthropic、Gemini、OpenAI互換APIを選択できる実験的なAI人格機能を追加
- AI人格用の設定、APIキーのKeychain保存、同梱実験ゴーストからの利用経路を追加
- Materiaの「さくら」で使われるFIRSTを解析し、対応範囲をWineなしで実行するネイティブ経路を追加
- アプリ内でログやSHIORI通信を確認できるデバッグウインドウを追加

### 修正

- コンテンツ更新定義とデバッグウインドウの動作を修正

## [0.1.0-alpha.7] - 2026-08-22

### 追加

- ゴーストからUtataneとmacOSの状態を参照できるProperty Systemを追加
- SakuraScriptによるアーカイブ操作、更新定義生成、ウインドウ位置や表示状態の操作を拡充
- WebSocket経由のSakuraScript・SHIORI連携を拡充

### 修正

- バルーン内のマーカー位置を修正
- NARのインストール、SAORI呼び出し、SakuraScriptのアクション処理を改善

## [0.1.0-alpha.6] - 2026-08-22

### 追加

- SakuraScriptの対応命令を大幅に拡充。ウインドウ、バルーン、文字表示、選択肢、サーフェス、音声、外部通信などの命令を追加
- WebSocketセッションとネットワーク診断の基盤を追加
- `surfacetable.txt`の読み込みに対応
- UKADOCに基づくSakuraScript互換状況の文書を追加

### 修正

- SakuraScriptの`source.length`、パーサー、ウインドウ配置、シェル定義の処理を修正

## [0.1.0-alpha.5] - 2026-08-21

### 追加

- ゴーストとバルーンを配布元から更新するためのコンテンツマニフェスト生成・配信経路を追加
- シェルの着せ替え定義とbind操作への対応を拡充
- 同梱ゴースト「りあ」に冬服用の追加サーフェスと会話を追加

### 変更

- 同梱コンテンツの初回配置と更新URLの扱いを改善し、利用者が変更した内容を上書きしにくい構成へ変更

## [0.1.0-alpha.4] - 2026-08-21

### 追加

- SakuraScriptのバルーン制御、文字装飾、選択肢、サーフェス操作、待機、音声再生などに対応
- バルーンの定義読み込みとテキスト表示を拡充

### 変更

- 同梱ゴーストの会話とマウス操作を、新しいSakuraScript対応へ合わせて更新

## [0.1.0-alpha.3] - 2026-08-21

### 追加

- 同梱ゴースト「りあ」と専用バルーンを追加し、初回起動から利用できるようにした
- ゴーストと単体バルーンの手動・自動ネットワーク更新に対応
- SparkleによるUtatane本体の更新と、タグから配布物を作るリリース処理を追加
- 現在地の天気を取得し、ゴーストへ渡す機能を追加
- PNGの透過・合成処理と`overlay-fast`の互換性を改善

### 修正

- 同梱YAYAの状態ファイルが上書きされる問題を修正

## [0.1.0-alpha.2] - 2026-08-20

### 追加

- KAWARIと、外部ビルドしたAosoraモジュールの読み込みに対応
- `config.txt`形式のHEADLINE/2.0センサーをネイティブ実行し、Windows DLLをWine経由で呼ぶ実験的な経路を追加
- MateriaのFIRSTを専用ホストとWine経由で動かす開発用経路を追加
- エラー表示、進行状況ウインドウ、外観・表示倍率・起動方法などの設定を拡充
- Native SHIORIと互換状況の開発文書を追加

### 修正

- 読み込めないゴーストがあっても、ほかのゴーストを起動できるようにした
- Aosora、ネットワーク更新、SSTP、バルーン配置などの互換性を改善

## [0.1.0-alpha.1] - 2026-08-19

### 追加

- macOS上でゴースト、シェル、バルーンを表示・操作するUtataneの最初の公開版
- NARのインストール、展開済みSSPフォルダからの取り込み、複数ゴーストの起動に対応
- YAYAとSATORIを使うゴーストのネイティブ実行に対応
- SSTP over HTTP、RSS / Atom、ネットワーク更新の基礎機能を追加
- シェル・バルーンの倍率、ウインドウ位置、画面端補正などの設定を追加
- 起動中のゴーストを操作するstdio形式のMCPサーバーを同梱

[0.1.0-alpha.11]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.10...HEAD
[0.1.0-alpha.10]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.9...v0.1.0-alpha.10
[0.1.0-alpha.9]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.8...v0.1.0-alpha.9
[0.1.0-alpha.8]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.7...v0.1.0-alpha.8
[0.1.0-alpha.7]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.6...v0.1.0-alpha.7
[0.1.0-alpha.6]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.5...v0.1.0-alpha.6
[0.1.0-alpha.5]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.4...v0.1.0-alpha.5
[0.1.0-alpha.4]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.3...v0.1.0-alpha.4
[0.1.0-alpha.3]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.2...v0.1.0-alpha.3
[0.1.0-alpha.2]: https://github.com/opera7133/Utatane/compare/v0.1.0-alpha.1...v0.1.0-alpha.2
[0.1.0-alpha.1]: https://github.com/opera7133/Utatane/releases/tag/v0.1.0-alpha.1
