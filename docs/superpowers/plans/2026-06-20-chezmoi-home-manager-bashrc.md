# home-manager を chezmoi 管理し .bashrc を home-manager 所有にする 実装プラン

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 既存の flake ベース home-manager 設定を chezmoi 管理下に取り込み、複数 Linux / 将来 macOS へ展開可能にし、`.bashrc` を home-manager 所有へ移行する。

**Architecture:** chezmoi が nix 設定ファイル（flake.nix / flake.lock / home.nix）を素のファイルとして配布し、home-manager が `.bashrc`（`programs.bash`）と mise 有効化（`programs.mise`）を所有する。マシン固有値は nix 側のホスト鍵 flake と `pkgs.stdenv.isDarwin` 分岐で吸収する（chezmoi テンプレートは使わない）。

**Tech Stack:** chezmoi, nix flakes, home-manager, mise, bash

## Global Constraints

- コミットメッセージは日本語。`feat:` / `fix:` / `docs:` プレフィックスを必要に応じて付ける。
- master へ直接 push しない。作業は既存ブランチ `docs/home-manager-bashrc-design` 上で行う。
- コミット本文末尾に `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` を付ける。
- 秘密情報はコミットしない。`.tmpl` に秘密を直書きしない。
- nix ファイルは `.tmpl` にせず素のままコピーする。
- nix コマンドの検証は git リポジトリ内ソースではなく、`chezmoi apply` 後のターゲット `~/.config/home-manager`（非 git）に対して実行する（flake は git 内の未追跡ファイルを無視するため）。
- ドキュメントは日本語・簡潔・絵文字なし。見出し階層を整え、コードブロックに言語指定を付ける。
- `username = "ekuinox"`、`homeDirectory` は Linux `/home/ekuinox` / Darwin `/Users/ekuinox`、`stateVersion = "26.05"`、ホスト鍵は `wsl`（system `x86_64-linux`）。

---

### Task 1: 既存 nix 設定を chezmoi ソースへ取り込む

現状の `~/.config/home-manager/` の 3 ファイルを chezmoi ソースへ無編集で取り込み、ソースとターゲットが一致する状態を作る。

**Files:**
- Create: `dot_config/home-manager/flake.nix`（chezmoi add で生成）
- Create: `dot_config/home-manager/flake.lock`（chezmoi add で生成）
- Create: `dot_config/home-manager/home.nix`（chezmoi add で生成）

**Interfaces:**
- Consumes: なし
- Produces: chezmoi ソース配下に `dot_config/home-manager/{flake.nix,flake.lock,home.nix}`。Task 3/4 がこれらを編集する。

- [ ] **Step 1: 取り込み前の状態を確認**

Run: `ls ~/.config/home-manager/`
Expected: `flake.lock  flake.nix  home.nix` が表示される。

- [ ] **Step 2: 3 ファイルを chezmoi ソースへ取り込む**

Run:
```bash
chezmoi add ~/.config/home-manager/flake.nix ~/.config/home-manager/flake.lock ~/.config/home-manager/home.nix
```

- [ ] **Step 3: ソースに配置されたことを確認**

Run: `ls ~/.dotfiles/dot_config/home-manager/`
Expected: `flake.lock  flake.nix  home.nix` が表示される。

- [ ] **Step 4: chezmoi が管理対象として認識し、差分が無いことを確認**

Run:
```bash
chezmoi managed | grep home-manager
chezmoi diff
```
Expected: `managed` に `.config/home-manager/flake.nix` 等 3 ファイルが出る。`chezmoi diff` の出力に home-manager 関連の差分が無い（ソース == ターゲット）。

- [ ] **Step 5: コミット**

