# yuri: MacBook Air (Apple Silicon, aarch64-darwin) 固有のホスト設定。
# macOS の既定の対話シェルは zsh のため、common.nix の programs.* が用意する
# ツール統合（starship / zoxide / fzf / mise / direnv / yazi）と home.shellAliases は
# programs.zsh を有効にして初めて対話シェルへ入る。
{ config, pkgs, ... }:
{
  home.packages = [
    # 対話シェルとして手で起動する。zsh からの自動 exec はしない
    pkgs.nushell
  ];

  # rustup 管理の cargo / rustc は nix の外にあるため、PATH は home-manager で通す。
  # 従来は ~/.zshenv の `. "$HOME/.cargo/env"` が担っていた。
  home.sessionPath = [ "$HOME/.cargo/bin" ];

  programs.zsh = {
    enable = true;
    history = {
      # 既定は $XDG_DATA_HOME/zsh/zsh_history。既存の履歴を引き継ぐため従来の場所に固定する
      path = "${config.home.homeDirectory}/.zsh_history";
      ignoreDups = true;
      ignoreSpace = true;
      size = 10000;
      save = 20000;
    };
  };
}
