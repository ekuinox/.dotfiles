# herdr 導入設計（wsl 限定 / home-manager 集約）

## 背景と目的

herdr（<https://herdr.dev>）は AI コーディングエージェントを複数同時に扱うターミナル
ワークスペース管理ツール（tmux のエージェント版）。これを wsl ホストに導入する。
pi（Raspberry Pi, aarch64）には導入しない。

flake が `packages.<system>.default` を公開しており、これは既存の paseo と同型。
よって paseo と同じ「flake input → `home.packages`」の流儀に乗せる。

## 方針

- 本体（バイナリ）も設定（`~/.config/herdr/config.toml`）も **home-manager に集約**する。
  chezmoi 側には herdr 固有のファイルを置かない（`home-manager` 設定群自体は従来どおり
  chezmoi ソース `dot_config/home-manager/` が source of truth）。
- **wsl 限定**。`home.nix` は全ホスト共通のため、`host == "wsl"` で分岐する。これが
  `home.nix` における初めてのホスト別分岐になる。
- flake input は **リリースタグ固定**（`v0.7.4`、2026-07-15 時点の最新）。
- config は **スターター設定**（documented な最小例をベースに、シェルを bash に変更）。

## ホスト別分岐の仕組み（既存）

`flake.nix` の `hosts`（ホスト名 → system）を `mapAttrs mkHome` で
`homeConfigurations.{wsl,pi}` に展開している。ホスト名は `extraSpecialArgs` の `host` として
`home.nix` に渡り、`hms` エイリアス（`switch --flake ...#${host}`）にも埋め込まれる。
従来 `home.nix` は `host` で分岐しておらず、全ホスト共通だった。

## 変更内容

### `dot_config/home-manager/flake.nix`

- `inputs` に herdr を追加（paseo と同じ注記を付す）:

  ```nix
  herdr.url = "github:ogulcancelik/herdr/v0.7.4";
  ```

- `outputs = { nixpkgs, home-manager, paseo, herdr, ... }:` に `herdr` を追加。
- `extraSpecialArgs` に `herdr = herdr.packages.${system}.default;` を追加。
  pi にも渡るが、`home.nix` が pi では herdr を参照しないため遅延評価で pi ではビルドされない。

### `dot_config/home-manager/home.nix`

- 先頭のパラメータに `herdr` を追加。
- `home.packages` の末尾に条件付きで追加:

  ```nix
  ] ++ lib.optional (host == "wsl") herdr;
  ```

- `home.file` に config を追加（`enable` で wsl だけ生成）:

  ```nix
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
  ```

## 適用手順

1. chezmoi ソース（`flake.nix` / `home.nix`）を編集。
2. `chezmoi diff` で確認 → `chezmoi apply` で `~/.config/home-manager/` へ反映。
3. `hms`（= `home-manager switch --flake ~/.config/home-manager#wsl`）で適用。
   herdr を Rust ビルド（初回は時間がかかる）し、`flake.lock` が更新される。
4. `chezmoi re-add ~/.config/home-manager/flake.lock` で更新後の lock をソースへ戻す。
5. `~/.dotfiles` をブランチで commit（`flake.nix` / `home.nix` / `flake.lock` / 本メモ）。
   master へは直接 push せず PR ベース。
6. 検証: `which herdr` / `herdr --version`、`~/.config/herdr/config.toml` の生成を確認。

## 注意点

- pi では switch しても herdr は評価・ビルドされない。将来 pi にも入れたくなったら
  `host == "wsl"` を条件式（`builtins.elem host [...]` 等）に広げる。
- config は home-manager 生成のため `~/.config/herdr/config.toml` は読み取り専用になる。
  手で書き換えたいときは `home.nix` を編集する運用（containers 設定と同じ）。
- herdr は Rust ビルド（ghostty/zig 依存）。初回 switch のビルドがやや重い。
