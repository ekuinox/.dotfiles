# home-manager ホスト構成のモジュール分割 (Issue #29)

## 背景

#28 で `hosts` に yomogi（自宅 Pi の個体名、door-lock 中継役）を追加したが、実態は「全ホストが同じ `home.nix` を共有し、yomogi は host 文字列の比較で door-lock を有効化しているだけ」で、pi を継承する構造にはなっていない。将来 `host == "pi"` でガードした設定を書くと yomogi に反映されず破綻する。

本仕様では、モジュール分割 + `imports` による本物の継承へ置き換える。

## ゴール

- yomogi が pi を継承する（pi.nix への追記が自動で yomogi に効く）構造にする。
- host 文字列比較の条件分岐をホストモジュールへ移し、`home.nix` 側から `host ==` 判定を撤廃する。
- hms エイリアスが参照するホスト名（specialArg の `host`）は引き続き渡す。

## ファイル構成

```
dot_config/home-manager/
  flake.nix          # hosts を { system, modules } 形式へ
  common.nix         # 旧 home.nix（全ホスト共通のベース）
  hosts/
    wsl.nix          # herdr パッケージ + herdr config.toml
    pi.nix           # pi 系（aarch64）共通。現状は空、将来の pi ガード設定の置き場
    yomogi.nix       # services.mube-door-lock（door-lock 中継）
  packages/          # 変更なし
```

`home.nix` は `common.nix` にリネームする。ホストモジュール（`hosts/*.nix`）と役割を明確に区別するため。

## flake.nix

`hosts` をホスト名 → `{ system, modules }` のマップに変更する。

```nix
hosts = {
  wsl    = { system = "x86_64-linux";  modules = [ ./hosts/wsl.nix ]; };
  pi     = { system = "aarch64-linux"; modules = [ ./hosts/pi.nix ]; };
  yomogi = {
    system = "aarch64-linux";
    modules = [ ./hosts/pi.nix ./hosts/yomogi.nix mube.homeManagerModules.default ];
  };
};

mkHome = host: { system, modules }:
  home-manager.lib.homeManagerConfiguration {
    pkgs = nixpkgs.legacyPackages.${system};
    modules = [ ./common.nix ] ++ modules;
    extraSpecialArgs = {
      inherit host;
      paseo = paseo.packages.${system}.default;
      herdr = herdr.packages.${system}.default;
    };
  };

homeConfigurations = nixpkgs.lib.mapAttrs mkHome hosts;
```

ポイント:

- yomogi の `modules` に `./hosts/pi.nix` を含めることで、pi.nix への追記が自動で yomogi に効く（本物の継承）。
- mube モジュール（`services.mube-door-lock` オプションの提供元）は yomogi の `modules` にだけ入れる。wsl/pi は door-lock オプション自体を持たない。
- `herdr` specialArg は従来どおり全ホストへ渡すが、参照するのは wsl.nix のみ。pi/yomogi のモジュール関数は `herdr` を引数に取らないため Nix の遅延評価で aarch64 版 herdr は forced されず、ビルドされない（現行の挙動を維持）。

## 条件分岐の移動

`home.nix`（→ common.nix）にある host 文字列比較 3 箇所を撤廃し、該当ホストのモジュールへ無条件設定として移す。

| 現状 (home.nix) | 移動先 | 移動後 |
|---|---|---|
| `home.packages ++ lib.optional (host == "wsl") herdr` | hosts/wsl.nix | `home.packages = [ herdr ];`（無条件、common の list にマージ） |
| `file.".config/herdr/config.toml".enable = host == "wsl"` | hosts/wsl.nix | `file.".config/herdr/config.toml".text = ...`（無条件配置） |
| `services.mube-door-lock.enable = host == "yomogi"` | hosts/yomogi.nix | `enable = true;`（無条件） |

モジュールが該当ホストでしか読まれないため、`host ==` 判定はすべて不要になる。

## 各モジュールの内容

### common.nix（旧 home.nix）

- 上記 3 箇所を削除。
- 関数シグネチャから `herdr` を外す（`{ config, pkgs, lib, host, paseo, ... }`）。`host` は hms エイリアス（`#${host}`）で引き続き必要。`paseo` は systemd user サービスで必要。
- それ以外（packages 本体、programs.*、containers 設定、paseo デーモン等）は不変。

### hosts/wsl.nix

```nix
{ pkgs, herdr, ... }:
{
  home.packages = [ herdr ];
  home.file.".config/herdr/config.toml".text = ''
    onboarding = false
    ...
  '';
}
```

herdr の config.toml 本文は現行 home.nix からそのまま移す。

### hosts/pi.nix

```nix
# Raspberry Pi (aarch64) 共通のホスト設定。yomogi はこれを継承する。
# 現状 pi 固有の差分は無い。pi 系で共通化したい設定はここに追記すると
# yomogi にも自動で反映される。
{ ... }:
{
}
```

### hosts/yomogi.nix

```nix
# 自宅 Pi の個体 yomogi 固有。mube door-lock の中継役。
# 秘密物（~/.cloudflared/cert.pem と <tunnel-id>.json）は手動配置。linger 必須。
{ ... }:
{
  services.mube-door-lock = {
    enable = true;
    hostname = "door-lock-private.ekuinox.dev";
    tunnelId = "b45a50d5-24f6-4732-9568-7971f9772504";
    picoOrigin = "http://172.20.10.13:80"; # Pico の IP が変わったらここを更新して hms
    protocol = "http2"; # この回線は QUIC(UDP 7844) が塞がれているため必須
  };
}
```

## 付随する修正

- flake.nix のコメント内 `home.nix` 参照を `common.nix` に更新。herdr / mube の挙動説明もモジュール分割後の内容へ更新。
- `dot_config/home-manager/scripts/gog-setup-credentials.sh` の先頭コメント `home.nix の pkgs.writeShellApplication ...` を `common.nix` に更新。
- README の home-manager 構成説明は、必要ならホストモジュール構成を一言追記する（過剰にはしない）。

## 動作確認

3 ターゲットを検証する。

- pi / yomogi は aarch64-linux でこの worktree ネイティブ build が可能。`nix build .#homeConfigurations.pi.activationPackage` と `.#homeConfigurations.yomogi.activationPackage` を通す。
- wsl は x86_64-linux のため aarch64 上ではネイティブ build できない。`nix eval` / dry-run で評価が通ることを確認する。
- yomogi の activationPackage にのみ door-lock の user unit 2 本（mube 側が生成する caddy 相当 + cloudflared）が含まれ、pi/wsl には含まれないことを確認する。

## デプロイ上の注意

- chezmoi ソースで `home.nix` → `common.nix` にリネームすると、`chezmoi apply` 後もターゲット側に旧 `~/.config/home-manager/home.nix` が孤児として残る場合がある（chezmoi は管理外になったファイルを自動削除しない）。flake は `./common.nix` のみ参照するため実害はないが、各マシンで手動削除するのが望ましい。
- `hosts/` 配下は新規ファイルとしてソースに追加され、`chezmoi apply` でターゲットに配置される。

## スコープ外 (YAGNI)

- mac ホストの追加（将来 `hosts/mac.nix` を作る余地は残すが本 Issue では扱わない）。
- specialArg のホスト別トリミング（herdr を wsl のみに渡す等）。遅延評価で十分なため行わない。
