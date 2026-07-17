{
  description = "Home Manager configuration of ekuinox";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Paseo（リモートからエージェントを操作する CLI/サーバー）。flake が
    # 各 system 向け package を公開しているのでそれを home.packages に入れる。
    # nixpkgs は paseo 側のピンに従わせる（follows で上書きしない）。
    paseo.url = "github:getpaseo/paseo";
    # herdr（AI コーディングエージェント用ターミナルワークスペース管理）。paseo と
    # 同じく flake が各 system 向け package を公開しているので home.packages に入れる。
    # nixpkgs は herdr 側のピンに従わせる（follows で上書きしない）。wsl 限定のため
    # home.nix 側で host == "wsl" のときだけ参照する（pi では遅延評価でビルドされない）。
    herdr.url = "github:ogulcancelik/herdr/v0.7.4";
  };

  outputs = { nixpkgs, home-manager, paseo, herdr, ... }:
    let
      # ホスト名 -> system。home.nix は全ホスト共通で、ホスト間の差分は
      # system と、home.nix に渡すホスト名（hms エイリアスの flake 参照先）だけ。
      hosts = {
        wsl = "x86_64-linux";
        pi = "aarch64-linux"; # Raspberry Pi (Ubuntu, aarch64)
        # 将来: mac = "aarch64-darwin";
      };
      mkHome = host: system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ ./home.nix ];
          extraSpecialArgs = {
            inherit host;
            paseo = paseo.packages.${system}.default;
            herdr = herdr.packages.${system}.default;
          };
        };
    in {
      homeConfigurations = nixpkgs.lib.mapAttrs mkHome hosts;
    };
}
