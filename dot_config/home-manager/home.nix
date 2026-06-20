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
  # 対象は fzf で vault -> item -> attachment と絞り込んで選ぶ。
  gog-setup-credentials = pkgs.writeShellApplication {
    name = "gog-setup-credentials";
    runtimeInputs = [ pkgs.proton-pass-cli pkgs.gogcli pkgs.jq pkgs.fzf pkgs.coreutils ];
    text = ''
      # pass-cli ログイン確認（vault/item 取得・download に必要）
      if ! pass-cli test >/dev/null 2>&1; then
        echo "pass-cli が未ログインです。先に 'pass-cli login' を実行してください。" >&2
        exit 1
      fi

      # fzf で vault -> item -> attachment と絞り込む
      vault_obj="$(pass-cli vault list --output json \
        | jq -r '.vaults[] | "\(.name)\t\(tojson)"' \
        | fzf --delimiter='\t' --with-nth=1 --prompt='Vault> ' | cut -f2- || true)"
      [ -n "$vault_obj" ] || { echo "vault が選択されませんでした。" >&2; exit 1; }
      SHARE_ID="$(printf '%s' "$vault_obj" | jq -r '.shareId // .id')"

      item_obj="$(pass-cli item list --share-id "$SHARE_ID" --output json \
        | jq -r '.items[] | "\(.title)\t\(tojson)"' \
        | fzf --delimiter='\t' --with-nth=1 --prompt='Item> ' | cut -f2- || true)"
      [ -n "$item_obj" ] || { echo "item が選択されませんでした。" >&2; exit 1; }
      ITEM_ID="$(printf '%s' "$item_obj" | jq -r '.id')"

      view="$(pass-cli item view --share-id "$SHARE_ID" --item-id "$ITEM_ID" --output json)"
      att_obj="$(printf '%s' "$view" \
        | jq -r '(.attachments // .files // [])[] | "\(.name // .fileName // .id)\t\(tojson)"' \
        | fzf --delimiter='\t' --with-nth=1 --prompt='Attachment> ' | cut -f2- || true)"
      if [ -z "$att_obj" ]; then
        echo "attachment が選択されませんでした（この item に添付が無い可能性）。view JSON:" >&2
        printf '%s\n' "$view" | jq . >&2
        exit 1
      fi
      ATTACHMENT_ID="$(printf '%s' "$att_obj" | jq -r '.id // .attachmentId')"

      # 短命な一時ファイル（tmpfs 優先）へ取得し、登録後に確実に消す
      tmpdir="''${XDG_RUNTIME_DIR:-/tmp}"
      tmp="$(mktemp "$tmpdir/gog-cred.XXXXXX")"
      trap 'shred -u "$tmp" 2>/dev/null || rm -f "$tmp"' EXIT

      pass-cli item attachment download \
        --share-id "$SHARE_ID" --item-id "$ITEM_ID" --attachment-id "$ATTACHMENT_ID" \
        --output "$tmp"

      gog auth credentials set "$tmp"

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
