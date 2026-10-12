# 自宅 Pi の個体 aoi 固有の設定。pi.nix を継承しつつ、aoi の HTTP サーバーを
# Cloudflare Access の後ろにまとめて公開する入口（aoi-gateway）を担う。
# 設計と展開手順は docs/superpowers/specs/2026-10-12-aoi-gateway-design.md。
# 秘密物（~/.cloudflared/<tunnel-id>.json）は手動配置。linger 必須。
{ ... }:
{
  imports = [ ../modules/aoi-gateway.nix ];

  services.aoi-gateway = {
    enable = true;
    domain = "ekuinox.dev";
    tunnelId = "f8c8da83-f4d2-4b84-8c85-9f0c51feca13"; # cloudflared tunnel create aoi-gateway
    teamName = "white-fog-5e56";
    # Access アプリ *-aoi.ekuinox.dev の AUD タグ。アプリを作り直すと変わるので、そのときはここも直す
    audTags = [ "e9bfcf394b6b27bc0154371c5cb219c93258a9008eaf1254feff55915939060a" ];
    # aoi の 8080 番は別のプロセスが使っているため 8090 番で待ち受ける
    proxyPort = 8090;
    protocol = "http2"; # この回線は QUIC(UDP 7844) が塞がれているため必須
    routes = {
      # 公開ホスト名は kgd-aoi.ekuinox.dev。転送先は loopback ではなく aoi の LAN アドレスにする
      # （kgd のビューアは loopback からの接続を拒否するため）。DHCP で予約して固定する。
      kgd = "http://172.20.1.1:8081";
    };
  };
}
