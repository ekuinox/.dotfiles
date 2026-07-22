# WSL (x86_64-linux) 固有のホスト設定。
# herdr（AI コーディングエージェント用ターミナルワークスペース管理）は wsl のみで使う。
# パッケージ・設定ともこのモジュールが wsl でしか読まれないため host 判定は不要。
{ pkgs, herdr, ... }:
{
  # herdr 本体（flake input が公開する package）を PATH に入れる。
  # common.nix の home.packages リストへマージされる。
  home.packages = [ herdr ];

  # herdr の設定。プレーンな TOML なので nix で直接生成する。
  home.file.".config/herdr/config.toml".text = ''
    onboarding = false

    [terminal]
    default_shell = "bash"
    shell_mode = "auto"
    new_cwd = "follow"

    [keys]
    prefix = "ctrl+b"
    next_tab = "prefix+n"
    previous_tab = "prefix+p"

    [theme]
    name = "catppuccin"

    [ui.toast]
    delivery = "herdr"
  '';
}
