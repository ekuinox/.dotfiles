{ config, pkgs, lib, ... }:
let
  # nixpkgs に無い自前パッケージは packages/ 配下に 1 ファイルずつ分離し、
  # callPackage で nixpkgs の依存（stdenv/fetchurl 等）を自動注入して読み込む。
  redmine-go = pkgs.callPackage ./packages/redmine-go.nix { };
  ntn = pkgs.callPackage ./packages/ntn.nix { };
  gog-setup-credentials = pkgs.callPackage ./packages/gog-setup-credentials.nix { };
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
      pkgs.podman
      pkgs.podman-compose
      pkgs.proton-pass-cli
      pkgs.strace
      ntn
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

    # rootless podman 用の containers 設定。非 NixOS では /etc/containers を
    # 誰も用意しないため、ユーザー側 (~/.config/containers) を home-manager で管理する。
    # イメージ署名ポリシー。これが無いと "no policy.json file found" で起動できない
    file.".config/containers/policy.json".text = ''
      {
        "default": [{ "type": "insecureAcceptAnything" }]
      }
    '';
    # 短縮名 (hello-world 等) を docker.io から解決できるようにする
    file.".config/containers/registries.conf".text = ''
      unqualified-search-registries = ["docker.io"]
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
