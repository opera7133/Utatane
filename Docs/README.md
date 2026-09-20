# Utataneドキュメント

Utataneを使う人、ゴーストや拡張を作る人、Utatane本体を開発する人向けの資料をまとめています。迷った場合は、目的に近い項目から読んでください。

Web版の公開先は [Utataneドキュメント](https://dl.wmsci.com/utatane/docs/) です。アプリの「Utataneヘルプ」では、同じ原稿から生成した利用者向けの説明をオフラインで読めます。

原稿は用途別のフォルダにまとめています。WebのURLやアプリへの同梱対象は、フォルダとは独立して `navigation.json` で管理します。

| フォルダ | 読みたいこと |
| --- | --- |
| `Guide/` | 導入、日常の操作、設定、音声、保存場所 |
| `Support/` | トラブル対処、ゴースト・SHIORIの互換性 |
| `Creators/` | ゴースト、SHIORI、シェル、プラグインの制作 |
| `Reference/` | 命令、イベント、ファイル、SSTPの対応表 |
| `Development/` | 本体のローカルビルド、変更、テスト、ドキュメントへの貢献 |

## はじめに・基本操作

- [はじめてのUtatane](Guide/Getting-Started.md): 用語、インストール、初回起動
- [ゴーストと遊ぶ](Guide/Basic-Operations.md): 会話、マウス操作、配置、切り替え、終了
- [コンテンツを管理する](Guide/Content.md): NAR、SSP取り込み、エクスプローラ、更新、削除
- [設定を調整する](Guide/Settings.md): 各カテゴリの項目と適用範囲
- [カレンダー・ニュース・拡張](Guide/Features.md)
- [保存場所とバックアップ](Guide/Storage.md)
- [メニューとショートカット](Guide/Shortcuts.md)
- [困ったとき](Support/Troubleshooting.md): 症状別の確認と報告

## Utataneを使う

- [ゴースト互換状況](Support/Compatibility.md): 実際に確認したゴースト、SHIORI、SAORIと既知の制約
- [Utatane NAR検査](https://utatane-validate.wmsci.com/): NARをアップロードしてSHIORIと基本的な対応状況を確認
- [ウィンドウモード](Guide/Window-Mode.md): 配信・画面収録向けの単一ウィンドウ表示、背景、スクリーンショット、発話履歴
- [Realtime音声会話](Guide/Realtime-Voice.md): OpenAI Realtime APIまたは互換APIを使った音声会話の設定
- [音声合成・音声認識](Guide/Speech.md): macOS標準、ローカル音声合成ソフト、クラウド音声合成と音声認識の設定
- [IP Messenger](Guide/IP-Messenger.md): 同じLAN上のSSP・IP Messengerとのメッセージ送受信
- [Native SHIORI / SAORI](Support/Native-SHIORI.md): Wineなしで動く人格エンジンと、外部モジュール・Wineフォールバックの対応範囲

基本的なインストール、ゴーストの追加、Materia付属FIRSTの配置方法は[プロジェクトREADME](../README.md)にあります。

## ゴースト・シェル・拡張を作る

最初に[Utatane対応ガイド](Creators/Content-Authoring.md)を読んでください。新規制作と、既存のSSP向け資産をUtataneでも動かす場合の進め方を分けて説明しています。

- [SHIORI開発者向け対応ガイド](Creators/SHIORI-Development.md): 独自SHIORIの新規開発・移植、macOS用ABI、SHIOLINK、検証と配布
- [SakuraScript互換状況](Reference/UKADOC-SakuraScript-Compatibility.md): 表示命令と実行命令の対応範囲
- [SHIORIイベント互換状況](Reference/UKADOC-SHIORI-Event-Compatibility.md): Utataneが通知するイベントとReference
- [テキストファイル互換状況](Reference/UKADOC-Text-File-Compatibility.md): descript、install、surfaces、更新定義など
- [SSTP互換状況](Reference/UKADOC-SSTP-Compatibility.md): SSTPリクエストとEXECUTE命令
- [nijigenerateシェル拡張](Creators/nijigenerate-shell.md): 通常シェルと併用するパペット、表情、視線・ドラッグ反応の設定
- [ネイティブプラグイン](Creators/Native-Plugins.md): macOS用モジュールのABIと、内蔵SHIORI・Wineを使うプラグインの実行方式

互換表の「対応」は、SSPの全挙動との完全一致を意味しません。配布前には、対象ゴーストで起動、会話、入力、シェル、更新、外部モジュールを実際に確認してください。

## Utatane本体の開発に参加する

- [ローカル開発ガイド](Development/Development.md): 必要な環境、ビルド、テスト、コンテンツ検証CLI、ディレクトリ構成
- [ドキュメントへの貢献](Development/Documentation.md): Web・同梱ヘルプの編集、ローカル確認、ページや画像の追加
- [Native SHIORI / SAORI](Support/Native-SHIORI.md): 内蔵人格エンジンとモジュール実行経路

## 目的から探す

| やりたいこと | 読むもの |
| --- | --- |
| 手元のゴーストが動くか知りたい | [Utatane NAR検査](https://utatane-validate.wmsci.com/)、[ゴースト互換状況](Support/Compatibility.md) |
| ゴーストをウィンドウ単位で収録したい | [ウィンドウモード](Guide/Window-Mode.md) |
| ゴーストの発話を読み上げたい | [音声合成・音声認識](Guide/Speech.md) |
| 同じLAN上のSSP・IP Messengerと会話したい | [IP Messenger](Guide/IP-Messenger.md) |
| 新しいゴーストを作りたい | [Utatane対応ガイド](Creators/Content-Authoring.md) |
| SSP向けゴーストを移行したい | [Utatane対応ガイド](Creators/Content-Authoring.md)、各[互換表](Reference/UKADOC-Text-File-Compatibility.md) |
| 自作SHIORIをUtataneに対応させたい | [SHIORI開発者向け対応ガイド](Creators/SHIORI-Development.md) |
| SHIORI・SAORIの実行方式を知りたい | [Native SHIORI / SAORI](Support/Native-SHIORI.md) |
| nijigenerateをシェルで使いたい | [nijigenerateシェル拡張](Creators/nijigenerate-shell.md) |
| macOS用プラグインを作りたい | [ネイティブプラグイン](Creators/Native-Plugins.md) |
| ソースをビルド・検査したい | [ローカル開発ガイド](Development/Development.md) |
| ドキュメントを修正したい | [ドキュメントへの貢献](Development/Documentation.md) |
