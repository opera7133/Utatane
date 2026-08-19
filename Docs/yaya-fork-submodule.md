# YAYA forkとsubmoduleへの移行手順

現在は、動作確認を先に進めるためYAYAのソースを
`packages/yaya-native/Sources/CYayaNative/Vendor/YAYA`へ直接配置している。
保守用forkの準備ができたら、同じ場所をgit submoduleへ置き換える。

## 1. 保守用forkを作る

YAYAの`500`ブランチ、commit `f64a42d`（tag `Tc573-6`）からGitHub上にforkを作る。
fork側には、たとえば`utatane-macos`ブランチを作成する。upstreamの履歴を保持し、
macOS対応を独立した少数のcommitに分ける。

現在のvendorコピーからforkへ移す変更は次のとおり。

vendorディレクトリにはUtataneがコンパイルするソースとヘッダーだけを置いている。
そのため、vendorディレクトリ自体でforkのルートを置き換えてはいけない。forkのルートへ
中身を上書きコピーし、upstream側のMakefile、Visual Studioプロジェクト、READMEなどは残す。
たとえばforkを別ディレクトリへcloneした後、次のようにコピーする。

```sh
cp -R packages/yaya-native/Sources/CYayaNative/Vendor/YAYA/. <YAYA_FORK_CHECKOUT>/
```

- CP932のソースをUTF-8へ変換する
- `boost::shared_ptr`と`boost::make_shared`を標準C++の実装へ置き換える
- Darwinの`FREAD`、`FWRITE`マクロとYAYA関数名の衝突を避ける
- `sha1.h`で標準の固定幅整数型を使う
- `basename`用にPOSIXの`libgen.h`を読み込む
- `ptrdiff_t`からYAYA整数型への変換を明示する
- 64bit整数リテラルと、廃止された`std::binary_function`を現代化する
- POSIX版`request`が入力バッファを必ず解放するよう所有権を統一する

Swiftとの境界である`YayaBridge.cpp`と`CYayaNative.h`はUtatane側に残す。
forkはYAYA本体の移植だけを扱う。

## 2. fork単体を検証する

fork側でApple ClangとC++17を使い、arm64の静的ライブラリまたはdylibをビルドする。
最低限、次をfork側のCIで確認する。

1. macOS arm64で全ソースがコンパイルできる
2. `multi_loadu`でEmilyの`ghost/master`をロードできる
3. `multi_request`へ`OnBoot`を送り、SHIORI 200と`Value`を受け取れる
4. `multi_unload`後に異常終了しない

Windows向けFMOと`LOADLIB / REQUESTLIB / UNLOADLIB`はmacOS CIの対象外とし、
未対応であることをforkのREADMEへ明記する。

## 3. vendorコピーをsubmoduleへ置き換える

forkのURLとブランチが確定した後、Utatane側で次の順に移行する。
実行前にvendor内の変更がすべてforkへpush済みであることを確認する。

```sh
git rm -r packages/yaya-native/Sources/CYayaNative/Vendor/YAYA
git submodule add -b utatane-macos <YAYA_FORK_URL> \
  packages/yaya-native/Sources/CYayaNative/Vendor/YAYA
git submodule absorbgitdirs
```

その後、通常の検証を実行する。

```sh
git submodule update --init --recursive
mise run check
```

`packages/Package.swift`の`CYayaNative`ターゲットは同じパスを参照しているため、
submodule化だけならSwift側のimportや製品名は変更しない。

## 4. 更新ルール

- upstreamの更新はforkへ取り込み、fork単体のCIを通してからsubmoduleのcommitを更新する
- Utatane固有のC ABIやアプリ都合の処理をYAYA forkへ入れない
- submoduleの参照更新とSwiftアダプターの変更は、可能なら別commitにする
- clone時は`--recurse-submodules`、既存cloneでは`git submodule update --init --recursive`を使う
- BSD 3-Clauseの`LICENSE`をforkとアプリ配布物の両方に含める
