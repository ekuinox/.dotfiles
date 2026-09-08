{ pkgs, lib, host, ... }:
let
  # nixpkgs に無い自前パッケージは packages/ 配下に 1 ファイルずつ分離し、
  # callPackage で nixpkgs の依存（stdenv/fetchurl 等）を自動注入して読み込む。
  redmine-go = pkgs.callPackage ./packages/redmine-go.nix { };
  ntn = pkgs.callPackage ./packages/ntn.nix { };
  gog-setup-credentials = pkgs.callPackage ./packages/gog-setup-credentials.nix { };
  git-setup-signing = pkgs.callPackage ./packages/git-setup-signing.nix { };
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
      # 並列 gzip（環境未導入のため追加）
      pkgs.pigz
      # yazi プレビュー: PDF のサムネイル生成（pdftoppm）
      pkgs.poppler-utils
      pkgs.proton-pass-cli
      # クラウドストレージ同期（環境未導入のため追加）
      pkgs.rclone
      # sed 代替。直感的な文字列置換
      pkgs.sd
      # nc の高機能版。ポートフォワード等（環境未導入のため追加）
      pkgs.socat
      # パケットキャプチャ（環境未導入のため追加）
      pkgs.tcpdump
      pkgs.tree
      # rar/zip/7z を展開（free。環境未導入のため追加）
      pkgs.unar
      # zip 展開（環境未導入のため追加）
      pkgs.unzip
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
      git-setup-signing
    ];
    sessionVariables = { };

    # bash / zsh の両方へ反映される共通エイリアス。
    shellAliases = {
      # home-manager switch。ホスト鍵は flake から渡される現ホスト名を使う。
      hms = "home-manager switch --flake ~/.config/home-manager#${host}";
    };

    # nano のシンタックスハイライト。scopatz/nanorc プリセット（118 言語）を読み込む
    file.".nanorc".text = ''
      include "${pkgs.nanorc}/share/*.nanorc"
      # nix は scopatz プリセットに無いため nano 同梱の公式定義を追加する
      include "${pkgs.nano}/share/nano/nix.nanorc"
    '';

  };

  programs = {
    home-manager.enable = true;

    # cat 代替。シンタックスハイライト＋行番号＋git 差分表示
    bat.enable = true;
    # top 代替のリッチなシステムモニタ
    btop.enable = true;
    # ls 代替。現在の home-manager は enable だけで bash / zsh に ls→eza の
    # エイリアスを張るため、その 2 つでは ls が eza になる。nushell 統合だけは
    # home-manager 側の既定が off のため builtin の ls のまま。スクリプトや
    # command ls では PATH 上の ls（Linux では linux.nix が入れる GNU coreutils）が使われる。
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
}