```bash
cd ~/.dotfiles
git add dot_config/home-manager/
git commit -m "feat: home-manager 設定を chezmoi ソースに取り込み

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: chezmoiignore に Windows 除外ブロックを追加

nix/home-manager は Windows 非対象。Windows のときだけ `.config/home-manager` を除外する。

**Files:**
- Modify: `/home/ekuinox/.dotfiles/.chezmoiignore`

**Interfaces:**
- Consumes: Task 1 が配置した `dot_config/home-manager/`
- Produces: なし

- [ ] **Step 1: 追加前のレンダリング結果を確認**

Run: `cd ~/.dotfiles && chezmoi managed | grep home-manager`
Expected: linux 環境なので 3 ファイルが管理対象として出る（除外されていない）。

- [ ] **Step 2: .chezmoiignore に Windows 除外ブロックを追記**

既存の「非 Windows で除外」ブロックの後ろに、別建てで以下を追加する。`.chezmoiignore` 末尾はこうなる:

```text
# リポジトリ付随物（home に展開しない）
README.md
CLAUDE.md
docs
docs/**

# PowerShell プロファイルは Windows 専用。他 OS では無視する
{{ if ne .chezmoi.os "windows" }}
Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1
.claude/init_env.sh
{{ end }}

# nix/home-manager は Windows 非対象。Windows でのみ無視する
{{ if eq .chezmoi.os "windows" }}
.config/home-manager
.config/home-manager/**
{{ end }}
```

- [ ] **Step 3: linux では引き続き管理対象であることを確認**

Run:
```bash
cd ~/.dotfiles
chezmoi managed | grep home-manager
chezmoi execute-template '{{ if eq .chezmoi.os "windows" }}IGNORED{{ else }}MANAGED{{ end }}'
```
Expected: 3 ファイルが管理対象に残る。テンプレート出力は `MANAGED`（この環境は linux のため）。

- [ ] **Step 4: コミット**

```bash
cd ~/.dotfiles
git add .chezmoiignore
git commit -m "feat: chezmoiignore に home-manager の Windows 除外を追加

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: flake.nix をホスト鍵方式に書き換え

単一 `homeConfigurations."ekuinox"` を、system を受け取る `mkHome` ベースのホスト鍵方式へ変更する。

**Files:**
- Modify: `/home/ekuinox/.dotfiles/dot_config/home-manager/flake.nix`

**Interfaces:**
- Consumes: Task 1 の `home.nix`（`./home.nix` として参照、この時点では旧内容のままで可）
- Produces: `homeConfigurations.wsl`（system `x86_64-linux`）。Task 5 が `--flake ~/.config/home-manager#wsl` で参照する。

- [ ] **Step 1: flake.nix を以下の内容に置き換える**

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

- [ ] **Step 2: ソースをターゲットへ反映**

Run: `cd ~/.dotfiles && chezmoi apply ~/.config/home-manager`
Expected: エラー無し。

- [ ] **Step 3: ターゲットで flake 出力に wsl が現れることを確認**

Run: `nix flake show ~/.config/home-manager 2>&1 | grep -i homeConfigurations -A3`
Expected: `homeConfigurations` の下に `wsl` が表示される（旧 home.nix のままでも flake は評価できる）。

- [ ] **Step 4: コミット**

```bash
cd ~/.dotfiles
git add dot_config/home-manager/flake.nix
git commit -m "feat: flake.nix をホスト鍵方式に変更

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: home.nix に OS 分岐 / programs.bash / programs.mise を追加

`.bashrc` を home-manager 所有にし、mise の有効化とシェル統合を宣言する。`homeDirectory` を OS で分岐する。mise の `config.toml` は chezmoi 管理のまま据え置くため `globalConfig` は使わない。

**Files:**
- Modify: `/home/ekuinox/.dotfiles/dot_config/home-manager/home.nix`

**Interfaces:**
- Consumes: Task 3 の `flake.nix`（`homeConfigurations.wsl` から `./home.nix` を読む）
- Produces: `programs.bash.enable = true`（`.bashrc` を生成）、`programs.mise.enable = true`（mise 本体 + bash 統合）

- [ ] **Step 1: home.nix を以下の内容に置き換える**

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
  };
}
```

- [ ] **Step 2: ソースをターゲットへ反映**

Run: `cd ~/.dotfiles && chezmoi apply ~/.config/home-manager`
Expected: エラー無し。

- [ ] **Step 3: home-manager のドライビルドで評価が通ることを確認**

Run: `home-manager build --flake ~/.config/home-manager#wsl 2>&1 | tail -20`
Expected: ビルドが成功し、カレントに `result` シンボリックリンクが生成される（まだ activate はしない）。

- [ ] **Step 4: 生成物に bash / mise の統合が含まれることを確認**

Run:
```bash
grep -l "mise activate bash" result/home-files/.bashrc 2>/dev/null && echo "MISE_OK"
ls -l result/home-files/.bashrc
```
Expected: `.bashrc` に `mise activate bash` が含まれ `MISE_OK` が出る。`result/home-files/.bashrc` が存在する。

- [ ] **Step 5: ドライビルドの result を片付けてコミット**

```bash
rm -f result
cd ~/.dotfiles
git add dot_config/home-manager/home.nix
git commit -m "feat: home.nix に programs.bash / programs.mise / OS 分岐を追加

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: この WSL マシンへ移行適用（home-manager switch）

ターゲットへ反映済みの設定で実際に `.bashrc` を home-manager 所有へ切り替える。既存 `.bashrc` / `.profile` はバックアップへ退避する。これはローカルのマシン状態変更でありコミットは伴わない。

**Files:**
- なし（ローカル home の状態変更のみ）

**Interfaces:**
- Consumes: Task 4 までで `~/.config/home-manager` に反映済みの設定
- Produces: home-manager が所有する `~/.bashrc`（/nix/store へのシンボリックリンク）

- [ ] **Step 1: 切替前の .bashrc が通常ファイルであることを確認**

Run: `ls -l ~/.bashrc ~/.profile`
Expected: いずれも通常ファイル（シンボリックリンクではない）。

- [ ] **Step 2: バックアップ付きで switch する**

Run: `home-manager switch -b bak --flake ~/.config/home-manager#wsl 2>&1 | tail -20`
Expected: `Activating ...` を経て成功で終了。既存ファイルは `~/.bashrc.bak` 等へ退避される。

- [ ] **Step 3: .bashrc が nix store のシンボリックリンクになったことを確認**

Run: `ls -l ~/.bashrc`
Expected: `~/.bashrc -> /nix/store/.../.bashrc` のリンクになっている。

- [ ] **Step 4: 新しい対話シェルで mise が有効化されることを確認**

Run: `bash -lic 'command -v mise && type -t mise' 2>&1 | tail -5`
Expected: mise のパスが表示され、シェル統合が読み込まれている（エラー無く mise が見つかる）。

- [ ] **Step 5: バックアップの存在を確認（記録のみ）**

Run: `ls -l ~/.bashrc.bak ~/.profile.bak 2>&1`
Expected: 退避ファイルが存在する（無い場合は元から対象ファイルが無かっただけで問題ない）。

---

### Task 6: README / CLAUDE.md を更新

管理対象・ブートストラップ・flake.lock ドリフト運用を文書化する。

**Files:**
- Modify: `/home/ekuinox/.dotfiles/README.md`
- Modify: `/home/ekuinox/.dotfiles/CLAUDE.md`

**Interfaces:**
- Consumes: なし
- Produces: なし

- [ ] **Step 1: README の「管理対象」に home-manager を追加**

`README.md` の「## 管理対象」リストへ次の行を追加する（`~/.codex/config.toml` の行の後あたり）:

```markdown
- `~/.config/home-manager/`（nix / home-manager 設定。Linux / macOS のみ）
```

- [ ] **Step 2: README に nix / home-manager のブートストラップ節を追加**

「### Linux / macOS」手順の後（「### 共通の補足」の前）に次の節を追加する:

```markdown
### nix / home-manager（Linux / macOS のみ）

chezmoi 展開後、nix と home-manager を別途セットアップする。

1. nix をインストールする（公式または Determinate インストーラ）。
2. chezmoi 展開で `~/.config/home-manager` が配置済みなので、初回は home-manager を直接実行して反映する。

   ```sh
   nix run home-manager/master -- switch -b bak --flake ~/.config/home-manager#wsl
   ```

3. 2 回目以降は home-manager が PATH に入るため、次で反映する（`<host>` は対象マシンの鍵。現状は `wsl`）。

   ```sh
   home-manager switch --flake ~/.config/home-manager#<host>
   ```

`.bashrc` は home-manager（`programs.bash`）が所有する。既存の `.bashrc` がある初回は `-b bak` で退避される。
```

- [ ] **Step 3: README の「## 日常運用」に flake.lock ドリフトの注意を追加**

「## 日常運用」のコードブロックの後に次を追加する:

```markdown
nix 設定（`~/.config/home-manager`）は通常どおり `chezmoi edit` → `chezmoi apply` で編集・反映する。ただし `nix flake update` は chezmoi の**ターゲット側** `~/.config/home-manager/flake.lock` を書き換えるため、更新後はソースへ取り込み直す。

```
nix flake update --flake ~/.config/home-manager   # lock 更新（ターゲット側）
chezmoi re-add ~/.config/home-manager/flake.lock  # ソースへ取り込み直す
home-manager switch --flake ~/.config/home-manager#<host>
```
```

- [ ] **Step 4: CLAUDE.md の「安全な検証手順」に flake.lock 運用を一行追記**

`CLAUDE.md` の「## 安全な検証手順」の箇条書き末尾に次を追加する:

```markdown
- `nix flake update` で `~/.config/home-manager/flake.lock` を更新したら、`chezmoi re-add` でソースへ取り込み直す（ターゲットのみ更新されソースと乖離するため）。
```

- [ ] **Step 5: 文書のレンダリングを目視確認**

Run: `cd ~/.dotfiles && git diff --stat README.md CLAUDE.md`
Expected: 両ファイルに変更が出る。見出し階層・コードブロック言語指定が崩れていないことを目視で確認する。

- [ ] **Step 6: コミット**

```bash
cd ~/.dotfiles
git add README.md CLAUDE.md
git commit -m "docs: home-manager のブートストラップと flake.lock 運用を追記

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## 完了後

全タスク完了後、ブランチ `docs/home-manager-bashrc-design` を push して PR を作成する（master へ直接 push しない）。PR 本文末尾に規約の Co-Authored-By / Generated-with を付ける。
