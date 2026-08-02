# ホストごとに 1 回実行する SSH 署名のセットアップ。鍵の生成やパスフレーズ入力を
# 伴いうる対話処理のため、home-manager switch 時の自動実行にはせず明示コマンドとして
# 提供する。秘密鍵は repo にも /nix/store にも置かず、このホストの ~/.ssh に留まる。
# 本体は別ファイル（../scripts/git-setup-signing.sh）に置き readFile で読む。
{ writeShellApplication, openssh, git, gh, coreutils, gnugrep }:

writeShellApplication {
  name = "git-setup-signing";
  runtimeInputs = [ openssh git gh coreutils gnugrep ];
  text = builtins.readFile ../scripts/git-setup-signing.sh;
}
