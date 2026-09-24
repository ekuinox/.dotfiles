# paseo コンテナイメージ由来パッケージ 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** yomogi（aarch64-linux）の paseo を、上流が配布する arm64 コンテナイメージから組むことで、30〜60 分のソースビルドを廃する。

**Architecture:** `dockerTools.pullImage` で `ghcr.io/getpaseo/paseo` の arm64 イメージを取得し、`/usr/local/lib/node_modules` と `/usr/local/bin/paseo` を取り出して nixpkgs の `nodejs_22` でラップする。参照するイメージは version / digest / FOD ハッシュを持つサイドカー JSON に固定し、更新スクリプトがそれを書き換える。`modules/paseo.nix` は aarch64-linux のときだけこのパッケージを使い、他プラットフォームは従来の flake input のままにする。

**Tech Stack:** Nix（`dockerTools.pullImage`, `autoPatchelfHook`, `makeWrapper`）、nixpkgs `nodejs_22`、skopeo、home-manager、chezmoi

**Spec:** `docs/superpowers/specs/2026-09-24-paseo-image-package-design.md`

## Global Constraints

- 対象プラットフォームは `aarch64-linux` のみ。`meta.platforms = [ "aarch64-linux" ]` を明示する。
- `dot_config/home-manager/flake.nix` は変更しない。flake の `paseo` input は残す。
- 変更してよい既存ファイルは `dot_config/home-manager/modules/paseo.nix` のみ。
- `modules/paseo.nix` の systemd ユニット定義、`Environment` の PATH、`PASEO_PRIMARY_LAN_IP` の動的解決は変更しない。
- イメージ名は `ghcr.io/getpaseo/paseo` 固定。
- 2026-09-24 時点の実測値: 最新安定版は `0.9.1`、その arm64 マニフェスト digest は `sha256:ee6af9593253ec745a40e745b79dfdf0138bcb7882da86d4b12be1eb78638667`。
- コミットメッセージは日本語。yomogi では `~/.ssh/id_ed25519.pub` が無く署名が壊れているため、`git -c commit.gpgsign=false commit` を使う。
- chezmoi ソース（`~/.dotfiles/dot_config/home-manager/`）を編集する。ターゲット（`~/.config/home-manager/`）を直接編集しない。
- hms は paseo.service を再起動し paseo 経由の Claude セッションを落とすため、`systemd-run --user` で切り離して実行する。

## Review Focus

- **サイドカーの digest がマルチアーキのインデックスを指してしまう場合。** `pullImage` はアーキテクチャ固有のマニフェスト digest を要求する。インデックス digest を渡すと、取得はできても中身が amd64 になりうる。Task 1 で取り出したツリーが arm64 であることを ELF ヘッダで確認する。
- **`sherpa-onnx.node` の同梱 `.so` が解決できない場合。** `libsherpa-onnx-c-api.so` と `libonnxruntime.so` はパッケージ内に同梱されており、autoPatchelf が出力内を走査して解決する前提に立っている。解決できないとビルドが失敗する。Task 3 でこの 1 ファイルを名指しで検証する。
- **`bin/paseo` が相対 symlink のまま壊れる場合。** イメージ内の `/usr/local/bin/paseo` は `../lib/node_modules/@getpaseo/cli/bin/paseo` への相対 symlink。ディレクトリ構成を変えて取り出すとリンクが切れる。Task 2 で `paseo --version` が動くことで検証する。
- **`node` が PATH に無い状態で起動される場合。** `cli/bin/paseo` の shebang は `#!/usr/bin/env -S node --disable-warning=DEP0040` で、PATH の node に依存する。systemd ユニットの PATH には nixpkgs の node が含まれない可能性があるため、ラッパーで node を固定する。Task 2 で PATH を空にして起動できることを検証する。
- **aarch64-linux 以外で誤って評価される場合。** `modules/paseo.nix` は hizake / ume / yuri も読む。分岐を誤ると x86 や darwin で arm64 イメージを引こうとして壊れる。Task 4 で x86_64-linux として評価し、従来どおり flake input が選ばれることを確認する。

