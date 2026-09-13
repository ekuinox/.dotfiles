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
    # 取り込むのは hosts/paseo.nix のみ（hizake / ume / yomogi / yuri が import する）。
    paseo.url = "github:getpaseo/paseo";
    # herdr（AI コーディングエージェント用ターミナルワークスペース管理）。paseo と
    # 同じく flake が各 system 向け package を公開しているので home.packages に入れる。
    # nixpkgs は herdr 側のピンに従わせる（follows で上書きしない）。wsl 限定のため
    # hosts/wsl.nix でのみ参照する（pi 系 / yuri では遅延評価でビルドされない）。
    herdr.url = "github:ogulcancelik/herdr/v0.7.4";
    # mube スマートロックの中継スタック（Caddy ヘッダ削ぎプロキシ + cloudflared）を
    # home-manager モジュールとして提供する。yomogi の modules でのみ import・有効化（hosts/yomogi.nix 参照）。
    mube.url = "github:ekuinox/mube";
  };

  outputs = { nixpkgs, home-manager, paseo, herdr, mube, ... }:
    let
      # ホスト名 -> { system, modules }。鍵はマシンの個体名で持つ。
      # 共通設定は common.nix、種別ごとの共通差分は hosts/{linux,pi,wsl}.nix、
      # 個体固有の差分は hosts/<個体名>.nix に置く。linux.nix は Linux ホストが
      # 共通で読む（systemd や Linux 限定パッケージは darwin で評価が通らないため
      # common.nix には置かない）。paseo は重いので pi 系では yomogi だけが持ち、
      # 取り込みは hosts/paseo.nix の imports で個体ごとに決める。
      hosts = {
        # WSL (x86_64) 機
        hizake = {
          system = "x86_64-linux";
          modules = [ ./hosts/linux.nix ./hosts/wsl.nix ];
        };
        ume = {
          system = "x86_64-linux";
          modules = [ ./hosts/linux.nix ./hosts/wsl.nix ];
        };
        # yomogi: 自宅 Pi の個体名。pi.nix を継承し、door-lock 中継役の設定を追加する。
        # mube.homeManagerModules.default は services.mube-door-lock オプションの提供元で、
        # yomogi だけが必要とするためここでのみ import する（他ホストはオプションを持たない）。
        yomogi = {
          system = "aarch64-linux";
          modules = [
            ./hosts/linux.nix
            ./hosts/pi.nix
            ./hosts/yomogi.nix
            mube.homeManagerModules.default
          ];
        };
        # sumomo / aoi: スペックの高くない Pi。paseo はビルド時間が問題になるため入れない。
        sumomo = {
          system = "aarch64-linux";
          modules = [ ./hosts/linux.nix ./hosts/pi.nix ];
        };
        aoi = {
          system = "aarch64-linux";
          modules = [ ./hosts/linux.nix ./hosts/pi.nix ];
        };
        # yuri: MacBook Air (Apple Silicon)。linux.nix は読まない。
        yuri = {
          system = "aarch64-darwin";
          modules = [ ./hosts/yuri.nix ];
        };
      };
      mkHome = host: { system, modules }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ ./common.nix ] ++ modules;
          # host は hms エイリアスの flake 参照先。paseo/herdr は system 別 package。
          # 全ホストに渡すが、nix は遅延評価なので実際に参照したホストしかビルドされない。
          # paseo を参照するのは paseo.nix、herdr は wsl.nix のみ。paseo.nix を読まない
          # sumomo / aoi では aarch64 版 paseo は instantiate すらされない。
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
