# Linux 共通のホスト設定。wsl / pi / yomogi が読む。
# common.nix を OS 非依存に保つため、Linux でしか成立しない設定はここへ置く。
#   - systemd.user.* は home-manager が非 Linux で assertion により弾く
#   - strace / pciutils / usbutils / traceroute は nixpkgs 上で Linux 限定
#   - podman 一式は macOS だと podman machine(VM) が別途要り、ラッパーが成立しない
#   - coreutils は Ubuntu の uutils ls 対策であり、macOS では BSD ls を上書きしてしまう
{ config, pkgs, paseo, ... }:
let
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
  # common.nix の home.packages リストへマージされる。
  home.packages = [
    # Ubuntu 26.04 標準の uutils ls はロケールを見ず、日本語など非 ASCII の
    # ファイル名を端末で ? や 8 進エスケープに化けさせる（最新版でも未修正）。
    # 成熟した GNU coreutils を PATH 先頭(nix-profile)に置き uutils(/usr/bin) を上書きする。
    pkgs.coreutils
    # lspci。PCI デバイス一覧
    pkgs.pciutils
    pkgs.podman
    pkgs.podman-compose
    pkgs.strace
    # 経路調査。nixpkgs の traceroute は Linux 限定（macOS は /usr/sbin/traceroute が標準）
    pkgs.traceroute
    # lsusb。USB デバイス一覧
    pkgs.usbutils
    docker-compat
    docker-compose-compat
    paseo
  ];

  # rootless podman 用の containers 設定。非 NixOS では /etc/containers を
  # 誰も用意しないため、ユーザー側 (~/.config/containers) を home-manager で管理する。
  home.file = {
    # イメージ署名ポリシー。これが無いと "no policy.json file found" で起動できない
    ".config/containers/policy.json".text = ''
      {
        "default": [{ "type": "insecureAcceptAnything" }]
      }
    '';
    # 短縮名 (hello-world 等) を docker.io から解決できるようにする
    ".config/containers/registries.conf".text = ''
      unqualified-search-registries = ["docker.io"]
    '';
    # docker compose ... 実行時の "Executing external compose provider" 警告を抑制する
    ".config/containers/containers.conf".text = ''
      [engine]
      compose_warning_logs = false
    '';
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
