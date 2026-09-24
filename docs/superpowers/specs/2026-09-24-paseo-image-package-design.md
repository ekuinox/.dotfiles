# paseo を公式コンテナイメージから組む設計（aarch64-linux 限定）

## 背景と目的

yomogi（Raspberry Pi 4, aarch64-linux）で paseo を更新しようとすると、home-manager switch が
30〜60 分かかり、`npm ci` が RSS 3.7GB を要求する。yomogi は RAM 7.7GB / swap なしのため、
この更新は実質的に「気軽にはできない作業」になっている。

その結果として実害が出た。paseo のモデル一覧は
`packages/server/dist/server/server/agent/providers/claude/model-manifest.js` に静的に
焼き込まれており、動的な取得を一切しない。yomogi の paseo は flake の pin（rev `7c430777bf`、
2026-08-22）由来の 0.5.0-beta.5 で止まっていたため、上流が追加した新モデルが出てこなかった。

- Fable 5.1: 上流が 2026-09-01 に追加（#4179）
- Opus 5.5: 上流が 2026-09-22 に追加（#5200）

claude-code 2.1.280 のバイナリには `claude-opus-5-5` と `claude-fable-5-1` の両方が含まれており、
CLI 側は対応済みである。ボトルネックは paseo の pin だけだった。

本設計の目的は、yomogi における paseo のビルドを廃し、更新を現実的なコストに下げることにある。

## 調査で確認した事実

### 上流の nix パッケージはモノレポ全体をビルドしている

`nix/package.nix` は `buildNpmPackage` に `src = lib.cleanSourceWith { src = ./..; ... }` を渡す。
workspace 全体の依存を `npm ci` し、そこからビルドする。30〜60 分と RSS 3.7GB はこれが原因である。

### 同じ成果物が既に配布されている

上流の `.github/workflows/docker.yml` が `PLATFORMS: linux/amd64,linux/arm64` でマルチアーキ
ビルドし、`ghcr.io/getpaseo/paseo` に push している。2026-09-24 時点でタグは 58 個、`latest` あり。

0.9.1 の arm64 イメージは 12 レイヤ・289MB（圧縮時）。Debian ベースで node 22.23.2 を含む。
内部構成は次のとおり。

- `/usr/local/lib/node_modules/@getpaseo/` に `cli` `client` `highlight` `plugin` `protocol` `relay` `server`
- `/usr/local/bin/paseo`
- `node_modules` は解決済みで 19,256 エントリ

### ネイティブアドオンはビルド済み同梱である

`.node` ファイルは 9 個あり、いずれも prebuilds 形式でプラットフォーム別に同梱されている。
インストール時のコンパイルは発生しない。

```
node-pty/prebuilds/linux-arm64/pty.node
sherpa-onnx-linux-arm64/sherpa-onnx.node
```

ただし Debian でリンクされているため、nixpkgs の node と組み合わせるには `autoPatchelfHook` が要る。
上流の `package.nix` も同じ理由で `autoPatchelfHook` と `libuv` を入れている。

### ghcr は匿名では blob を取れない

`https://ghcr.io/v2/getpaseo/paseo/blobs/<digest>` への認証なしアクセスは 401 を返す。
素の `fetchurl` では取得できない。`dockerTools.pullImage` は内部で skopeo（yomogi の nixpkgs では
1.23.0）を使い匿名トークンの取得を代行するため、こちらを用いる。

### 検討して退けた選択肢

- 自前で CI とバイナリキャッシュを立てる: yomogi の nix はマルチユーザ構成で
  `trusted-users = root` のため、ユーザ権限で substituter を追加しても daemon に無視される。
  各ホストで root 権限の作業が別途必要になる。上流がコンテナイメージを配布している以上、
  paseo 一つのために負う投資としては見合わない。
- npm パッケージ（`@getpaseo/server` ほか）から組む: `bundleDependencies` が false で
  tarball に `package-lock.json` も入らないため、バージョンごとにロックファイルを生成・維持する
  必要がある。イメージ経由なら解決済みの `node_modules` がそのまま手に入るため、
  更新作業が digest の書き換えだけで済む。

## 方針

- **対象は aarch64-linux のみ**とする。x86_64-linux（hizake / ume）と aarch64-darwin（yuri）は
  従来どおり flake input を使い、一切変更しない。x86 機ではビルド時間が問題になっていないため、
  影響範囲を yomogi だけに閉じる。
- flake の `paseo` input は**残す**。他 3 ホストが引き続き使う。
- 参照するイメージは version / digest / FOD ハッシュを持つサイドカー JSON に固定する。
  上流の `package.nix` が `npm-deps.hash` を別ファイルに切り出しているのと同じ流儀に合わせる。
- 更新はスクリプト 1 本で完結させ、差分がサイドカーの数行に収まるようにする。

## スコープ外

