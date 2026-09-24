#!/usr/bin/env bash
# paseo-image.json を最新の安定版へ更新する。
# 引数を与えるとそのバージョン（例: 0.9.1）に固定する。
#
# ghcr は blob の匿名取得を許さず、また必要なハッシュは skopeo が生成する
# イメージ tar 全体に対するものなので、nix store prefetch-file は使えない。
# プレースホルダのハッシュで一度ビルドさせ、nix が報告する got: を採る。
set -euo pipefail

REPO=getpaseo/paseo
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HM="$(cd "$HERE/.." && pwd)"
SIDECAR="$HERE/paseo-image.json"
PLACEHOLDER="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

BACKUP="$(mktemp)"
cp "$SIDECAR" "$BACKUP"
restore() { cp "$BACKUP" "$SIDECAR"; rm -f "$BACKUP"; }
trap 'restore' ERR

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
        n = lock.nodes.nixpkgs_3.locked;
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

CURRENT_DIGEST="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["imageDigest"])' "$SIDECAR")"
CURRENT_VERSION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$SIDECAR")"
if [ "$DIGEST" = "$CURRENT_DIGEST" ] && [ "$VERSION" = "$CURRENT_VERSION" ]; then
  echo "既に最新。変更なし。"
  rm -f "$BACKUP"
  trap - ERR
  exit 0
fi

echo "ハッシュを取得するため、プレースホルダで一度ビルドする"
write_sidecar "$VERSION" "$DIGEST" "$PLACEHOLDER"
OUTPUT="$(build || true)"
HASH="$(printf '%s\n' "$OUTPUT" | grep -oE 'got: +sha256-[A-Za-z0-9+/=]+' | head -1 | sed 's/got: *//')"

if [ -z "$HASH" ]; then
  echo "ハッシュの取得に失敗した。ビルド出力:" >&2
  printf '%s\n' "$OUTPUT" | tail -20 >&2
  restore
  trap - ERR
  exit 1
fi

write_sidecar "$VERSION" "$DIGEST" "$HASH"
echo "ビルドを検証する"
build > /dev/null

rm -f "$BACKUP"
trap - ERR
echo "更新した:"
cat "$SIDECAR"
