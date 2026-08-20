# ゴースト互換状況

「対応」と書いてあっても、全機能の完全再現ではありません。起動と基本会話を中心に見ています。

| ゴースト | SHIORI | 状況 | 主な残りもの |
| --- | --- | --- | --- |
| Emily/Phase4.5 | YAYA | 起動、会話、マウス反応をテスト済み | 未対応のSakuraScriptやSERIKO |
| めもりーな | SATORI | 起動、会話、SSU、システム情報をテスト済み | `exec.dll`、`proxy.dll`など外部処理 |
| ユグドラシルチェリィ | SATORI | 起動、2キャラクター、シェル切り替えをテスト済み | `ukastream.dll`を使うルーレット |
| 酒の神さま | SATORI | 起動と`kenonoke.dll`のキーワード分類をテスト済み | 音声系SAORI、画面効果 |
| COLORSβ | KAWARI | 起動、シェル、クリップボードをテスト済み | COLORS専用SAORIは後回し |
| Aosora demo | Aosora | 外部macOSモジュールで実際に起動確認済み | 上流変更への追従、配布方法 |
| さくらとうにゅ（FIRST） | Materia FIRST | Wine経由の専用実験対応 | 起動が遅い、Wine依存、互換範囲狭め |

## SAORI

| モジュール | 状況 | 補足 |
| --- | --- | --- |
| SSU | 対応 | SATORI同梱実装 |
| `saori_cpuid.dll` | 対応 | macOSの情報を返す互換実装 |
| `kenonoke.dll` | 対応 | `keyword.txt`による分類 |
| `textcopy2.dll` | 対応 | macOSのクリップボードへ書き込み |
| `exec.dll` / `process.dll` / `proxy.dll` | 未対応 | 権限と安全な挙動を決めてから |
| その他のWindows DLL | 原則未対応 | Wineへ何でも投げる方針にはしない |

実ゴーストを手元へ置く場所やテスト方法は[開発ガイド](Development.md)と[Native SHIORI / SAORI](Native-SHIORI.md)を参照してください。
