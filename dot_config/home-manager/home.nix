{ config, pkgs, lib, ... }:
let
  # nixpkgs に無い Go CLI を buildGoModule で自前ビルドする
  redmine-go = pkgs.buildGoModule {
    pname = "redmine-go";
    version = "0.2.0";
    src = pkgs.fetchFromGitHub {
      owner = "kqns91";
      repo = "redmine-go";
      rev = "v0.2.0";
      hash = "sha256-jrYo3ptqfHJk8r+05ndwBgg1UBJMcF4p0NNBoGjHcXM=";
    };
    vendorHash = "sha256-zFVdCFZK5uQAaIv3c8IMp/0B0sHOdV+xLjvjxZhEUto=";
    subPackages = [ "cmd/redmine" ];
  };

  # Proton Pass の添付（gog の OAuth クライアント資格情報）を gog の keyring へ
  # 橋渡しする一度きりのセットアップ。secret は repo にも /nix/store にも置かず、
  # 実行時に短命な一時ファイル経由で登録する（switch 時には行わない）。
  # 本体は別ファイル（scripts/gog-setup-credentials.sh）に置き readFile で読む。
  gog-setup-credentials = pkgs.writeShellApplication {
    name = "gog-setup-credentials";
    runtimeInputs = [ pkgs.proton-pass-cli pkgs.gogcli pkgs.jq pkgs.fzf pkgs.coreutils ];
    text = builtins.readFile ./scripts/gog-setup-credentials.sh;
  };
in
{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "claude-code" "proton-pass-cli" ];

  home = {
    username = "ekuinox";
    homeDirectory =
      if pkgs.stdenv.isDarwin then "/Users/ekuinox" else "/home/ekuinox";
    stateVersion = "26.05";
    packages = [
      pkgs.claude-code
      pkgs.chezmoi
      pkgs.gogcli
      pkgs.jq
      pkgs.nano
      pkgs.proton-pass-cli
      redmine-go
      gog-setup-credentials
    ];
    sessionVariables = { };

    # nano のシンタックスハイライト。scopatz/nanorc プリセット（118 言語）を読み込む
    file.".nanorc".text = ''
      include "${pkgs.nanorc}/share/*.nanorc"
      # nix は scopatz プリセットに無いため nano 同梱の公式定義を追加する
      include "${pkgs.nano}/share/nano/nix.nanorc"
    '';
  };

  programs = {
    home-manager.enable = true;

    bash = {
      enable = true;
      historyControl = [ "ignoredups" "ignorespace" ];
      historySize = 10000;
      historyFileSize = 20000;
      shellOptions = [ "histappend" "checkwinsize" ];
      shellAliases = {
        # home-manager switch（このマシンのホスト鍵は wsl）
        hms = "home-manager switch --flake ~/.config/home-manager#wsl";
      };
    };

    mise = {
      enable = true;
      enableBashIntegration = true;
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    zoxide = {
      enable = true;
      enableBashIntegration = true;
    };

    fzf = {
      enable = true;
      enableBashIntegration = true;
    };

    starship = {
      enable = true;
      enableBashIntegration = true;
      settings = {
        # OS 名をプロンプト先頭に表示する（$all は os 以外の全モジュール）
        format = "$os$all";
        os.disabled = false;
      };
    };
  };
}
