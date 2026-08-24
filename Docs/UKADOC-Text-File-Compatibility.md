# UKADOC テキストファイル互換状況

UKADOCに掲載されているゴースト関連の設定・配布用テキストファイルと、Utataneの読み込み・利用状況をまとめる。

調査日: 2026-08-24  
調査対象: ローカルの `/Users/wamo/ws/ukadoc/manual` とUtatane本番Swiftコード

## 判定

| 記号 | 意味 |
| --- | --- |
| ✅ | UKADOCにある構文・項目を一通り読み込み、対応する機能で利用する |
| 🟡 | ファイルは読み込むが、未使用の項目・構文・挙動が残る |
| ❌ | ファイルまたは対応する本体機能が未実装 |

単にカンマ区切りを辞書へ格納できるだけでは対応扱いにしない。値がモデルや実行時の挙動へ反映されることを基準にした。

## 全体

| ファイル | 状況 | 現在の実装 | 主な不足 |
| --- | --- | --- | --- |
| Ghost `descript.txt` | 🟡 | UTF-8／Shift_JIS、基本情報、SHIORI名、キャラクター名、既定surface・balloon、更新URL、README、推奨balloon | 74項目中、配置、SSTP制御、SHIORI詳細設定、カーソル、メニュー、アイコン等が未反映 |
| Shell `descript.txt` | 🟡 | UTF-8／Shift_JIS、名前、`seriko.use_self_alpha`、bindgroup／bindoption | 102項目中、初期配置、balloon offset、メニュー装飾、z-order、sticky-window等が未反映 |
| Balloon `descript.txt` | 🟡 | UTF-8／Shift_JIS、名前・type、文字領域、折返し、基本フォント、装飾・shadow、arrow座標、cursor／anchorのstyle・色 | 162項目中、visited、marker配置、入力欄、透過方式、ウインドウ位置等が未反映 |
| Plugin `descript.txt` | ❌ | なし | PLUGIN機構自体が未実装。UKADOC掲載13項目は未使用 |
| Headline `descript.txt` | 🟡 | UTF-8／Shift_JIS／ASCII、名前、DLL名、URL、open URL、homeurl、charset、alwaysdisplay。RSS用`type`・`feed`拡張も利用 | UKADOC掲載9項目のうちreadme系が未使用。Windows DLL実行は実行環境依存 |
| `install.txt` | 🟡 | UTF-8／Shift_JIS、name、type、directory、Ghost同梱balloon、Ghost／Shell／Balloon／Headlineの安全な新規インストール | accept、bootghost、refresh、refreshundeletemask、汎用複数オブジェクト、上書き更新が未対応 |
| `delete.txt` | 🟡 | UTF-8／Shift_JIS、charset行、Windows区切りの相対ファイル・ディレクトリを更新後に安全確認して削除 | 更新本体と削除を合わせた完全なロールバックは未対応 |
| `developer_options.txt` | ❌ | なし | noupdate、compress、ignore等を読まず、更新定義・NAR生成へ反映しない |
| `surfaces.txt`／`surfaces*.txt` | 🟡 | 複数ファイル結合、surface selector、append、alias、element、rect／polygon collision、主要animation | 後述のSERIKO構文・描画メソッド・surface属性が多数未対応 |
| `surfaces2.txt` | 🟡 | `surfaces`で始まるため読み込む | SSP用上書きではなく、他のsurfacesファイルとファイル名順で単純結合する |
| `alias.txt` | 🟡 | surfaces文書として追加読込し、sakura／kero／char scope aliasを利用 | alias以外の互換挙動は未照合 |
| `surfacetable.txt` | ✅ | charset、version、option、group、scope、surface IDと名前を解析。`DisableNoDefineSurfaces`、`__disabled`、`__parts`も利用 | 実機UIでの全表示差は未確認 |
| `updates2.dau` | 🟡 | path・MD5・size・date・charsetを解析し、取得・サイズ／MD5検証・ロールバック更新。生成はCRLFで拡張フィールドも出力 | date・charsetは保持のみ。削除を含めた完全なトランザクションは未対応 |
| `updates.txt` | 🟡 | `charset,`と`file,`行、path・MD5・拡張フィールド、未知行の無視に対応 | Version 3形式の生成は未対応 |
| `readme.txt`／`readme.md` | 🟡 | 既定候補をmacOSの関連アプリで開く | descript.txtのreadme・readme.charset指定を参照しない。Markdownの独自表示はしない |

