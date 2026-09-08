# yuri: MacBook Air (Apple Silicon, aarch64-darwin) 固有のホスト設定。
# macOS の既定の対話シェルは zsh のため、common.nix の programs.* が用意する
# ツール統合（starship / zoxide / fzf / mise / direnv / yazi）と home.shellAliases は
# programs.zsh を有効にして初めて対話シェルへ入る。nushell も同じ理由で
# programs.nushell を有効にする。
{ config, lib, host, ... }:
let
  # rustup 管理の cargo / rustc は nix の外にあるため、PATH は home-manager で通す。
  # 従来は ~/.zshenv の `. "$HOME/.cargo/env"` が担っていた。bash / zsh は
  # home.sessionPath、nushell は programs.nushell.extraEnv と経路が分かれるため、
  # 片方だけ足して片方を忘れないよう値はここで一度だけ持つ。
  cargoBin = "${config.home.homeDirectory}/.cargo/bin";
in
{
  home.sessionPath = [ cargoBin ];

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

  # 手で起動する対話シェル（zsh からの自動 exec はしない）。enable が本体も入れる。
  # home-manager 管理外に置くと、starship 等の初期化ファイルが生成時のパスを
  # 絶対パスで抱えたまま取り残される（Homebrew 版 starship を外したときに壊れた）。
  # 管理下に置けば switch のたびに再生成され、統合の対象も zsh と揃う。
  programs.nushell = {
    enable = true;
    settings = {
      show_banner = false;
      edit_mode = "emacs";
    };
    # home.shellAliases は home-manager が nushell にも渡す。ただし nushell は
    # # をコメント開始として扱うため、flake 参照を含む hms はそのままだと
    # # 以降が切り捨てられ、config.nu 全体が構文エラーになる。~ はクォート内で
    # 展開されないため、絶対パスにしたうえでクォートしたものへ差し替える。
    shellAliases.hms = lib.mkForce
      ''home-manager switch --flake "${config.home.homeDirectory}/.config/home-manager#${host}"'';
    # env.nu。home.sessionPath は nushell に届かないため、同じ PATH をここでも通す。
    extraEnv = ''
      $env.PATH = ($env.PATH | prepend "${cargoBin}" | uniq)
    '';
  };
}
