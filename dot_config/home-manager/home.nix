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

  # Notion CLI (ntn) は nixpkgs に無く、Rust 製のビルド済みバイナリ配布のため
  # tarball を fetchurl で取得して bin に置く。Linux は static-pie のため patchelf 不要。
  ntn = let
    version = "0.17.0";
    sources = {
      x86_64-linux = {
        target = "x86_64-unknown-linux-musl";
        hash = "sha256-3wBdObguJkxgUePErSYB978w+u8hiweLygwmDWrYDjs=";
      };
      aarch64-linux = {
        target = "aarch64-unknown-linux-musl";
        hash = "sha256-dWVIH6ok2G5zWcN0ozywHMcmWhUIqEeluJuHdNfEG5k=";
      };
      aarch64-darwin = {
        target = "aarch64-apple-darwin";
        hash = "sha256-mNj88+traB1yKPINxmGppTJs7X96Laz2+f5vkKVMJkc=";
      };
      x86_64-darwin = {
        target = "x86_64-apple-darwin";
        hash = "sha256-cqUq0rb5dbKdCP7KLYIRxaNdUtohT6E/6FkYYL5PbQg=";
      };
    };
    plat = sources.${pkgs.stdenv.hostPlatform.system} or (throw
      "ntn: unsupported system ${pkgs.stdenv.hostPlatform.system}");
  in pkgs.stdenvNoCC.mkDerivation {
    pname = "ntn";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://ntn.dev/releases/v${version}/ntn-${plat.target}.tar.gz";
      inherit (plat) hash;
    };
    sourceRoot = "ntn-${plat.target}";
    installPhase = ''
      runHook preInstall
      install -Dm0755 ntn "$out/bin/ntn"
      runHook postInstall
    '';
    meta = {
      description = "Notion CLI";
      homepage = "https://developers.notion.com/cli/get-started/overview";
      mainProgram = "ntn";
      platforms = builtins.attrNames sources;
    };
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