現状は ✅ 1 / 🟡 12 / ❌ 2。

## Ghost descript.txt

UKADOC掲載は74項目。汎用パーサーはコメントと空行を除いた`key,value`を保持するが、実際に利用するのは次の項目群。

| 状況 | 項目 |
| --- | --- |
| 利用 | `name`、`shiori`、`balloon`、`sakura.name`、`kero.name`、`char*.name` |
| 利用 | `sakura.seriko.defaultsurface`、`kero.seriko.defaultsurface`、`char*.seriko.defaultsurface` |
| 利用 | `balloon.defaultsurface`、scope別`balloon.defaultsurface` |
| 別経路で利用 | `homeurl`、`readme.txt`候補 |
| 未反映 | charset宣言、作者・ID・title、readme指定、配置・alignment、SSTP設定、SHIORI version/cache/encoding、イベント抑制、カーソル、メニュー、アイコン、install.accept、推奨balloon関連 |

文字コードはファイル内`charset`ではなく、UTF-8を試してからShift_JISへフォールバックする。

## Shell descript.txt

UKADOC掲載は102項目。現在利用するのはかなり限定的。

| 状況 | 項目 |
| --- | --- |
| 利用 | `name`、`seriko.use_self_alpha` |
| 利用 | scope別`bindgroup*.name/default/addid` |
| 利用 | scope別`bindoption*.group`の`mustselect`・`multiple` |
| 未反映 | 基本メタデータ、readme、menu表示、名前上書き、z-order、sticky-window、DPI、初期配置、balloon offset/alignment/dontmove/syncscale、menuitem、全メニュー装飾、透過・crossfade、アイコン枠色 |

SakuraScriptからのz-orderやsticky-window操作は実装済みだが、Shell `descript.txt`の初期値は読んでいない。

## Balloon descript.txt

UKADOC掲載は162項目。現在の実利用項目は以下。

| 状況 | 項目 |
| --- | --- |
| 利用 | `type`、`name`、`origin.x/y`、`validrect.left/top`、`wordwrappoint.x/y` |
| 利用 | `font.name`、`font.height`、`font.color.r/g/b`、`font.shadowcolor.r/g/b`、`font.shadowstyle` |
| 利用 | `font.bold`、`font.italic`、`font.underline`、`font.strike`、`font.outline`、`arrow0.x/y`、`arrow1.x/y` |
| 利用 | cursor、cursor.notselect、anchor、anchor.notselectの`style`、font／pen／brush RGB |
| 画像として利用 | balloon画像、marker画像、arrow画像。ただしfilename指定ではなく既定ファイル名を探索 |
| 未反映 | validrect右・下、vertical、disable.font、blendmethod、visited anchor、各marker座標・間隔・文字、number書式、communicatebox、透過方式、windowposition、filename差替え、recommended ghost |

`origin`が0または未定義なら`validrect.left/top`へフォールバックする独自の互換処理がある。

## Headline descript.txt

UKADOC掲載9項目のうち、`charset`、`name`、`dllname`、`url`、`openurl`、`alwaysdisplay`をカタログで利用する。`homeurl`は共通のネットワーク更新URL探索で利用する。`readme`、`readme.charset`は未使用。

RSS型についてはUKADOCのHEADLINE DLL項目に加え、`type,rss`と`feed,URL`をUtatane拡張として扱う。

## install.txt

UKADOC掲載の主要15項目・構文に対する状況。

