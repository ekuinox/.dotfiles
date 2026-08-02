# git-setup-signing の本体。
# packages/git-setup-signing.nix の writeShellApplication が text として読み込む
# （builtins.readFile）。シバンと set -o errexit/nounset/pipefail、runtimeInputs の
# PATH は writeShellApplication 側で付与されるため、ここには書かない。
#
# ホストごとに 1 回実行する。SSH 署名に使う鍵を用意し、allowed_signers への登録状況を
# 確認し、GitHub へ signing key として登録し、実際に署名と検証が通るかまで確かめる。
# 秘密鍵はこのホストから出さない。何度実行してもよい。

KEY="$HOME/.ssh/id_ed25519"
PUBKEY="$KEY.pub"
ALLOWED_SIGNERS="$HOME/.config/git/allowed_signers"

cleanup_paths=()
cleanup() {
  if [ ${#cleanup_paths[@]} -gt 0 ]; then
    rm -rf "${cleanup_paths[@]}"
  fi
}
trap cleanup EXIT

# 1. 鍵を用意する。既にあれば流用する（認証用と署名用を兼ねる）。
if [ ! -f "$PUBKEY" ]; then
  echo "$PUBKEY が見つかりません。ed25519 鍵を生成します。"
  echo "パスフレーズを設定すると、署名のたびに入力または ssh-agent が必要になります。"
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t ed25519 -f "$KEY" -C "$(whoami)@$(uname -n)"
fi
echo "署名鍵: $(ssh-keygen -l -f "$PUBKEY")"

email="$(git config --get user.email || true)"
if [ -z "$email" ]; then
  echo "git の user.email が未設定です。先に設定してください。" >&2
  exit 1
fi

# 2. allowed_signers に自分の鍵が載っているか確認する。
#    このファイルは chezmoi が管理するため、ここでは書き換えず追加すべき行を示す。
#    鍵の本体（keytype と base64）だけを取り出して照合する。コメント欄は無視する。
keybody="$(cut -d' ' -f1,2 < "$PUBKEY")"
if [ ! -f "$ALLOWED_SIGNERS" ] || ! grep -qF "$keybody" "$ALLOWED_SIGNERS"; then
  echo "" >&2
  echo "この鍵が $ALLOWED_SIGNERS に未登録です。" >&2
  echo "chezmoi ソース (dot_config/git/allowed_signers) に次の行を追加し、" >&2
  echo "chezmoi apply したうえで再実行してください。" >&2
  echo "" >&2
  printf '# %s\n%s namespaces="git" %s\n' "$(uname -n)" "$email" "$(cat "$PUBKEY")"
  echo "" >&2
  exit 1
fi
echo "allowed_signers に登録済みです。"

# 3. GitHub へ signing key として登録する。認証用の鍵として登録済みでも、署名用は
#    別枠のため改めて登録が必要。ここが失敗しても署名自体は成立するので処理は止めない。
registered=0
if gh ssh-key list 2>/dev/null | grep -qF "$keybody"; then
  echo "GitHub に登録済みです。"
  registered=1
elif gh ssh-key add "$PUBKEY" --type signing --title "$(uname -n) (signing)" 2>/dev/null; then
  echo "GitHub に signing key として登録しました。"
  registered=1
else
  echo "" >&2
  echo "GitHub への自動登録ができませんでした（gh 未ログイン、または" >&2
  echo "トークンに admin:ssh_signing_key スコープが無い可能性があります）。" >&2
  echo "次のどちらかで登録してください:" >&2
  echo "  1) gh auth refresh -s admin:ssh_signing_key を実行し、このコマンドを再実行する" >&2
  echo "  2) https://github.com/settings/ssh/new で Key type に Signing Key を選び、" >&2
  echo "     下記の公開鍵を貼り付ける" >&2
  echo "" >&2
  cat "$PUBKEY"
  echo "" >&2
fi

# 4. 使い捨てリポジトリで署名と検証の両方を確かめる。~/.gitconfig 側の設定が未適用でも
#    確かめられるよう、署名まわりの設定はすべて明示する。
workdir="$(mktemp -d)"
cleanup_paths+=("$workdir")
git -C "$workdir" init -q -b main
git -C "$workdir" config gpg.format ssh
git -C "$workdir" config user.signingkey "$PUBKEY"
git -C "$workdir" config gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"
if ! git -C "$workdir" commit -q --allow-empty -m "signing test" -S; then
  echo "署名コミットに失敗しました。" >&2
  exit 1
fi
if ! git -C "$workdir" verify-commit HEAD; then
  echo "署名の検証に失敗しました。allowed_signers の principal が" >&2
  echo "user.email ($email) と一致しているか確認してください。" >&2
  exit 1
fi

echo ""
echo "OK: 署名コミットの生成と検証に成功しました。"
if [ "$registered" -eq 1 ]; then
  echo "以後のコミットは GitHub 上で Verified になります。"
fi
