# 自宅 Pi の個体 aoi 固有の設定。pi.nix を継承しつつ、aoi の HTTP サーバーを
# Cloudflare Access の後ろにまとめて公開する入口（aoi-gateway）を担う。
# 設計と展開手順は docs/superpowers/specs/2026-10-12-aoi-gateway-design.md。
# 秘密物（~/.cloudflared/<tunnel-id>.json）は手動配置。linger 必須。
{ ... }:
{
  imports = [ ../modules/aoi-gateway.nix ];

  services.aoi-gateway = {
    # トンネル aoi-gateway を作成し、tunnelId / teamName / audTags を埋めてから true にする
    # （spec の展開手順 1〜4）。
    enable = false;
    domain = "ekuinox.dev";
    protocol = "http2"; # この回線は QUIC(UDP 7844) が塞がれているため必須
    routes = {
      # 公開ホスト名は kgd-aoi.ekuinox.dev。転送先は loopback ではなく aoi の LAN アドレスにする
      # （kgd のビューアは loopback からの接続を拒否するため）。DHCP で予約して固定する。
      kgd = "http://172.20.1.1:8081";
    };
  };
}