---

### Task 1: サイドカーとイメージ取得

**Files:**
- Create: `dot_config/home-manager/packages/paseo-image.json`
- Create: `dot_config/home-manager/packages/paseo-image.nix`

**Interfaces:**
- Produces: `paseo-image.json` は `{ version, imageDigest, hash }` の 3 キーを持つ。後続タスクと更新スクリプトがこのキー名に依存する。
- Produces: `packages/paseo-image.nix` は `callPackage` 可能な関数で、単一の derivation を返す。

- [ ] **Step 1: arm64 マニフェスト digest を実測で確かめる**

```bash
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:getpaseo/paseo:pull&service=ghcr.io" \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['token'])")
curl -s -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.oci.image.index.v1+json" \
  "https://ghcr.io/v2/getpaseo/paseo/manifests/0.9.1" \
  | python3 -c "
import json,sys
for m in json.load(sys.stdin)['manifests']:
    p = m['platform']
    if p['architecture'] == 'arm64' and p['os'] == 'linux':
        print(m['digest'])"
```

期待: `sha256:ee6af9593253ec745a40e745b79dfdf0138bcb7882da86d4b12be1eb78638667`

- [ ] **Step 2: サイドカーを hash 未確定の状態で書く**

`dot_config/home-manager/packages/paseo-image.json`:

```json
{
  "version": "0.9.1",
  "imageDigest": "sha256:ee6af9593253ec745a40e745b79dfdf0138bcb7882da86d4b12be1eb78638667",
  "hash": "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
}
```

`hash` は意図的に誤った値。次の手順で nix が正しい値を教えてくれる。

- [ ] **Step 3: pullImage だけの derivation を書く**

`dot_config/home-manager/packages/paseo-image.nix`:

```nix
{ lib
, dockerTools
}:

let
  spec = builtins.fromJSON (builtins.readFile ./paseo-image.json);
in
dockerTools.pullImage {
  imageName = "ghcr.io/getpaseo/paseo";
  imageDigest = spec.imageDigest;
  hash = spec.hash;
  finalImageName = "paseo";
  finalImageTag = spec.version;
  os = "linux";
  arch = "arm64";
}
```

pin されている nixpkgs の `pullImage` は `lib.fetchers.withNormalizedHash` で包まれており、
`hash = "sha256-..."` 形式を受け付ける（`sha256 = ` ではない）。出力は
`outputHashMode = "flat"` の tar が 1 個。
```

- [ ] **Step 4: ビルドしてハッシュ不一致で失敗させ、正しい hash を得る**

```bash
cd ~/.dotfiles/dot_config/home-manager
nix build --impure --no-link --expr '
  let
    lock = builtins.fromJSON (builtins.readFile ./flake.lock);
    n = lock.nodes.nixpkgs_3.locked;
    pkgs = import (builtins.fetchTarball {
      url = "https://github.com/${n.owner}/${n.repo}/archive/${n.rev}.tar.gz";
    }) { system = "aarch64-linux"; };
  in pkgs.callPackage ./packages/paseo-image.nix { }'
