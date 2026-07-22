# 自宅 Pi の個体 yomogi 固有の設定。pi.nix を継承しつつ door-lock 中継役を担う。
# mube スマートロックの中継スタック（Caddy ヘッダ削ぎプロキシ + cloudflared tunnel）。
# モジュール実体は flake input の mube 側（flake.nix で yomogi の modules に import 済み）。
# このモジュールは yomogi でしか読まれないため enable は無条件 true。
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
