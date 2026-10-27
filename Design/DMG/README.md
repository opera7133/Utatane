# DMG背景アセット

Utataneの配布用DMGで使う背景です。アプリの白黒アイコンと公式サイトの控えめな青緑に合わせ、淡い地色と右向きの矢印を置いています。編集元は`background.svg`です。

## 編集と書き出し

`background.svg`の色・パス・文字・矢印を編集し、リポジトリのルートで実行します。macOS、Python 3、librsvgが必要です。

```sh
brew install librsvg
python3 Scripts/export-dmg-assets.py
```

既定の出力先はGit管理外の`build/dmg-assets/`です。`--output /path/to/output`で変更できます。繰り返し実行すると、その出力先の生成ファイルを更新します。

| ファイル | 用途 |
| --- | --- |
| `background.png` | 768 × 512 px、72 dpiの1x画像 |
| `background@2x.png` | 1536 × 1024 px、144 dpiの2x画像 |
| `background.tiff` | 同じ768 × 512 ptを表す1x/2x画像を格納。Finder背景用 |
| `layout.json` | ウィンドウ寸法とアイコン配置 |
| `manifest.json` | SVG・生成物のハッシュとレンダラーの版 |

通常の編集ではSVGを変更して再出力します。PNG・TIFFは生成物として扱います。文字は編集可能なテキストで、書き出し時のフォントはHelvetica Neueを優先します。

## 配置

アプリとApplicationsへのショートカットはFinderで配置し、背景へ描き込みません。`layout.json`は768 × 512 ptのウィンドウを想定し、座標はコンテンツ領域の左上基準です。左右の中心はそれぞれ(208, 256)、(560, 256) pt、アイコンサイズは96 ptです。ファイル名はFinder側で表示するため、説明文の言語は背景へ固定していません。

## DMGの生成と検証

固定したdmgbuildでFinderを操作せずに作成します。Python 3.13とuvが必要です。

```sh
uv run --project Scripts/dmg --locked --no-config python Scripts/build-dmg.py \
  --app /path/to/Utatane.app --assets build/dmg-assets \
  --output build/Utatane-macOS.dmg
```

生成後に読み取り専用でマウントし、背景のハッシュ、ウィンドウ寸法、アイコン座標、Applicationsリンクとアプリのコード署名を検証してアンマウントします。`--require-app-ticket`を付けると格納したアプリの公証チケットも検証します。既存画像は上書きしません。`--verify-only`で既存DMGを検査できます。

タグ付きリリースではSVGを書き出した結果・配置・生成スクリプト・依存ロックを署名済みアプリの候補と一緒に保存します。本体の公証とチケット添付後にDMGを作り、DMG自体にも署名・公証・チケット添付を行います。Sparkleとダウンロード案内も同じ最終DMGを使います。公開済みの以前のZIPはそのまま利用できます。