- hizake / ume / yuri の paseo 取得方法の変更
- sumomo / aoi への paseo 導入（従来どおり入れない）
- バイナリキャッシュの構築
- `modules/paseo.nix` が提供する systemd ユニットや PATH 設定の変更

## 変更内容

### `dot_config/home-manager/packages/paseo-image.nix`（新規）

`dockerTools.pullImage` で arm64 イメージを取得し、レイヤを展開して
`/usr/local/lib/node_modules` と `/usr/local/bin/paseo` を取り出し、nixpkgs の `nodejs_22` で
ラップする derivation。

- サイドカー `paseo-image.json` から version / digest / hash を読む。
- `autoPatchelfHook` と `libuv` を通し、prebuilds の `.node` を nix の動的リンカに適合させる。
- `meta.platforms = [ "aarch64-linux" ]` を明示し、他プラットフォームでの誤評価を防ぐ。
- `meta.version` はサイドカーの version を反映する。

### `dot_config/home-manager/packages/paseo-image.json`（新規）

```json
{
  "version": "0.9.1",
  "imageDigest": "sha256:ee6af9593253ec745a40e745b79dfdf0138bcb7882da86d4b12be1eb78638667",
  "hash": "sha256-..."
}
```

`imageDigest` は arm64 マニフェストの digest（マルチアーキのインデックスではなく、
アーキテクチャ固有のもの）。上の値は 0.9.1 の実測値である。

`hash` は `pullImage` の fixed-output ハッシュで、実装時に取得して埋める。
設計上の未決事項ではなく、値が実行して初めて確定する種類のもの。

### `dot_config/home-manager/packages/update-paseo-image.sh`（新規）

サイドカーを書き換える更新スクリプト。次を順に行う。

1. ghcr のタグ一覧から最新の安定版タグを決める。`latest` と、`-beta` `-rc` `-alpha` を含むタグ、
   および数字で始まらないタグを除外し、残りをバージョン順に並べた最後を採る
2. そのタグのマルチアーキインデックスから `linux/arm64` のマニフェスト digest を解決する
3. `pullImage` の FOD ハッシュを求める
4. `paseo-image.json` を書き換える

実行ホストを問わず動くようにし、yomogi 以外からでも更新できる状態にする。

### `dot_config/home-manager/modules/paseo.nix`（変更）

`let` でパッケージの選択に分岐を入れる。モジュール引数の `paseo`（flake input 由来）は
引き続き受け取る。

```nix
let
  paseoPkg =
    if pkgs.stdenv.hostPlatform.system == "aarch64-linux"
    then pkgs.callPackage ../packages/paseo-image.nix { }
    else paseo;
in
```

現在 `paseo` を参照している箇所は 2 つあり、どちらも `paseoPkg` に差し替える。

- `home.packages = [ paseo ];`
- `ExecStart` 内の `exec ${paseo}/bin/paseo start --foreground`

systemd ユニットの定義、PATH の指定、`PASEO_PRIMARY_LAN_IP` の動的解決はいずれも変更しない。
`flake.nix` も変更しない。

## 更新の運用

更新経路は 2 本になる。

```
# hizake / ume / yuri 向け（従来どおり）
nix flake update paseo

# yomogi 向け
./dot_config/home-manager/packages/update-paseo-image.sh
```

いずれも差分は数行で、コミットして PR を出し hms する流れは現状と変わらない。
yomogi 側は hms 時のビルドが消え、イメージのダウンロードのみになる。

**yomogi だけバージョンがずれうる。** 本設計はこれを許容する。揃えたいときは 2 つのコマンドを
両方実行する運用とし、同期は強制しない。

## 検証

yomogi 上で次を確認する。

1. `nix build` が `npm ci` を実行せずに完了すること
2. `paseo --version` がサイドカーの version を返すこと
3. `paseo daemon status --json` の `connectedDaemon` が `reachable` になること
4. 上流 CI と同じスモークテスト（デーモンを起動し、Web UI に curl が通ること）
5. `list_models` に `claude-opus-5-5` と `claude-fable-5-1` が現れること

hms の実行は paseo.service を再起動し、paseo 経由の Claude セッションを落とすため、
`systemd-run --user` で切り離して行う。

## 既知のリスクと撤退方法

- `autoPatchelfHook` が Debian ビルドの prebuilds を拾いきれない可能性がある。
  その場合はイメージ内の node 22.23.2 ごと取り込み、nixpkgs の `nodejs_22` を使わない形に倒す。
- イメージ内 node（22.23.2）と nixpkgs `nodejs_22` の細かいバージョン差で動作しない可能性がある。
  対処は上と同じ。
- 上流がイメージのレイアウト（`/usr/local/lib/node_modules` の配置など）を変えると壊れる。
  上流の `package.nix` と違い、この derivation の保守はこちら持ちになる。

いずれの場合も、`modules/paseo.nix` の分岐を削除すれば従来の flake input 経由に戻せる。
撤退は 1 ファイルの数行を消すだけで済む。