| 項目・構文 | 状況 | 備考 |
| --- | --- | --- |
| charset | 🟡 | 宣言値は参照せずUTF-8→Shift_JISで判定 |
| name | ✅ | インストール結果の表示名に利用 |
| type | 🟡 | ghost、shell、balloon、headlineに対応。他種別は拒否 |
| directory | ✅ | 1階層の安全な名前に限定して利用 |
| accept | ❌ | 対象ゴースト名の制限なし |
| bootghost | ❌ | インストール後起動なし |
| refresh | ❌ | 既存インストール先は上書きせず失敗 |
| refreshundeletemask | ❌ | 未実装 |
| `*.directory`／`*.source.directory` | 🟡 | Ghost同梱balloonのみ対応 |
| `*.refresh`／`*.refreshundeletemask` | ❌ | 未実装 |
| developer_optionsの相対パス規則 | ❌ | ファイル自体を未読込 |

アーカイブについてはパストラバーサル、絶対パス、バックスラッシュ、シンボリックリンク、特殊ファイル、過大な件数・容量を拒否し、途中失敗時は作成済み項目を戻す。これはUKADOC互換とは別の安全策。

## surfaces.txt・alias.txt

UKADOCの定義項目・キーワードは137。現在の対応範囲は次の通り。

| 分類 | 状況 | 対応内容 |
| --- | --- | --- |
| surface選択 | 🟡 | 単一ID、範囲、列挙、除外、`surface.append` |
| alias | 🟡 | sakura、kero、char scopeの名前→surface ID候補 |
| element | 🟡 | PNG／PNA、base・overlay系。画像形式・全描画オプションは未網羅 |
| collision | 🟡 | 矩形、collisionex rect／polygon |
| animation基本 | 🟡 | name、interval文字列、pattern、wait、座標 |
| interval | 🟡 | runonce、sometimes、rarely、talk、bindを実行。random、periodic、always、never、yen-e、starttalk、endtalk等は未実装 |
| pattern method | 🟡 | base、overlay、overlay-fast、stopを実装。move、startや多数のblend・制御methodは未実装 |
| animation option／collision | ❌ | exclusive、background、shared-index、animation固有collision等を保持しない |
| surface属性 | ❌ | maxwidth、sort、balloon offset、各point、icon.rect、surface name等を保持しない |
| cursor定義 | ❌ | collision別mouse cursor定義を保持しない |

`surfaces*.txt`は全てファイル名順に連結する。`surfaces2.txt`の「SSPだけへ上書き」という優先規則は専用実装していない。

## surfacetable.txt

UKADOC掲載6構文（charset、version、option、group、scope、surface ID行）は全て解析対象。UI用のgroupと名前、未定義surface非表示、disabled group、parts表示をモデルへ保持するため、この一覧では✅とした。

## 更新定義

読み込みでは`updates2.dau`を先に試し、取得できなければ`updates.txt`へフォールバックする。pathと32桁MD5を検証し、変更ファイルだけを一時領域へ取得してから置換する。

size／date／charset拡張フィールドとVersion 3の`charset,`・未知行を解析し、sizeとMD5はダウンロード結果の検証にも使う。生成するVersion 2はsize／date、先頭行のcharset、CRLFを出力する。

`delete.txt`はcharset行・コメントを除いたWindows区切りの相対パスを読み、更新後にファイルまたはディレクトリを削除する。絶対パス・空要素・`.`・`..`は拒否する。更新済みファイルの置換と削除処理をまとめた完全なロールバックは今後の課題。

生成処理は引き続きdeveloper_options.txtを無視し、`.DS_Store`、`*_variable.cfg`、更新定義自身だけを固定で除外する。

## 優先度

1. Ghost／Shell descript.txtの配置・balloon offset・alignmentを既存ウインドウ機能へ接続する。
2. `install.txt`のaccept、refresh、複数同梱オブジェクトを実装する。
3. Balloon descript.txtのフォント装飾・marker・visitedを既存描画へ接続する。
4. surfaces.txtのanimation option、surface属性、未対応pattern methodを段階的に追加する。
5. developer_options.txtを更新定義生成と将来のNAR生成で共通利用する。
