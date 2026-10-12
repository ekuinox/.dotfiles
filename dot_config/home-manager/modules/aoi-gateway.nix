# aoi の HTTP サーバーを Cloudflare Access の後ろにまとめて公開する入口
# （Caddy の Host 振り分けプロキシ + cloudflared named tunnel）の home-manager モジュール。
# 設計は docs/superpowers/specs/2026-10-12-aoi-gateway-design.md。
# 公開ホスト名は <routes のキー><hostSuffix>.<domain>（例: kgd-aoi.ekuinox.dev）に固定し、
# Access アプリ *<hostSuffix>.<domain> の対象から外れる名前を設定できないようにする。
# 前提: lingering 有効（loginctl enable-linger <user>）。
# 秘密物（~/.cloudflared/cert.pem とトンネル資格情報 <tunnel-id>.json）は含まない。手動配置。
{ config, lib, pkgs, ... }:
let
  cfg = config.services.aoi-gateway;

  hostOf = name: "${name}${cfg.hostSuffix}.${cfg.domain}";
  hosts = map hostOf (lib.attrNames cfg.routes);

  # Host は完全一致で振り分ける。末尾一致にすると、ワイルドカード DNS で届く
  # x.kgd-aoi.<domain> のような 2 階層目（Access の対象外）まで転送してしまう。
  # Cf-* を削るのは、Cloudflare 経由の印が付いたリクエストを拒否するアプリ（kgd の
  # ビューアなど）に、Access を通ったリクエストを LAN からのものとして渡すため。
  routeBlocks = lib.concatStrings (lib.mapAttrsToList (name: origin: ''
    	@${name} host ${hostOf name}
    	handle @${name} {
    		reverse_proxy ${origin} {
    			header_up -Cf-*
    			header_up -Cdn-Loop
    		}
    	}
  '') cfg.routes);

  # なぜサイトアドレスが「http://:<port>」+ default_bind なのか（Host 照合の罠）:
  # 「127.0.0.1:<port>」をサイトアドレスにすると Caddy はそれを Host 名として照合し、
  # cloudflared からのリクエスト（Host: <公開ホスト名>）にマッチせず空の 200 を返す
  # （door-lock の中継で 2026-07-22 に踏んだ）。Host 不問の「:<port>」で受け、
  # 待受アドレスの限定は default_bind 127.0.0.1 で行う。
  caddyfile = pkgs.writeText "aoi-gateway-Caddyfile" ''
    {
    	default_bind 127.0.0.1
    	admin off
    	auto_https off
    	persist_config off
    }

    http://:${toString cfg.proxyPort} {
    	log {
    		output stderr
    		format json
    	}
    ${routeBlocks}
    	handle {
    		respond "not found" 404
    	}
    }
  '';

  # 全ホスト名を catch-all の 1 ルールで Caddy へ流す。Protect with Access により、
  # Access アプリを通っていないリクエスト（ワイルドカード DNS で届く対象外の名前など）は
  # cloudflared が 403 で止め、Caddy まで届かない。
  cloudflaredConfig = (pkgs.formats.yaml { }).generate "aoi-gateway-cloudflared.yml" (
    {
      tunnel = cfg.tunnelId;
      credentials-file = cfg.credentialsFile;
      ingress = [
        {
          service = "http://127.0.0.1:${toString cfg.proxyPort}";
          originRequest.access = {
            required = true;
            inherit (cfg) teamName;
            audTag = cfg.audTags;
          };
        }
      ];
    }
    // lib.optionalAttrs (cfg.protocol != null) { inherit (cfg) protocol; }
  );

  # デプロイ後に外から叩いて、未ログインのリクエストが公開ホスト名では Access のログインへ、
  # 対象外の名前では cloudflared の 403 へ落ちることを確かめる。
  checkScript = pkgs.writeShellApplication {
    name = "aoi-gateway-check";
    runtimeInputs = [ pkgs.curl pkgs.coreutils ];
    text = ''
      fail=0

      # 接続できないときも 000 として FAIL を出す (set -e で止めない)
      fetch() {
        curl -s -o /dev/null --max-time 10 -w '%{http_code} %{redirect_url}' "$@" || true
      }

      hosts=(${lib.escapeShellArgs hosts})
      for host in "''${hosts[@]}"; do
        out=$(fetch "https://$host/")
        status=''${out%% *}
        location=''${out#* }
        if [[ $status == 302 && $location == https://*.cloudflareaccess.com/* ]]; then
          echo "ok   $host -> $status (Access login)"
        else
          echo "FAIL $host -> $out (expected: 302 to *.cloudflareaccess.com)"
          fail=1
        fi
      done

      # Access アプリの対象外の名前。ワイルドカード DNS でトンネルに届き、cloudflared が止める
      probe="aoi-gateway-check-$(date +%s).${cfg.domain}"
      out=$(fetch "https://$probe/")
      status=''${out%% *}
      if [[ $status == 403 ]]; then
        echo "ok   $probe -> $status"
      else
        echo "FAIL $probe -> $out (expected: 403)"
        fail=1
      fi

      # 偽の JWT を付けても通らない
      out=$(fetch -H 'Cf-Access-Jwt-Assertion: invalid' "https://$probe/")
      status=''${out%% *}
      if [[ $status =~ ^[45][0-9][0-9]$ ]]; then
        echo "ok   $probe (forged JWT) -> $status"
      else
        echo "FAIL $probe (forged JWT) -> $out (expected: 4xx or 5xx)"
        fail=1
      fi

      exit "$fail"
    '';
  };
in
{
  options.services.aoi-gateway = {
    enable = lib.mkEnableOption "aoi-gateway（Caddy プロキシ + cloudflared）。lingering 必須（loginctl enable-linger）";

    domain = lib.mkOption {
      type = lib.types.str;
      example = "example.com";
      description = "公開ホスト名を置くゾーン（必須）";
    };

    hostSuffix = lib.mkOption {
      type = lib.types.str;
      default = "-aoi";
      description = "公開ホスト名の 1 階層目に付ける接尾辞。Access アプリ *<hostSuffix>.<domain> と揃える";
    };

    routes = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { kgd = "http://192.168.1.5:8081"; };
      description = "サービス名から転送先 URL への対応表。公開ホスト名は <サービス名><hostSuffix>.<domain> になる";
    };

    tunnelId = lib.mkOption {
      type = lib.types.str;
      example = "00000000-0000-0000-0000-000000000000";
      description = "cloudflared named tunnel の ID（必須。cloudflared tunnel create で発行）";
    };

    teamName = lib.mkOption {
      type = lib.types.str;
      example = "myteam";
      description = "Zero Trust のチーム名（必須。ログイン画面の <チーム名>.cloudflareaccess.com）";
    };

    audTags = lib.mkOption {
      type = lib.types.nonEmptyListOf lib.types.str;
      description = "Access アプリの AUD タグ（必須。アプリを作り直すと変わる）";
    };

    proxyPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Caddy プロキシの待受ポート（127.0.0.1 のみ）";
    };

    protocol = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "http2";
      description = "cloudflared のトンネルプロトコル。null なら cloudflared の既定（auto）。QUIC(UDP 7844) が塞がれた回線では \"http2\" を指定する";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.cloudflared/${cfg.tunnelId}.json";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.cloudflared/''${tunnelId}.json"'';
      description = "トンネル資格情報 JSON のパス（手動配置。モジュールは配布しない）";
    };
  };

  config = lib.mkIf cfg.enable {
    # サービス名は DNS の 1 ラベルの一部になり、Caddy の matcher 名にも使う
    assertions = lib.mapAttrsToList (name: _: {
      assertion = builtins.match "[a-z0-9]([a-z0-9-]*[a-z0-9])?" name != null;
      message = "services.aoi-gateway.routes: サービス名 \"${name}\" は英小文字・数字・ハイフンだけで書く（先頭と末尾はハイフン不可）";
    }) cfg.routes;

    home.packages = [ checkScript ];

    systemd.user.services.aoi-gateway-proxy = {
      Unit = {
        Description = "aoi-gateway Host routing proxy (Caddy)";
      };
      Service = {
        # ストアパスのファイル名が「Caddyfile」丸ごとではないため adapter の明示が必須
        ExecStart = "${pkgs.caddy}/bin/caddy run --config ${caddyfile} --adapter caddyfile";
        Restart = "always";
        RestartSec = 2;
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services.cloudflared-aoi-gateway = {
      Unit = {
        Description = "aoi-gateway Cloudflare named tunnel";
      };
      Service = {
        ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate --config ${cloudflaredConfig} run";
        Restart = "always";
        RestartSec = 2;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
