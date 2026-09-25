#!/usr/bin/env bash
# paseo-image.json を最新の安定版へ更新する。
# 引数を与えるとそのバージョン（例: 0.9.1）に固定する。
#
# ghcr は blob の匿名取得を許さず、また必要なハッシュは skopeo が生成する
# イメージ tar 全体に対するものなので、nix store prefetch-file は使えない。
# プレースホルダのハッシュで一度ビルドさせ、nix が報告する got: を採る。
# -E: ERR trap を関数内の失敗でも発火させる（これが無いと build() 内の失敗で
# 後片付けが走らず、サイドカーが壊れたまま残る）。
set -Eeuo pipefail

REPO=getpaseo/paseo
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HM="$(cd "$HERE/.." && pwd)"
SIDECAR="$HERE/paseo-image.json"
PLACEHOLDER="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

BACKUP="$(mktemp)"
cp "$SIDECAR" "$BACKUP"
SUCCESS=0
cleanup() {
  # 成功していなければサイドカーを元に戻す。EXIT も拾うので、Ctrl-C（長い
  # skopeo 取得の最中など）や予期しない終了でもプレースホルダを残さない。
  if [ "$SUCCESS" -ne 1 ] && [ -f "$BACKUP" ]; then
    cp "$BACKUP" "$SIDECAR"
    echo "サイドカーを元に戻した" >&2
  fi
  rm -f "$BACKUP"
}
trap cleanup EXIT INT TERM

write_sidecar() {
  python3 - "$SIDECAR" "$1" "$2" "$3" <<'PY'
import json, sys
path, version, digest, h = sys.argv[1:5]
with open(path, "w") as f:
    json.dump({"version": version, "imageDigest": digest, "hash": h},
              f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
}

build() {
  ( cd "$HM" && nix build --impure --no-link --print-out-paths --expr '
      let
        lock = builtins.fromJSON (builtins.readFile ./flake.lock);
        # root の nixpkgs が指す節を辿る。節名（nixpkgs_3 等）は入力の増減で
        # 自動採番が変わるため、ベタ書きすると別 input の nixpkgs を掴みうる。
        rootNixpkgs = lock.nodes.${lock.root}.inputs.nixpkgs;
        n = lock.nodes.${rootNixpkgs}.locked;
        pkgs = import (builtins.fetchTarball {
          url = "https://github.com/${n.owner}/${n.repo}/archive/${n.rev}.tar.gz";
        }) { system = "aarch64-linux"; };
      in pkgs.callPackage ./packages/paseo-image.nix { }' 2>&1 )
}

TOKEN="$(curl -sf "https://ghcr.io/token?scope=repository:${REPO}:pull&service=ghcr.io" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')"

if [ $# -ge 1 ]; then
  VERSION="$1"
else
  # latest、プレリリース、数字で始まらないタグを除外し、バージョン順の最後を採る。
  VERSION="$(curl -sf -H "Authorization: Bearer $TOKEN" \
    "https://ghcr.io/v2/${REPO}/tags/list" \
    | python3 -c '
import json, sys, re
tags = json.load(sys.stdin)["tags"]
stable = [t for t in tags
          if re.match(r"^[0-9]", t) and not re.search(r"-(beta|rc|alpha)", t)]
if not stable:
    sys.exit("安定版タグが見つからない")
stable.sort(key=lambda t: [int(x) for x in re.findall(r"[0-9]+", t)])
print(stable[-1])')"
fi
echo "対象バージョン: $VERSION"

MANIFEST="$(curl -sf -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
  "https://ghcr.io/v2/${REPO}/manifests/${VERSION}" || true)"
if [ -z "$MANIFEST" ]; then
  echo "タグ ${VERSION} のマニフェストを取得できない（バージョン名を確認）" >&2
  exit 1
fi

DIGEST="$(printf '%s' "$MANIFEST" \
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

CURRENT_DIGEST="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["imageDigest"])' "$SIDECAR")"
CURRENT_VERSION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$SIDECAR")"
CURRENT_HASH="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["hash"])' "$SIDECAR")"
# hash も見る。プレースホルダのまま残っている状態から再実行したときに
# 「既に最新」と言って自己修復しないのを防ぐ。
if [ "$DIGEST" = "$CURRENT_DIGEST" ] && [ "$VERSION" = "$CURRENT_VERSION" ] \
   && [ "$CURRENT_HASH" != "$PLACEHOLDER" ]; then
  echo "既に最新。変更なし。"
  SUCCESS=1
  exit 0
fi

echo "ハッシュを取得するため、プレースホルダで一度ビルドする"
write_sidecar "$VERSION" "$DIGEST" "$PLACEHOLDER"
OUTPUT="$(build || true)"
HASH="$(printf '%s\n' "$OUTPUT" | grep -oE 'got: +sha256-[A-Za-z0-9+/=]+' | head -1 | sed 's/got: *//')"

if [ -z "$HASH" ]; then
  echo "ハッシュの取得に失敗した。ビルド出力:" >&2
  printf '%s\n' "$OUTPUT" | tail -20 >&2
  exit 1
fi

write_sidecar "$VERSION" "$DIGEST" "$HASH"
echo "ビルドを検証する"
if ! VERIFY="$(build)"; then
  echo "検証ビルドが失敗した。出力:" >&2
  printf '%s\n' "$VERIFY" | tail -20 >&2
  exit 1
fi

SUCCESS=1
echo "更新した:"
cat "$SIDECAR"
