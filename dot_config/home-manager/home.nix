{ config, pkgs, lib, host, paseo, herdr, ... }:
let
  # nixpkgs に無い自前パッケージは packages/ 配下に 1 ファイルずつ分離し、
  # callPackage で nixpkgs の依存（stdenv/fetchurl 等）を自動注入して読み込む。
  redmine-go = pkgs.callPackage ./packages/redmine-go.nix { };
  ntn = pkgs.callPackage ./packages/ntn.nix { };
  gog-setup-credentials = pkgs.callPackage ./packages/gog-setup-credentials.nix { };
  # docker は導入せず podman へ委譲する。エイリアスは対話シェルにしか効かず
  # justfile やスクリプトの sh からは見えないため、PATH 上に実体のラッパーを置く。
  docker-compat = pkgs.writeShellScriptBin "docker" ''
    exec ${pkgs.podman}/bin/podman "$@"
  '';
  docker-compose-compat = pkgs.writeShellScriptBin "docker-compose" ''
    exec ${pkgs.podman-compose}/bin/podman-compose "$@"
  '';
in
{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "claude-code" "proton-pass-cli" ];

  home = {
    username = "ekuinox";
    homeDirectory =
      if pkgs.stdenv.isDarwin then "/Users/ekuinox" else "/home/ekuinox";
    stateVersion = "26.05";
    # programs.* モジュールがあるツール（bat/eza/ripgrep/fd/btop/lazygit/
    # lazydocker/tealdeer/yazi/zellij）は下の programs で enable するのでここには置かない。
    # yazi のプレビュー依存（chafa/ffmpeg-headless/imagemagick/p7zip/poppler-utils）は
    # PATH 上にあれば yazi が自動的に検出して使う。jq/fd/ripgrep/fzf/zoxide は導入済み。
    packages = [
      pkgs.awscli2
      # netstat 代替。帯域をプロセス別に可視化する
      pkgs.bandwhich
      # bzip2 展開・圧縮（環境未導入のため追加）
      pkgs.bzip2
      # yazi プレビュー: 画像をターミナル描画（sixel/kitty 非対応端末向けフォールバック）
      pkgs.chafa
      pkgs.chezmoi
      pkgs.claude-code
      # Cloudflare Tunnel のクライアント。`cloudflared tunnel ...` を PATH 上に置く
      pkgs.cloudflared
      # Ubuntu 26.04 標準の uutils ls はロケールを見ず、日本語など非 ASCII の
      # ファイル名を端末で ? や 8 進エスケープに化けさせる（最新版でも未修正）。
      # 成熟した GNU coreutils を PATH 先頭(nix-profile)に置き uutils(/usr/bin) を上書きする。
      pkgs.coreutils
      # DNS 調査。dig / nslookup / host（環境未導入のため追加）
      pkgs.dnsutils
      # du 代替。ディスク使用量を視覚的に表示（アトリビュート名は dust、中身は du-dust）
      pkgs.dust
      # yazi プレビュー: 動画サムネイル生成（headless で軽量）
      pkgs.ffmpeg-headless
      pkgs.gcc
      pkgs.gh
      pkgs.gogcli
      # curl 代替の HTTP クライアント（本体コマンドは http / https）
      pkgs.httpie
      # yazi プレビュー: SVG/HEIC/フォント等の変換
      pkgs.imagemagick
      pkgs.jq
      pkgs.just
      # traceroute+ping の実況版。ネット障害切り分け（環境未導入のため追加）
      pkgs.mtr
      pkgs.nano
      # ポートスキャン。ncat も付属（環境未導入のため追加）
      pkgs.nmap
      # yazi プレビュー: 書庫(zip/7z 等)の中身表示（7z コマンド）
      pkgs.p7zip
      # lspci。PCI デバイス一覧（環境未導入のため追加）
      pkgs.pciutils
      # 並列 gzip（環境未導入のため追加）
      pkgs.pigz
      pkgs.podman
      pkgs.podman-compose
      # yazi プレビュー: PDF のサムネイル生成（pdftoppm）
      pkgs.poppler-utils
      pkgs.proton-pass-cli
      # クラウドストレージ同期（環境未導入のため追加）
      pkgs.rclone
      # sed 代替。直感的な文字列置換
      pkgs.sd
      # nc の高機能版。ポートフォワード等（環境未導入のため追加）
      pkgs.socat
      pkgs.strace
      # パケットキャプチャ（環境未導入のため追加）
      pkgs.tcpdump
      # 経路調査（環境未導入のため追加）
      pkgs.traceroute
      pkgs.tree
      # rar/zip/7z を展開（free。環境未導入のため追加）
      pkgs.unar
      # zip 展開（環境未導入のため追加）
      pkgs.unzip
      # lsusb。USB デバイス一覧（環境未導入のため追加）
      pkgs.usbutils
      # ファイル変更を検知してコマンドを自動実行
      pkgs.watchexec
      # ドメイン/IP の登録情報（環境未導入のため追加）
      pkgs.whois
      # curl 代替の軽量 HTTP クライアント（Rust 製）
      pkgs.xh
      # jq の YAML/XML 版
      pkgs.yq-go
      # zip 作成（環境未導入のため追加）
      pkgs.zip
      # 高速圧縮（環境未導入のため追加）
      pkgs.zstd
      ntn
      redmine-go
      gog-setup-credentials
      docker-compat
      docker-compose-compat
      paseo
      # herdr（エージェント多重化 TUI）は wsl のみ。pi では参照しない。
    ] ++ lib.optional (host == "wsl") herdr;
    sessionVariables = { };

    # nano のシンタックスハイライト。scopatz/nanorc プリセット（118 言語）を読み込む
    file.".nanorc".text = ''
      include "${pkgs.nanorc}/share/*.nanorc"
      # nix は scopatz プリセットに無いため nano 同梱の公式定義を追加する
      include "${pkgs.nano}/share/nano/nix.nanorc"
    '';

    # rootless podman 用の containers 設定。非 NixOS では /etc/containers を
    # 誰も用意しないため、ユーザー側 (~/.config/containers) を home-manager で管理する。
    # イメージ署名ポリシー。これが無いと "no policy.json file found" で起動できない
    file.".config/containers/policy.json".text = ''
      {
        "default": [{ "type": "insecureAcceptAnything" }]
      }
    '';
    # 短縮名 (hello-world 等) を docker.io から解決できるようにする
    file.".config/containers/registries.conf".text = ''
      unqualified-search-registries = ["docker.io"]
    '';
    # docker compose ... 実行時の "Executing external compose provider" 警告を抑制する
    file.".config/containers/containers.conf".text = ''
      [engine]
      compose_warning_logs = false
    '';

    # herdr（エージェント多重化 TUI）の設定。プレーンな TOML なので nix で直接生成する。
    # herdr 本体と同じく wsl 限定（pi では enable=false でファイルを置かない）。
    file.".config/herdr/config.toml" = {
      enable = host == "wsl";
      text = ''
        onboarding = false

        [terminal]
        default_shell = "bash"
        shell_mode = "auto"
        new_cwd = "follow"

        [keys]
        prefix = "ctrl+b"
        next_tab = "prefix+n"
        previous_tab = "prefix+p"

        [theme]
        name = "catppuccin"

        [ui.toast]
        delivery = "herdr"
      '';
    };
  };

  programs = {
    home-manager.enable = true;

    # cat 代替。シンタックスハイライト＋行番号＋git 差分表示
    bat.enable = true;
    # top 代替のリッチなシステムモニタ
    btop.enable = true;
    # ls 代替。enableBashIntegration を有効にすると ls→eza エイリアスが張られ
    # coreutils の ls を上書きしてしまうため、意図的に enable のみとする。
    eza.enable = true;
    # find 代替。直感的で速い
    fd.enable = true;
    # コンテナ操作の TUI（podman 互換）
    lazydocker.enable = true;
    # Git 操作の TUI
    lazygit.enable = true;
    # grep 代替。gitignore を考慮した高速検索（rg）
    ripgrep.enable = true;
    # tldr。man の実用例だけを簡潔に表示
    tealdeer.enable = true;
    # ターミナルファイルマネージャ。`y` で終了時に最後の cwd へ cd するラッパーを追加
    yazi = {
      enable = true;
      enableBashIntegration = true;
    };

    # ターミナルマルチプレクサ。パッケージは入れるが、対話シェル起動時の自動起動は
    # 無効化している（enableBashIntegration=false）。使うときは手動で `zellij` を実行する。
    zellij = {
      enable = true;
      enableBashIntegration = false;
    };

    bash = {
      enable = true;
      historyControl = [ "ignoredups" "ignorespace" ];
      historySize = 10000;
      historyFileSize = 20000;
      shellOptions = [ "histappend" "checkwinsize" ];
      # 非ログインの対話シェル（新しいタブや tmux 等）は /etc/profile を読まず、
      # multi-user nix の PATH 設定（/etc/profile.d/nix.sh）が効かない。nix 本体は
      # ~/.nix-profile ではなく root の default プロファイルにあるため見失う。
      # nix が未ロードのときだけ公式スクリプトを読み込んで補う。パスを直書きせず
      # 公式の single source に委譲し、ログインシェルでの二重読み込み（PATH 重複）も避ける。
      initExtra = ''
        if ! command -v nix >/dev/null 2>&1 && [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
          . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        fi
      '';
      shellAliases = {
        # home-manager switch。ホスト鍵は flake から渡される現ホスト名を使う。
        hms = "home-manager switch --flake ~/.config/home-manager#${host}";
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

    fzf = {
      enable = true;
      enableBashIntegration = true;
    };

    starship = {
      enable = true;
      enableBashIntegration = true;
      settings = {
        # OS 名をプロンプト先頭に表示する（$all は os 以外の全モジュール）
        format = "$os$all";
        os.disabled = false;
      };
    };
  };

  # mube スマートロックの中継スタック（Caddy ヘッダ削ぎプロキシ + cloudflared tunnel）。
  # モジュール実体は flake input の mube リポジトリ側。中継役は自宅 Pi の個体 yomogi のみ
  # （汎用の pi では有効にしない）。
  # 秘密物（~/.cloudflared/cert.pem と <tunnel-id>.json）は手動配置。linger 必須。
  services.mube-door-lock = {
    enable = host == "yomogi";
    hostname = "door-lock-private.ekuinox.dev";
    tunnelId = "b45a50d5-24f6-4732-9568-7971f9772504";
    picoOrigin = "http://172.20.10.13:80"; # Pico の IP が変わったらここを更新して hms
    protocol = "http2"; # この回線は QUIC(UDP 7844) が塞がれているため必須
  };

  # Paseo デーモンを常駐させる。状態は $HOME 配下 (~/.paseo, ~/.claude) に
  # 永続するため、再起動でエージェント（セッション）は保持され、進行中ターン
  # だけが中断される。systemd user の環境は最小限で .bashrc も /etc/profile も
  # 読まないため、デーモンが生成するエージェント (claude 等) 用に PATH を明示する。
  # nix 本体 (nix, nix-build 等) は ~/.nix-profile ではなく multi-user の default
  # プロファイル配下にあるので、エージェントから nix が引けるよう明示的に含める。
  # ヘッドレス運用で未ログイン時も動かすには `loginctl enable-linger` が別途必要。
  systemd.user.services.paseo = {
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
        exec ${paseo}/bin/paseo start --foreground
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
