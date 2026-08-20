# Native SHIORI / SAORI

なるべくWineを使わずにゴーストを動かすための話です。KAWARIはアプリへ静的リンク、Aosoraは外部のmacOS用dynamic libraryを読み込みます。

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