```

期待: `hash mismatch` で失敗し、`got: sha256-...` が表示される。その値を控える。

- [ ] **Step 5: 正しい hash をサイドカーに書き、ビルドが通ることを確認する**

`paseo-image.json` の `hash` を Step 4 の `got:` の値に差し替え、Step 4 のコマンドを再実行する。

期待: ビルド成功。

- [ ] **Step 6: 取得したイメージが arm64 であることを確認する**

```bash
cd ~/.dotfiles/dot_config/home-manager
OUT=$(nix build --impure --no-link --print-out-paths --expr '
  let
    lock = builtins.fromJSON (builtins.readFile ./flake.lock);
    n = lock.nodes.nixpkgs_3.locked;
    pkgs = import (builtins.fetchTarball {
      url = "https://github.com/${n.owner}/${n.repo}/archive/${n.rev}.tar.gz";
    }) { system = "aarch64-linux"; };
  in pkgs.callPackage ./packages/paseo-image.nix { }')
echo "=== アーカイブの中身 ==="
tar -tf "$OUT"
echo "=== manifest.json ==="
tar -xOf "$OUT" manifest.json
```

期待: `manifest.json` が読め、レイヤのパスが列挙される。

このアーカイブ内のレイヤ配置（`<digest>/layer.tar` 形式か `blobs/sha256/<digest>` 形式か）は
skopeo のバージョンによって変わるため、**ここで観察した実際のパス形式を控える**。Task 2 の
`unpackPhase` はその形式に合わせて書く。

あわせて、取得したイメージが arm64 であることを確認する（Review Focus 1 点目の検証）。
最大のレイヤを 1 つ展開し、ネイティブアドオンの ELF ヘッダを見る。

```bash
WORK=$(mktemp -d); tar -xf "$OUT" -C "$WORK"
BIG=$(find "$WORK" -name '*.tar' -o -path '*blobs*' -type f | xargs -r ls -S 2>/dev/null | head -1)
tar -xf "$BIG" -C "$WORK" \
  usr/local/lib/node_modules/@getpaseo/server/node_modules/node-pty/prebuilds/linux-arm64/pty.node 2>/dev/null
file "$WORK/usr/local/lib/node_modules/@getpaseo/server/node_modules/node-pty/prebuilds/linux-arm64/pty.node"
```

期待: `ELF 64-bit LSB shared object, ARM aarch64`。`x86-64` と出た場合はインデックス digest を
掴んでいるので Step 1 に戻る。

- [ ] **Step 7: コミット**

```bash
cd ~/.dotfiles
git add dot_config/home-manager/packages/paseo-image.json dot_config/home-manager/packages/paseo-image.nix
git -c commit.gpgsign=false commit -m "feat(paseo): 公式 arm64 イメージを pullImage で取得する

サイドカー paseo-image.json に version / imageDigest / hash を固定する。

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: レイヤ展開と node ラップ

**Files:**
- Modify: `dot_config/home-manager/packages/paseo-image.nix`

**Interfaces:**
- Consumes: Task 1 の `paseo-image.json`（`version`, `imageDigest`, `hash`）
- Produces: derivation の出力に `bin/paseo` が存在し、`paseo --version` が `paseo-image.json` の `version` を返す。`modules/paseo.nix` はこの `bin/paseo` に依存する。

- [ ] **Step 1: pullImage を内部に持つ stdenv.mkDerivation に書き換える**

`dot_config/home-manager/packages/paseo-image.nix` を全面的に差し替える:

```nix
{ lib
, stdenv
, dockerTools
, nodejs_22
, makeWrapper
, jq
}:

let
  spec = builtins.fromJSON (builtins.readFile ./paseo-image.json);

  image = dockerTools.pullImage {
    imageName = "ghcr.io/getpaseo/paseo";
    imageDigest = spec.imageDigest;
    hash = spec.hash;
    finalImageName = "paseo";
    finalImageTag = spec.version;
    os = "linux";
    arch = "arm64";
  };
in
stdenv.mkDerivation {
  pname = "paseo";
  version = spec.version;

  src = image;

  # pullImage の出力はイメージ全体の tar。manifest.json が列挙する順に
  # レイヤを重ねて最終的なファイルシステムを再構成する。レイヤのパス形式は
  # skopeo のバージョンで変わるため、manifest.json の Layers を正として読む。
  nativeBuildInputs = [ makeWrapper jq ];

  unpackPhase = ''
    runHook preUnpack

    mkdir -p image rootfs
    tar -xf "$src" -C image

    for layer in $(jq -r '.[0].Layers[]' image/manifest.json); do
      tar -xf "image/$layer" -C rootfs \
        --exclude='dev/*' --exclude='proc/*' --exclude='sys/*' \
        --no-same-owner --no-same-permissions
    done

    test -d rootfs/usr/local/lib/node_modules/@getpaseo/cli \
      || { echo "paseo の node_modules が見つからない"; exit 1; }

    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp -r rootfs/usr/local/lib/node_modules "$out/lib/node_modules"

    # イメージ内の bin/paseo は相対 symlink。実体を直接ラップする。
    mkdir -p "$out/bin"
    makeWrapper ${nodejs_22}/bin/node "$out/bin/paseo" \
      --add-flags "--disable-warning=DEP0040" \
      --add-flags "$out/lib/node_modules/@getpaseo/cli/dist/index.js" \
      --prefix PATH : ${lib.makeBinPath [ nodejs_22 ]}

    runHook postInstall
  '';

  meta = with lib; {
    description = "Paseo daemon and CLI, repackaged from the upstream arm64 container image";
    homepage = "https://github.com/getpaseo/paseo";
    platforms = [ "aarch64-linux" ];
    mainProgram = "paseo";
  };
}
```

- [ ] **Step 2: ビルドして bin/paseo ができることを確認する**

```bash
cd ~/.dotfiles/dot_config/home-manager
OUT=$(nix build --impure --no-link --print-out-paths --expr '
  let
    lock = builtins.fromJSON (builtins.readFile ./flake.lock);
    n = lock.nodes.nixpkgs_3.locked;
    pkgs = import (builtins.fetchTarball {
      url = "https://github.com/${n.owner}/${n.repo}/archive/${n.rev}.tar.gz";
    }) { system = "aarch64-linux"; };
  in pkgs.callPackage ./packages/paseo-image.nix { }')
echo "$OUT"
test -x "$OUT/bin/paseo" && echo "bin/paseo あり"
```

期待: ビルド成功、`bin/paseo あり`。

- [ ] **Step 3: PATH を空にして paseo --version が動くことを確認する**

```bash
env -i "$OUT/bin/paseo" --version
```

期待: `0.9.1` を含む出力。PATH に依存せず node を引けていること（Review Focus 4 点目の検証）。

- [ ] **Step 4: コミット**

```bash
cd ~/.dotfiles
git add dot_config/home-manager/packages/paseo-image.nix
git -c commit.gpgsign=false commit -m "feat(paseo): イメージを展開し nodejs_22 でラップする

bin/paseo は相対 symlink のため実体を makeWrapper で包み、PATH に
依存せず node を引けるようにする。

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: ネイティブアドオンの patchelf

**Files:**
- Modify: `dot_config/home-manager/packages/paseo-image.nix`

**Interfaces:**
- Consumes: Task 2 の derivation
- Produces: 出力内の `linux-arm64` 向け `.node` が nix の動的リンカで解決可能になる。

ネイティブアドオンは Debian でリンクされており、必要な共有ライブラリは実測で次のとおり。

| アドオン | NEEDED |
|---|---|
| `node-pty/prebuilds/linux-arm64/pty.node` | libutil.so.1, libstdc++.so.6, libgcc_s.so.1, libpthread.so.0, libc.so.6 |
| `sherpa-onnx-linux-arm64/sherpa-onnx.node` | 上記に加え libsherpa-onnx-c-api.so, libonnxruntime.so |

`libsherpa-onnx-c-api.so` と `libonnxruntime.so` は `sherpa-onnx-linux-arm64/` に同梱されているため、autoPatchelf が出力内を走査して解決する。

- [ ] **Step 1: autoPatchelfHook を足す**

`paseo-image.nix` の引数と `nativeBuildInputs` / `buildInputs` を変更する:

```nix
{ lib
, stdenv
, dockerTools
, nodejs_22
, makeWrapper
, jq
, autoPatchelfHook
, libuv
}:
```

```nix
  nativeBuildInputs = [ makeWrapper jq autoPatchelfHook ];

  buildInputs = [
    stdenv.cc.cc.lib
    libuv
  ];

  # 他プラットフォーム向けの prebuilds（darwin / win32 / linux-x64）は
  # 解決できなくて当然なので patchelf の対象から外す。
  autoPatchelfIgnoreMissingDeps = true;
```

- [ ] **Step 2: ビルドして linux-arm64 の pty.node が解決済みか確認する**

```bash
cd ~/.dotfiles/dot_config/home-manager
OUT=$(nix build --impure --no-link --print-out-paths --expr '
  let
    lock = builtins.fromJSON (builtins.readFile ./flake.lock);
    n = lock.nodes.nixpkgs_3.locked;
    pkgs = import (builtins.fetchTarball {
      url = "https://github.com/${n.owner}/${n.repo}/archive/${n.rev}.tar.gz";
    }) { system = "aarch64-linux"; };
  in pkgs.callPackage ./packages/paseo-image.nix { }')
PTY=$(find "$OUT" -path '*prebuilds/linux-arm64/pty.node' | head -1)
echo "$PTY"
ldd "$PTY"
```

期待: `not found` が 1 つも無いこと。

- [ ] **Step 3: sherpa-onnx.node の同梱 .so が解決されていることを確認する**

```bash
SH=$(find "$OUT" -name 'sherpa-onnx.node' -path '*linux-arm64*' | head -1)
ldd "$SH" | grep -E "sherpa|onnxruntime"
```

期待: `libsherpa-onnx-c-api.so` と `libonnxruntime.so` が `not found` ではなく、出力内のパスに解決されていること（Review Focus 2 点目の検証）。

- [ ] **Step 4: paseo が実際に起動しデーモンに到達できることを確認する**

```bash
export PASEO_HOME="$(mktemp -d)"
export PASEO_LISTEN=127.0.0.1:6799
"$OUT/bin/paseo" daemon status --json || echo "デーモン未起動（想定内）"
```

期待: コマンドが node のロードエラーを出さずに実行され、JSON か「未起動」の旨を返すこと。ネイティブアドオンのロードに失敗する場合はここで例外が出る。

Step 2〜4 のいずれかが通らない場合の退避策（spec の「既知のリスク」に対応）:

イメージ内の node（22.23.2）を nixpkgs の `nodejs_22` の代わりに使う。`installPhase` で
`rootfs/usr/local/bin/node` も出力へコピーし、`makeWrapper` の対象をそちらに変える。
この node も Debian ビルドなので `autoPatchelfHook` の対象に含まれる。
nixpkgs 側の node とのバージョン差に起因する問題はこれで消える。

退避策に切り替えた場合は、その旨を spec の「既知のリスク」節に追記してから次のタスクへ進む。

- [ ] **Step 5: コミット**

```bash
cd ~/.dotfiles
git add dot_config/home-manager/packages/paseo-image.nix
git -c commit.gpgsign=false commit -m "feat(paseo): ネイティブアドオンを autoPatchelf で適合させる

Debian ビルドの prebuilds を nix の動的リンカに合わせる。他プラット
フォーム向け prebuilds は解決対象から外す。

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: modules/paseo.nix の分岐

**Files:**
- Modify: `dot_config/home-manager/modules/paseo.nix`

**Interfaces:**
- Consumes: Task 3 完成後の `packages/paseo-image.nix`
- Produces: `modules/paseo.nix` が aarch64-linux でのみ自作パッケージを使う。他は従来の `paseo` 引数（flake input）を使う。

現在の `modules/paseo.nix` は `paseo` を 2 箇所で参照している。`home.packages = [ paseo ];` と、`ExecStart` の `exec ${paseo}/bin/paseo start --foreground`。両方を差し替える。

- [ ] **Step 1: let で paseoPkg を束縛し、2 箇所を差し替える**

関数本体の先頭を次のように変える:

```nix
{ config, pkgs, lib, paseo, ... }:
let
  # aarch64-linux（yomogi）ではソースビルドが 30〜60 分・RSS 3.7GB かかるため、
  # 上流が配布する arm64 コンテナイメージから組んだパッケージを使う。
  # x86_64-linux（hizake / ume）と aarch64-darwin（yuri）はビルドが問題に
  # ならないので、従来どおり flake input をそのまま使う。
  paseoPkg =
    if pkgs.stdenv.hostPlatform.system == "aarch64-linux"
    then pkgs.callPackage ../packages/paseo-image.nix { }
    else paseo;
in
{
  home.packages = [ paseoPkg ];
```

`ExecStart` の該当行を次に変える:

```nix
        exec ${paseoPkg}/bin/paseo start --foreground
```

他の記述（systemd ユニット定義、`Environment` の PATH、`PASEO_PRIMARY_LAN_IP` の解決）は変更しない。

- [ ] **Step 2: aarch64-linux で自作パッケージが選ばれることを確認する**

```bash
cd ~/.dotfiles/dot_config/home-manager
nix eval --raw .#homeConfigurations.yomogi.config.home.path 2>/dev/null \
  || nix eval --impure --raw --expr '
      (builtins.getFlake (toString ./.)).homeConfigurations.yomogi.config.home.path'
```

期待: 評価が通る。エラーにならないこと。

- [ ] **Step 3: x86_64-linux で従来の flake input が選ばれることを確認する**

```bash
cd ~/.dotfiles/dot_config/home-manager
nix eval --impure --raw --expr '
  (builtins.getFlake (toString ./.)).homeConfigurations.hizake.config.home.path'
```

期待: 評価が通る。arm64 イメージを引こうとして失敗しないこと（Review Focus 5 点目の検証）。

- [ ] **Step 4: aarch64-darwin でも評価が通ることを確認する**

```bash
cd ~/.dotfiles/dot_config/home-manager
nix eval --impure --raw --expr '
  (builtins.getFlake (toString ./.)).homeConfigurations.yuri.config.home.path'
```

期待: 評価が通る。darwin で Linux イメージを引こうとしないこと。

- [ ] **Step 5: コミット**

```bash
cd ~/.dotfiles
git add dot_config/home-manager/modules/paseo.nix
git -c commit.gpgsign=false commit -m "feat(paseo): aarch64-linux だけイメージ由来パッケージを使う

hizake / ume / yuri は従来どおり flake input のまま。flake.nix は変更しない。

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: 更新スクリプト

**Files:**
- Create: `dot_config/home-manager/packages/update-paseo-image.sh`

**Interfaces:**
- Consumes: `packages/paseo-image.json` のキー（`version`, `imageDigest`, `hash`）
- Produces: 同ファイルを書き換える実行可能スクリプト。引数なしで最新安定版へ、引数 1 つでそのバージョンへ更新する。

- [ ] **Step 1: スクリプトを書く**

`dot_config/home-manager/packages/update-paseo-image.sh`:

```bash
#!/usr/bin/env bash
# paseo-image.json を最新の安定版へ更新する。
# 引数を与えるとそのバージョン（例: 0.9.1）に固定する。
set -euo pipefail

IMAGE=ghcr.io/getpaseo/paseo
REPO=getpaseo/paseo
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIDECAR="$HERE/paseo-image.json"

token() {
  curl -sf "https://ghcr.io/token?scope=repository:${REPO}:pull&service=ghcr.io" \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])'
}

