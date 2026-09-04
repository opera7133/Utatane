# Utataneドキュメント

Utataneを使う人、ゴーストや拡張を作る人、Utatane本体を開発する人向けの資料をまとめています。迷った場合は、目的に近い項目から読んでください。

## Utataneを使う

- [ゴースト互換状況](Compatibility.md): 実際に確認したゴースト、SHIORI、SAORIと既知の制約
- [Realtime音声会話](Realtime-Voice.md): OpenAI Realtime APIまたは互換APIを使った音声会話の設定
- [Native SHIORI / SAORI](Native-SHIORI.md): Wineなしで動く人格エンジンと、外部モジュール・Wineフォールバックの対応範囲

基本的なインストール、ゴーストの追加、Materia付属FIRSTの配置方法は[プロジェクトREADME](../README.md)にあります。

## ゴースト・シェル・拡張を作る

最初に[Utatane対応ガイド](Content-Authoring.md)を読んでください。新規制作と、既存のSSP向け資産をUtataneでも動かす場合の進め方を分けて説明しています。

- [SakuraScript互換状況](UKADOC-SakuraScript-Compatibility.md): 表示命令と実行命令の対応範囲
- [SHIORIイベント互換状況](UKADOC-SHIORI-Event-Compatibility.md): Utataneが通知するイベントとReference
- [テキストファイル互換状況](UKADOC-Text-File-Compatibility.md): descript、install、surfaces、更新定義など
- [SSTP互換状況](UKADOC-SSTP-Compatibility.md): SSTPリクエストとEXECUTE命令
- [nijigenerateシェル拡張](nijigenerate-shell.md): 通常シェルと併用するパペット、表情、視線・ドラッグ反応の設定
- [ネイティブプラグイン](Native-Plugins.md): macOS用モジュールのABIと、内蔵SHIORI・Wineを使うプラグインの実行方式

互換表の「対応」は、SSPの全挙動との完全一致を意味しません。配布前には、対象ゴーストで起動、会話、入力、シェル、更新、外部モジュールを実際に確認してください。

## Utatane本体を開発する

- [開発ガイド](Development.md): 必要な環境、ビルド、テスト、コンテンツ検証CLI、ディレクトリ構成
- [リリース手順](Release.md): バージョン、配布アーカイブ、Sparkle署名、appcast、Webサイト公開
- [Native SHIORI / SAORI](Native-SHIORI.md): 内蔵人格エンジンとモジュール実行経路

## 目的から探す

| やりたいこと | 読むもの |
| --- | --- |
| 手元のゴーストが動くか知りたい | [ゴースト互換状況](Compatibility.md) |
| 新しいゴーストを作りたい | [Utatane対応ガイド](Content-Authoring.md) |
| SSP向けゴーストを移行したい | [Utatane対応ガイド](Content-Authoring.md)、各[互換表](UKADOC-Text-File-Compatibility.md) |
| SHIORI・SAORIの実行方式を知りたい | [Native SHIORI / SAORI](Native-SHIORI.md) |
| nijigenerateをシェルで使いたい | [nijigenerateシェル拡張](nijigenerate-shell.md) |
| macOS用プラグインを作りたい | [ネイティブプラグイン](Native-Plugins.md) |
| ソースをビルド・検査したい | [開発ガイド](Development.md) |
| Utataneをリリースしたい | [リリース手順](Release.md) |
