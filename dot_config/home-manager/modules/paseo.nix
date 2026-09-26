# Paseo（リモートからエージェントを操作する CLI/サーバー）を入れるホスト用のモジュール。
# linux.nix のように種別で読むのではなく、必要な個体だけが imports で取り込む
# （hizake / ume / yomogi / yuri）。paseo はビルドが重く、スペックの低い Pi
# （sumomo / aoi）では導入を避けたいため。nix の遅延評価により、本モジュールを
# 読まないホストでは paseo が instantiate すらされない。
{ config, pkgs, lib, paseo, ... }:
let
  # Linux では上流の nix パッケージがモノレポ全体を buildNpmPackage にかけるため、
  # Pi 4（yomogi）で 30〜60 分・RSS 3.7GB、x86_64（hizake / ume）でも 15 分以上を要する。
  # さらに 0.9.2 では成果物から server の exports.js が抜けてデーモンが起動しなかった。
  # 同じ成果物が ghcr.io/getpaseo/paseo の amd64 / arm64 イメージとして配布されて
  # いるので、そちらを展開したパッケージを使ってビルドを回避する。
  # aarch64-darwin（yuri）はイメージが無いため、従来どおり flake input をそのまま使う。
  paseoPkg =
    if pkgs.stdenv.hostPlatform.isLinux
    then pkgs.callPackage ../packages/paseo-image.nix { }
    else paseo;

  # 0.9.0 で `paseo start --foreground` が廃止され `paseo daemon run` になった。
  # paseoPkg をホスト別に分岐させている以上、サブコマンドも同じバージョンから
  # 導かないと食い違う（Linux はイメージのバージョン、yuri は flake input のバージョン）。
  # flake input を 0.9 系に上げたときは、この分岐が自動で新しい形に切り替わる。
  paseoDaemonArgs =
    if lib.versionAtLeast paseoPkg.version "0.9.0"
    then "daemon run"
    else "start --foreground";
in
{
  home.packages = [ paseoPkg ];

  # Paseo デーモンを常駐させる。状態は $HOME 配下 (~/.paseo, ~/.claude) に
  # 永続するため、再起動でエージェント（セッション）は保持され、進行中ターン
  # だけが中断される。systemd user の環境は最小限で .bashrc も /etc/profile も
  # 読まないため、デーモンが生成するエージェント (claude 等) 用に PATH を明示する。
  # nix 本体 (nix, nix-build 等) は ~/.nix-profile ではなく multi-user の default
  # プロファイル配下にあるので、エージェントから nix が引けるよう明示的に含める。
  # ヘッドレス運用で未ログイン時も動かすには `loginctl enable-linger` が別途必要。
  # darwin には systemd が無く home-manager が assertion で弾くため Linux 限定にする。
  # yuri では paseo コマンドが PATH に入るだけで、デーモンは常駐しない。
  systemd.user.services.paseo = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    Unit = {
      Description = "Paseo daemon (control AI coding agents remotely)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      # ダウンロードはブラウザが daemon の HTTP エンドポイントへ直接アクセスする
      # 方式のため、0.0.0.0 待ち受け時はブラウザに広告する LAN IP が必要になる。
      # paseo の既定選択(インターフェイス名の辞書順で最初の非内部 IPv4)は
      # Docker ブリッジ(br-*, 172.19.0.1 等)を誤選択するので、既定ルートの
      # 送信元アドレスから起動時に動的解決して PASEO_PRIMARY_LAN_IP に渡す。
      # インターフェイス名に依存せず、DHCP や eth0→wlan0 の切り替えにも追従し、
      # IP の直書きを避けられる。
      ExecStart = pkgs.writeShellScript "paseo-start" ''
        export PASEO_PRIMARY_LAN_IP="$(${pkgs.iproute2}/bin/ip -4 route get 1.1.1.1 2>/dev/null | ${pkgs.gnugrep}/bin/grep -oP 'src \K\S+')"
        exec ${paseoPkg}/bin/paseo ${paseoDaemonArgs}
      '';
      Restart = "on-failure";
      RestartSec = 5;
      Environment = [
        "PATH=${config.home.profileDirectory}/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"
      ];
    };
    Install.WantedBy = [ "default.target" ];
  };
}
