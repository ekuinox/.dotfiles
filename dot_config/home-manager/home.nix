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
  # 場所はプロンプトで尋ね、item view で ID を解決する（生の ID 入力は不要）。
  gog-setup-credentials = pkgs.writeShellApplication {
    name = "gog-setup-credentials";
    runtimeInputs = [ pkgs.proton-pass-cli pkgs.gogcli pkgs.jq pkgs.coreutils pkgs.gnused pkgs.gawk ];
    text = ''
      if ! pass-cli test >/dev/null 2>&1; then
        echo "pass-cli が未ログインです。先に 'pass-cli login' を実行してください。" >&2
        exit 1
      fi

      read -rp "Vault 名: " VAULT
      read -rp "Item タイトル: " ITEM_TITLE
      read -rp "gog の --client 名（空でデフォルト）: " client

      view="$(pass-cli item view --vault-name "$VAULT" --item-title "$ITEM_TITLE" --output json)"

      SHARE_ID="$(printf '%s' "$view" | jq -r '.shareId // .share_id // .shareID // empty')"
      ITEM_ID="$(printf '%s' "$view" | jq -r '.itemId // .item_id // .itemID // .id // empty')"
      atts="$(printf '%s' "$view" | jq -r '
        (.attachments // .files // [])[]
        | [ (.id // .attachmentId // .attachment_id // empty),
            (.name // .fileName // .filename // "") ] | @tsv')"

      if [ -z "$SHARE_ID" ] || [ -z "$ITEM_ID" ] || [ -z "$atts" ]; then
        echo "JSON から ID / attachment を解決できませんでした。実際のキーを確認してください:" >&2
        printf '%s\n' "$view" | jq . >&2
        exit 1
      fi

      if [ "$(printf '%s\n' "$atts" | wc -l)" -eq 1 ]; then
        ATTACHMENT_ID="$(printf '%s\n' "$atts" | cut -f1)"
      else
        echo "添付が複数あります:" >&2
        printf '%s\n' "$atts" | cut -f2 | sed 's/^/  - /' >&2
        read -rp "Attachment 名: " ATTACHMENT_NAME
        ATTACHMENT_ID="$(printf '%s\n' "$atts" | awk -F'\t' -v n="$ATTACHMENT_NAME" '$2==n{print $1; exit}')"
      fi
      if [ -z "$ATTACHMENT_ID" ]; then
        echo "attachment-id を特定できませんでした。" >&2
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
