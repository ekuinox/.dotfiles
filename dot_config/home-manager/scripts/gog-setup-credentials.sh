# gog-setup-credentials の本体。
# home.nix の pkgs.writeShellApplication が text として読み込む（builtins.readFile）。
# シバンと set -o errexit/nounset/pipefail、runtimeInputs の PATH は
# writeShellApplication 側で付与されるため、ここには書かない。
#
# Proton Pass の添付（gog の OAuth クライアント資格情報）を gog の keyring へ
# 橋渡しする一度きりのセットアップ。fzf で vault -> item -> attachment と絞り込む。

# pass-cli ログイン確認（vault/item 取得・download に必要）
if ! pass-cli test >/dev/null 2>&1; then
  echo "pass-cli が未ログインです。先に 'pass-cli login' を実行してください。" >&2
  exit 1
fi

# fzf で vault -> item -> attachment と絞り込む
vault_obj="$(pass-cli vault list --output json \
  | jq -r '.vaults[] | "\(.name)\t\(tojson)"' \
  | fzf --delimiter='\t' --with-nth=1 --prompt='Vault> ' | cut -f2- || true)"
[ -n "$vault_obj" ] || { echo "vault が選択されませんでした。" >&2; exit 1; }
SHARE_ID="$(printf '%s' "$vault_obj" | jq -r '.share_id // .shareId // .id')"

item_obj="$(pass-cli item list --share-id "$SHARE_ID" --output json \
  | jq -r '.items[] | "\(.title)\t\(tojson)"' \
  | fzf --delimiter='\t' --with-nth=1 --prompt='Item> ' | cut -f2- || true)"
[ -n "$item_obj" ] || { echo "item が選択されませんでした。" >&2; exit 1; }
ITEM_ID="$(printf '%s' "$item_obj" | jq -r '.id')"

view="$(pass-cli item view --share-id "$SHARE_ID" --item-id "$ITEM_ID" --output json)"
att_obj="$(printf '%s' "$view" \
  | jq -r '(.attachments // [])[] | "\(.name // .file_name // .fileName // .id)\t\(tojson)"' \
  | fzf --delimiter='\t' --with-nth=1 --prompt='Attachment> ' | cut -f2- || true)"
if [ -z "$att_obj" ]; then
  echo "attachment が選択されませんでした。.attachments の構造を確認してください:" >&2
  printf '%s' "$view" | jq -c '.attachments' >&2
  exit 1
fi
ATTACHMENT_ID="$(printf '%s' "$att_obj" | jq -r '.attachment_id // .id // .attachmentId')"

# 短命な一時ファイル（tmpfs 優先）へ取得し、登録後に確実に消す
tmpdir="${XDG_RUNTIME_DIR:-/tmp}"
tmp="$(mktemp "$tmpdir/gog-cred.XXXXXX")"
trap 'shred -u "$tmp" 2>/dev/null || rm -f "$tmp"' EXIT

pass-cli item attachment download \
  --share-id "$SHARE_ID" --item-id "$ITEM_ID" --attachment-id "$ATTACHMENT_ID" \
  --output "$tmp"

gog auth credentials set "$tmp"

echo "OK: OAuth クライアント資格情報を keyring に登録しました。"
echo "次に: gog auth add <email>  でアカウントを認可してください。"
