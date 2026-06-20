# nix home-manager を chezmoi で管理し .bashrc を home-manager 所有にする設計

作成日: 2026-06-20

## 目的

既存の flake ベース home-manager 設定（`~/.config/home-manager/`）を chezmoi の管理対象に取り込み、複数 Linux マシン（将来 macOS も）へ展開できるようにする。あわせて `.bashrc` を home-manager（`programs.bash`）の所有に切り替え、宣言的に管理する。

## 前提・現状

- このリポジトリ自体が chezmoi の source ディレクトリ（`~/.dotfiles`）。クロス OS（Windows は PowerShell、Linux/macOS は OS 分岐）で運用している。
- この WSL マシンには nix と home-manager が導入済みで、`~/.config/home-manager/` に flake ベース設定（`flake.nix` / `flake.lock` / `home.nix`）が存在する。`home.nix` は `pkgs.claude-code` と `pkgs.mise` を導入している。
- `~/.bashrc` はほぼ Ubuntu 標準のまま。
- `dot_config/mise/config.toml` は既に chezmoi 管理で、全 OS 共通の単一ソースとして tool（claude / node / pnpm / yarn / chezmoi）を定義している。
- chezmoi の OS 判定: WSL 内では Linux バイナリとして動くため `.chezmoi.os` は `linux`。`windows` になるのはネイティブ Windows の `chezmoi.exe` のときだけ。よって `eq .chezmoi.os "windows"` ゲートは WSL を正しく除外できる。

## 確定した方針

### 所有権の分離

- `.bashrc` の所有者は **home-manager**（`programs.bash`）。chezmoi は `.bashrc` を直接管理しない。両者が同一ファイルを管理すると競合するため、所有者は一つに絞る。
- nix 設定ファイル（flake / home.nix）は **chezmoi** が配布する（素のファイルとしてコピー、`.tmpl` にしない）。
- mise の設定内容（`config.toml`）は **chezmoi** が全 OS 共通で管理。mise の有効化・シェル統合は **home-manager**（`programs.mise`）が担う。`globalConfig` は使わない（使うと chezmoi 管理の config.toml と所有権が衝突し、かつ nix 側と二重管理になるため）。

### マシン固有値の注入: 純 nix・ホスト鍵方式（A 案）

chezmoi のテンプレートで nix を生成するのではなく、nix 側でパラメータ化する。`flake.nix` が host ごとの `homeConfigurations` を列挙し、各々に `system` を渡す。`home.nix` は `pkgs.stdenv.isDarwin` で OS 差分を分岐する。chezmoi は nix ファイルを素のままコピーする。

理由:

- nix を正典に保ち、flake 単体で再現・利用できる（chezmoi のレンダリング無しでも `home-manager switch --flake github:...` が動く）。
- chezmoi の `{{ }}` と nix の `${ }` が同一ファイルに混在する二重テンプレートを避けられる。OS 分岐は nix 本来の得意分野。

## ファイル配置（chezmoi ソース）

`~/.config/home-manager/` を `chezmoi add` で取り込み、以下に配置する。

```text
dot_config/home-manager/
  flake.nix      # ホスト鍵方式に書き換え
  flake.lock     # 再現性のため管理対象に含める
  home.nix       # programs.bash / programs.mise / OS 分岐を追加
```

`home-manager switch` は `~/.config/home-manager` を自動検出するため、配置は標準のまま。

## nix 設定の内容

### flake.nix（ホスト鍵方式）

```nix
{
  description = "Home Manager configuration of ekuinox";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      mkHome = system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ ./home.nix ];
        };
    in {
      homeConfigurations = {
        wsl = mkHome "x86_64-linux";
        # 将来: mac = mkHome "aarch64-darwin";
      };
    };
}
```

適用は `home-manager switch --flake ~/.config/home-manager#wsl`。マシン追加時は `homeConfigurations` に 1 行追加する。

### home.nix（OS 分岐 + programs.bash + programs.mise）