TOKEN="$(token)"

if [ $# -ge 1 ]; then
  VERSION="$1"
else
  # latest、プレリリース、数字で始まらないタグを除外し、バージョン順の最後を採る。
  VERSION="$(curl -sf -H "Authorization: Bearer $TOKEN" \
    "https://ghcr.io/v2/${REPO}/tags/list" \
    | python3 -c '
import json, sys, re
tags = json.load(sys.stdin)["tags"]
stable = [
    t for t in tags
    if re.match(r"^[0-9]", t) and not re.search(r"-(beta|rc|alpha)", t)
]
stable.sort(key=lambda t: [int(x) for x in re.findall(r"[0-9]+", t)])
print(stable[-1])')"
fi

echo "対象バージョン: $VERSION"

DIGEST="$(curl -sf -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
  "https://ghcr.io/v2/${REPO}/manifests/${VERSION}" \
  | python3 -c '
import json, sys
for m in json.load(sys.stdin)["manifests"]:
    p = m["platform"]
    if p["architecture"] == "arm64" and p["os"] == "linux":
        print(m["digest"])
        break
else:
    sys.exit("linux/arm64 のマニフェストが見つからない")')"

echo "arm64 digest: $DIGEST"

HASH="$(nix store prefetch-file --json --unpack \
  "https://ghcr.io/v2/${REPO}/blobs/${DIGEST}" 2>/dev/null \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["hash"])' || true)"

if [ -z "$HASH" ]; then
  # ghcr は匿名 blob 取得を許さないため prefetch が使えない。
  # 誤ったハッシュで一度ビルドさせ、nix が報告する正しい値を拾う。
  echo "prefetch 不可。ビルドを走らせて正しいハッシュを取得する"
  FAKE="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
  python3 - "$SIDECAR" "$VERSION" "$DIGEST" "$FAKE" <<'PY'
import json, sys
path, version, digest, h = sys.argv[1:5]
json.dump({"version": version, "imageDigest": digest, "hash": h},
          open(path, "w"), indent=2, ensure_ascii=False)
open(path, "a").write("\n")
PY
  HASH="$(cd "$HERE/.." && nix build --impure --no-link --expr '
    let
      lock = builtins.fromJSON (builtins.readFile ./flake.lock);
      n = lock.nodes.nixpkgs_3.locked;
      pkgs = import (builtins.fetchTarball {
        url = "https://github.com/${n.owner}/${n.repo}/archive/${n.rev}.tar.gz";
      }) { system = "aarch64-linux"; };
    in pkgs.callPackage ./packages/paseo-image.nix { }' 2>&1 \
    | grep -oE 'got: +sha256-[A-Za-z0-9+/=]+' | head -1 | sed 's/got: *//')"
fi

if [ -z "$HASH" ]; then
  echo "ハッシュの取得に失敗した" >&2
  exit 1
fi

python3 - "$SIDECAR" "$VERSION" "$DIGEST" "$HASH" <<'PY'
import json, sys
path, version, digest, h = sys.argv[1:5]
json.dump({"version": version, "imageDigest": digest, "hash": h},
          open(path, "w"), indent=2, ensure_ascii=False)
open(path, "a").write("\n")
PY

echo "更新した:"
cat "$SIDECAR"
```

- [ ] **Step 2: 実行権を付ける**

```bash
chmod +x ~/.dotfiles/dot_config/home-manager/packages/update-paseo-image.sh
```

- [ ] **Step 3: 現行バージョンを明示指定して冪等性を確認する**

```bash
cd ~/.dotfiles/dot_config/home-manager
cp packages/paseo-image.json /tmp/sidecar-before.json
./packages/update-paseo-image.sh 0.9.1
diff <(python3 -c "import json;print(json.dumps(json.load(open('/tmp/sidecar-before.json')),sort_keys=True))") \
     <(python3 -c "import json;print(json.dumps(json.load(open('packages/paseo-image.json')),sort_keys=True))") \
  && echo "冪等: 内容が一致"
```

期待: `冪等: 内容が一致`。

- [ ] **Step 4: 引数なしで最新版が解決できることを確認する**

```bash
cd ~/.dotfiles/dot_config/home-manager
./packages/update-paseo-image.sh
git diff --stat packages/paseo-image.json
```

期待: 最新安定版のバージョンが表示される。2026-09-24 時点では 0.9.1 なので差分なし。より新しい版が出ていれば差分が出る。その場合は Task 2〜3 の検証コマンドを再実行して通ることを確認する。

- [ ] **Step 5: コミット**

```bash
cd ~/.dotfiles
git add dot_config/home-manager/packages/update-paseo-image.sh dot_config/home-manager/packages/paseo-image.json
git -c commit.gpgsign=false commit -m "feat(paseo): イメージ更新スクリプトを追加する

引数なしで最新安定版、引数ありでそのバージョンに固定する。
nix flake update paseo に相当する操作を 1 コマンドにまとめる。

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: yomogi での実機検証

**Files:**
- Modify: なし（検証のみ）

**Interfaces:**
- Consumes: Task 1〜5 のすべて

- [ ] **Step 1: chezmoi の差分が home-manager 配下に閉じていることを確認する**

```bash
cd ~/.dotfiles
chezmoi status | grep -E "home-manager"
chezmoi diff ~/.config/home-manager | head -40
```

期待: 追加した 3 ファイルと `modules/paseo.nix` の変更のみ。`.claude/settings.json` などの無関係な差分を巻き込まないこと。

- [ ] **Step 2: home-manager 配下だけをターゲットへ反映する**

```bash
cd ~/.dotfiles
chezmoi apply ~/.config/home-manager
diff -r ~/.config/home-manager ~/.dotfiles/dot_config/home-manager && echo "ソースとターゲット一致"
```

期待: `ソースとターゲット一致`。

- [ ] **Step 3: ディスクとメモリの余裕を確認する**

```bash
df -h / | tail -1
free -h | head -2
```

期待: ルートの使用率が 75% 未満であること。過去に 79% で microSD が応答停止した事例があるため、下回っていなければ中止して先に掃除する。

- [ ] **Step 4: hms を paseo から切り離して実行する**

```bash
systemd-run --user --unit=hms-paseo-image --collect \
  --setenv=PATH="$PATH" --setenv=HOME="$HOME" \
  "$HOME/.nix-profile/bin/home-manager" switch --flake "$HOME/.config/home-manager#yomogi"
```

完了待ちは次で行う:

```bash
until ! systemctl --user is-active --quiet hms-paseo-image.service; do sleep 5; done
journalctl --user -u hms-paseo-image.service --no-pager -n 40
```

期待: `npm ci` が走らないこと。ログに `building '/nix/store/...-paseo-...drv'` のソースビルドが現れず、イメージの取得のみで完了すること。

- [ ] **Step 5: バージョンとデーモンを確認する**

```bash
~/.nix-profile/bin/paseo --version
systemctl --user status paseo.service --no-pager | head -5
```

期待: `0.9.1`。paseo.service が `active`。

- [ ] **Step 6: 上流 CI と同じスモークテストを行う**

```bash
systemctl --user restart paseo.service
until systemctl --user is-active --quiet paseo.service; do sleep 1; done
~/.nix-profile/bin/paseo daemon status --json | python3 -c '
import json,sys
d = json.load(sys.stdin)
assert d.get("connectedDaemon") == "reachable", d
print("daemon reachable")'
```

期待: `daemon reachable`。

注意: このステップは paseo.service を再起動するため、paseo 経由の Claude セッションは落ちる。実行前にその旨を人間に伝える。

- [ ] **Step 7: 新モデルが出ることを確認する**

paseo の `list_models`（MCP ツール、または Web UI のモデル選択）で次の 2 つが現れることを確認する。

- `claude-opus-5-5`（Opus 5.5）
- `claude-fable-5-1`（Fable 5.1）

期待: 両方が一覧に出る。これが当初の動機の達成条件。

- [ ] **Step 8: PR を出す**

```bash
cd ~/.dotfiles
git push -u origin feat/paseo-image-package
```

PR 本文には次を含める。

- 目的（yomogi のビルド 30〜60 分の廃止と、新モデルが出ない問題の解消）
- 対象が aarch64-linux のみで、hizake / ume / yuri と `flake.nix` は無変更であること
- 更新経路が 2 本になり、yomogi だけバージョンがずれうること
- 検証結果（ビルドが走らないこと、`paseo --version`、daemon reachable、新モデル 2 つの確認）
