{ config, pkgs, lib, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "claude-code" ];

  home = {
    username = "ekuinox";
    homeDirectory =
      if pkgs.stdenv.isDarwin then "/Users/ekuinox" else "/home/ekuinox";
    stateVersion = "26.05";
    packages = [ pkgs.claude-code ];
    sessionVariables = { };
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
        # 例: ll = "ls -alF";
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

    starship = {
      enable = true;
      enableBashIntegration = true;
      settings = {
        # OS 名をプロンプト先頭に表示する（$all は os 以外の全モジュール）
        format = "$os$all";
        os = {
          disabled = false;
          # nerd フォント不要な絵文字で短く表示する（WSL でも追加フォント不要）
          symbols = {
            Ubuntu = "🐧 ";
            Debian = "🐧 ";
            Arch = "🐧 ";
            Fedora = "🐧 ";
            Linux = "🐧 ";
            Macos = "🍎 ";
            Windows = "🪟 ";
            Unknown = "❓ ";
          };
        };
      };
    };
  };
}