```nix
{ config, pkgs, lib, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "claude-code" ];

  home = {
    username = "ekuinox";
    homeDirectory =
      if pkgs.stdenv.isDarwin then "/Users/ekuinox" else "/home/ekuinox";
    stateVersion = "26.05";
    packages = [ pkgs.claude-code ];
    sessionVariables = { };
  };

  programs = {
    home-manager.enable = true;

    bash = {
      enable = true;                       # .bashrc を home-manager が所有
      historyControl = [ "ignoredups" "ignorespace" ];
      historySize = 10000;
      historyFileSize = 20000;
      shellOptions = [ "histappend" "checkwinsize" ];
      # enableCompletion はデフォルト true（nix の bash-completion を読み込む）
      shellAliases = {
        # 例: ll = "ls -alF";
      };
      # initExtra は不要（mise の統合は programs.mise が吐く）
    };

    mise = {
      enable = true;                 # mise 本体を導入
      enableBashIntegration = true;  # 既定 true。.bashrc に activate を自動挿入
      # globalConfig は使わない（config.toml は chezmoi 管理に一本化）
    };
  };
}
```

補足:

- nix / home-manager の session 変数の読み込みは `programs.bash.enable = true` で自動的に `.bashrc` に書き込まれる。手動の source 行は不要。
- Ubuntu 標準 `.bashrc` の有用部分（history 制御 / `checkwinsize` / bash 補完）は対応する option に置き換える。プロンプトは当面 home-manager 既定のまま。必要になれば `initExtra` か starship 等で拡張する。

## 既知の重複（スコープ外）

`home.packages` の `pkgs.claude-code` と、chezmoi 管理 `config.toml` の mise `claude` tool により、Linux/macOS では claude が nix と mise の両方で導入される。これは本作業以前からの状態であり、本設計では現状維持としてスコープ外に置く。将来どちらか一方へ寄せる場合は別途検討する。

## chezmoiignore（Windows 除外）

nix/home-manager は Windows 非対象。Windows のときだけ `.config/home-manager` を除外するブロックを追加する（既存の「非 Windows で除外」ブロックとは別建て）。

```text
{{ if eq .chezmoi.os "windows" }}
.config/home-manager
.config/home-manager/**
{{ end }}
```

mise の `config.toml` は全 OS で展開するため、ignore には追加しない（現状維持）。

## 移行手順（この WSL マシン）

1. ソース取り込み: `chezmoi add ~/.config/home-manager/flake.nix ~/.config/home-manager/flake.lock ~/.config/home-manager/home.nix`
2. 取り込んだ `dot_config/home-manager/` を本書の最終形に編集
3. `chezmoi apply` で `~/.config/home-manager` を更新
4. 既存 `.bashrc` / `.profile` は home-manager 管理外で「邪魔」判定され switch が失敗するため、バックアップ付きで切替: `home-manager switch -b bak --flake ~/.config/home-manager#wsl`
5. 新しいシェルで `.bashrc` が `/nix/store` へのシンボリックリンクになり、mise が有効化されることを確認

## 新マシンでのブートストラップ（Linux / macOS）

nix と home-manager は mise 同様、chezmoi 手順の外側でインストールする。README に追記する。順序:

1. nix をインストール（公式 or Determinate インストーラ）
2. 既存手順どおり `gh auth login` → chezmoi で `init --apply`（`~/.config/home-manager` が配置される）
3. 初回は home-manager 未導入のため `nix run home-manager/master -- switch -b bak --flake ~/.config/home-manager#wsl`。以降は `home-manager switch --flake ~/.config/home-manager#<host>`

## 日常運用の注意（flake.lock ドリフト）

`nix flake update` は chezmoi の **ターゲット側** `~/.config/home-manager/flake.lock` を書き換えるため、ソースと乖離する。更新後は `chezmoi re-add ~/.config/home-manager/flake.lock`（または `chezmoi add`）でソースへ取り込み直す。nix ファイルの編集自体は通常どおり `chezmoi edit` → `chezmoi apply`。

## 検証

- `chezmoi diff` と `chezmoi apply --dry-run` で chezmoi 差分を確認
- `home-manager build --flake ~/.config/home-manager#wsl` でドライビルド
- `switch` 後、新シェルで `.bashrc` の symlink 化・mise activation・bash 補完を実機確認

## ドキュメント更新

- README の「管理対象」に `~/.config/home-manager/`（nix/home-manager 設定）を追加し、nix/home-manager のブートストラップ節を新設
- CLAUDE.md / README に flake.lock ドリフト運用の注意を追記
- 追記はリポジトリ方針（日本語・簡潔・絵文字なし、見出し階層・コードブロック言語指定）に従う
