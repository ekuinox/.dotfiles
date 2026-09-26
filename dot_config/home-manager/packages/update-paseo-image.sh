#!/usr/bin/env bash
# paseo-image.json を最新の安定版へ更新する。
# 引数を与えるとそのバージョン（例: 0.9.1）に固定する。
# 対応する全アーキテクチャ（ARCHS）の digest と FOD ハッシュをまとめて書き換える。
#
# ghcr は blob の匿名取得を許さず、また必要なハッシュは skopeo が生成する
# イメージ tar 全体に対するものなので、nix store prefetch-file は使えない。
# プレースホルダのハッシュで一度ビルドさせ、nix が報告する got: を採る。
# 取得するのはイメージ tar（pullImage の出力）だけなので、実行するマシンの
# system に関係なく全アーキテクチャ分を得られる（hizake から arm64 分も取れる）。
# -E: ERR trap を関数内の失敗でも発火させる（これが無いと build() 内の失敗で
# 後片付けが走らず、サイドカーが壊れたまま残る）。
set -Eeuo pipefail

REPO=getpaseo/paseo
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HM="$(cd "$HERE/.." && pwd)"
SIDECAR="$HERE/paseo-image.json"
PLACEHOLDER="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
# nix の system 名と OCI のアーキテクチャ名の対応。paseo-image.nix の archs と揃える。
declare -A ARCHS=([aarch64-linux]=arm64 [x86_64-linux]=amd64)

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

# 引数: version、続けて system digest hash の 3 つ組をアーキテクチャの数だけ。
write_sidecar() {
  python3 - "$SIDECAR" "$@" <<'PY2'
import json, sys
path, version, *rest = sys.argv[1:]
images = {rest[i]: {"imageDigest": rest[i + 1], "hash": rest[i + 2]}
          for i in range(0, len(rest), 3)}
with open(path, "w") as f:
    json.dump({"version": version, "images": dict(sorted(images.items()))},
              f, indent=2, ensure_ascii=False)
    f.write("\n")
PY2
}

# 引数の attr（paseo-image.nix の derivation からの相対パス）をビルドする。
# 例: build 'imageFor "aarch64-linux"'、build '' はパッケージ本体。
build() {
  ( cd "$HM" && nix build --impure --no-link --print-out-paths --expr "
      let
        lock = builtins.fromJSON (builtins.readFile ./flake.lock);
        # root の nixpkgs が指す節を辿る。節名（nixpkgs_3 等）は入力の増減で
        # 自動採番が変わるため、ベタ書きすると別 input の nixpkgs を掴みうる。
        rootNixpkgs = lock.nodes.\${lock.root}.inputs.nixpkgs;
        n = lock.nodes.\${rootNixpkgs}.locked;
        pkgs = import (builtins.fetchTarball {
          url = \"https://github.com/\${n.owner}/\${n.repo}/archive/\${n.rev}.tar.gz\";
        }) { };
        pkg = pkgs.callPackage ./packages/paseo-image.nix { };
      in pkg${1:+.$1}" 2>&1 )
}

sidecar_get() {
  python3 -c 'import json,sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    d = d.get(k, {}) if isinstance(d, dict) else {}
print(d if isinstance(d, str) else "")' "$SIDECAR" "$@"
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

declare -A DIGESTS HASHES
UP_TO_DATE=1
[ "$VERSION" = "$(sidecar_get version)" ] || UP_TO_DATE=0
for SYS in "${!ARCHS[@]}"; do
  DIGESTS[$SYS]="$(printf '%s' "$MANIFEST" \
    | python3 -c '
import json, sys
arch = sys.argv[1]
for m in json.load(sys.stdin)["manifests"]:
    p = m["platform"]
    if p["architecture"] == arch and p["os"] == "linux":
        print(m["digest"])
        break
else:
    sys.exit(f"linux/{arch} のマニフェストが見つからない")' "${ARCHS[$SYS]}")"
  echo "$SYS (${ARCHS[$SYS]}) digest: ${DIGESTS[$SYS]}"
  # hash も見る。プレースホルダのまま残っている状態から再実行したときに
  # 「既に最新」と言って自己修復しないのを防ぐ。
  CURRENT_HASH="$(sidecar_get images "$SYS" hash)"
  if [ "${DIGESTS[$SYS]}" != "$(sidecar_get images "$SYS" imageDigest)" ] \
     || [ -z "$CURRENT_HASH" ] || [ "$CURRENT_HASH" = "$PLACEHOLDER" ]; then
    UP_TO_DATE=0
  fi
done

if [ "$UP_TO_DATE" -eq 1 ]; then
  echo "既に最新。変更なし。"
  SUCCESS=1
  exit 0
fi

sidecar_args() {
  local args=("$VERSION") sys
  for sys in "${!ARCHS[@]}"; do
    args+=("$sys" "${DIGESTS[$sys]}" "${HASHES[$sys]:-$PLACEHOLDER}")
  done
  write_sidecar "${args[@]}"
}

echo "ハッシュを取得するため、プレースホルダで一度ビルドする"
sidecar_args
for SYS in "${!ARCHS[@]}"; do
  OUTPUT="$(build "imageFor \"$SYS\"" || true)"
  HASH="$(printf '%s\n' "$OUTPUT" | grep -oE 'got: +sha256-[A-Za-z0-9+/=]+' | head -1 | sed 's/got: *//')"
  if [ -z "$HASH" ]; then
    echo "$SYS のハッシュの取得に失敗した。ビルド出力:" >&2
    printf '%s\n' "$OUTPUT" | tail -20 >&2
    exit 1
  fi
  echo "$SYS hash: $HASH"
  HASHES[$SYS]="$HASH"
  sidecar_args
done

# 手元の system 向けのパッケージ本体までビルドして、展開・autoPatchelf が通ることを
# 確かめる。他アーキテクチャはイメージ取得（ハッシュ一致）までしか検証できないので、
# 該当ホストの switch 後にデーモンの起動を確認すること。
echo "ビルドを検証する"
if ! VERIFY="$(build '')"; then
  echo "検証ビルドが失敗した。出力:" >&2
  printf '%s\n' "$VERIFY" | tail -20 >&2
  exit 1
fi

SUCCESS=1
echo "更新した:"
cat "$SIDECAR"
