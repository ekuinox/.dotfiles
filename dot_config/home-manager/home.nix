{ config, pkgs, lib, ... }:
let
  # nixpkgs に無い Go CLI を buildGoModule で自前ビルドする
  redmine-go = pkgs.buildGoModule {
    pname = "redmine-go";
    version = "0.2.0";
    src = pkgs.fetchFromGitHub {
      owner = "kqns91";
      repo = "redmine-go";
      rev = "v0.2.0";
      hash = "sha256-jrYo3ptqfHJk8r+05ndwBgg1UBJMcF4p0NNBoGjHcXM=";
    };
    vendorHash = "sha256-zFVdCFZK5uQAaIv3c8IMp/0B0sHOdV+xLjvjxZhEUto=";
    subPackages = [ "cmd/redmine" ];
  };

  # Proton Pass の添付（gog の OAuth クライアント資格情報）を gog の keyring へ
  # 橋渡しする一度きりのセットアップ。secret は repo にも /nix/store にも置かず、
  # 実行時に短命な一時ファイル経由で登録する（switch 時には行わない）。
  # 対象を指す 3 つの ID は環境変数から受け取る（.envrc + direnv での運用を想定）。
  gog-setup-credentials = pkgs.writeShellApplication {
    name = "gog-setup-credentials";
    runtimeInputs = [ pkgs.proton-pass-cli pkgs.gogcli pkgs.coreutils ];
    text = ''
      SHARE_ID="''${GOG_CRED_SHARE_ID:-}"
      ITEM_ID="''${GOG_CRED_ITEM_ID:-}"
      ATTACHMENT_ID="''${GOG_CRED_ATTACHMENT_ID:-}"
      client="''${GOG_CRED_CLIENT:-}"

      # 3 つとも未設定なら .envrc のサンプルを標準出力に出す
      # （`gog-setup-credentials > .envrc` で雛形を作れる）
      if [ -z "$SHARE_ID" ] && [ -z "$ITEM_ID" ] && [ -z "$ATTACHMENT_ID" ]; then
        cat <<'SAMPLE'
# gog-setup-credentials 用の識別子（Proton Pass の対象添付を指す）
# pass-cli で対象の vault/item/attachment の ID を調べて設定する。
export GOG_CRED_SHARE_ID=""
export GOG_CRED_ITEM_ID=""
export GOG_CRED_ATTACHMENT_ID=""
# 任意: gog の --client 名（空ならデフォルト）
# export GOG_CRED_CLIENT="default"
SAMPLE
        exit 0
      fi

      # 一部だけ未設定はエラー（3 つとも未設定のときだけサンプルを出す方針）
      missing=""
      if [ -z "$SHARE_ID" ]; then missing="$missing GOG_CRED_SHARE_ID"; fi
      if [ -z "$ITEM_ID" ]; then missing="$missing GOG_CRED_ITEM_ID"; fi
      if [ -z "$ATTACHMENT_ID" ]; then missing="$missing GOG_CRED_ATTACHMENT_ID"; fi
      if [ -n "$missing" ]; then
        echo "次の環境変数が未設定です:$missing" >&2
        echo "（3 つとも未設定なら .envrc サンプルを表示します）" >&2
        exit 1
      fi

      # pass-cli ログイン確認
      if ! pass-cli test >/dev/null 2>&1; then
        echo "pass-cli が未ログインです。先に 'pass-cli login' を実行してください。" >&2
        exit 1
      fi

      tmpdir="''${XDG_RUNTIME_DIR:-/tmp}"
      tmp="$(mktemp "$tmpdir/gog-cred.XXXXXX")"
      trap 'shred -u "$tmp" 2>/dev/null || rm -f "$tmp"' EXIT

      pass-cli item attachment download \
        --share-id "$SHARE_ID" --item-id "$ITEM_ID" --attachment-id "$ATTACHMENT_ID" \
        --output "$tmp"

      if [ -n "$client" ]; then
        gog auth credentials set "$tmp" --client "$client"
      else
        gog auth credentials set "$tmp"
      fi

      echo "OK: OAuth クライアント資格情報を keyring に登録しました。"
      echo "次に: gog auth add <email>  でアカウントを認可してください。"
    '';
  };
in
{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "claude-code" "proton-pass-cli" ];

  home = {
    username = "ekuinox";
    homeDirectory =
      if pkgs.stdenv.isDarwin then "/Users/ekuinox" else "/home/ekuinox";
    stateVersion = "26.05";
    packages = [
      pkgs.claude-code
      pkgs.chezmoi
      pkgs.gogcli
      pkgs.jq
      pkgs.nano
      pkgs.proton-pass-cli
      redmine-go
      gog-setup-credentials
    ];
    sessionVariables = { };

    # nano のシンタックスハイライト。scopatz/nanorc プリセット（118 言語）を読み込む
    file.".nanorc".text = ''
      include "${pkgs.nanorc}/share/*.nanorc"
      # nix は scopatz プリセットに無いため nano 同梱の公式定義を追加する
      include "${pkgs.nano}/share/nano/nix.nanorc"
    '';
  };

  programs = {
    home-manager.enable = true;

    bash = {
      enable = true;
      historyControl = [ "ignoredups" "ignorespace" ];
      historySize = 10000;
      historyFileSize = 20000;
      shellOptions = [ "histappend" "checkwinsize" ];
      shellAliases = {
        # 例: ll = "ls -alF";
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
