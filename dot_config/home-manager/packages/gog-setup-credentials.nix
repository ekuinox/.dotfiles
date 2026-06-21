# Proton Pass の添付（gog の OAuth クライアント資格情報）を gog の keyring へ
# 橋渡しする一度きりのセットアップ。secret は repo にも /nix/store にも置かず、
# 実行時に短命な一時ファイル経由で登録する（switch 時には行わない）。
# 本体は別ファイル（../scripts/gog-setup-credentials.sh）に置き readFile で読む。
{ writeShellApplication, proton-pass-cli, gogcli, jq, fzf, coreutils }:

writeShellApplication {
  name = "gog-setup-credentials";
  runtimeInputs = [ proton-pass-cli gogcli jq fzf coreutils ];
  text = builtins.readFile ../scripts/gog-setup-credentials.sh;
}
