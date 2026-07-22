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
    # hosts/wsl.nix でのみ参照する（pi/yomogi では遅延評価でビルドされない）。
    herdr.url = "github:ogulcancelik/herdr/v0.7.4";
    # mube スマートロックの中継スタック（Caddy ヘッダ削ぎプロキシ + cloudflared）を
    # home-manager モジュールとして提供する。yomogi の modules でのみ import・有効化（hosts/yomogi.nix 参照）。
    mube.url = "github:ekuinox/mube";
  };

  outputs = { nixpkgs, home-manager, paseo, herdr, mube, ... }:
    let
      # ホスト名 -> { system, modules }。共通設定は common.nix、ホスト固有差分は
      # hosts/*.nix に置く。yomogi は pi.nix を継承（modules に含める）しつつ
      # 個体固有の door-lock 設定（yomogi.nix）と mube モジュールを足す。
      hosts = {
        wsl = {
          system = "x86_64-linux";
          modules = [ ./hosts/wsl.nix ];
        };
        # Raspberry Pi (Ubuntu, aarch64) の汎用ホスト
        pi = {
          system = "aarch64-linux";
          modules = [ ./hosts/pi.nix ];
        };
        # yomogi: 自宅 Pi の個体名。pi.nix を継承し、door-lock 中継役の設定を追加する。
        # mube.homeManagerModules.default は services.mube-door-lock オプションの提供元で、
        # yomogi だけが必要とするためここでのみ import する（wsl/pi はオプションを持たない）。
        yomogi = {
          system = "aarch64-linux";
          modules = [ ./hosts/pi.nix ./hosts/yomogi.nix mube.homeManagerModules.default ];
        };
        # 将来: mac = { system = "aarch64-darwin"; modules = [ ./hosts/mac.nix ]; };
      };
      mkHome = host: { system, modules }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ ./common.nix ] ++ modules;
          # host は hms エイリアスの flake 参照先。paseo/herdr は system 別 package。
          # herdr を参照するのは wsl.nix のみ。pi/yomogi のモジュールは herdr を
          # 引数に取らないため、遅延評価で aarch64 版 herdr は forced されずビルドされない。
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
