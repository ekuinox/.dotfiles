# dotfiles

chezmoi で管理する個人 dotfiles。秘密情報・キャッシュは含めない。

## 管理対象

- `~/.gitconfig`（`[user]` のみ。マシン固有設定は `~/.gitconfig.local` に置く）
- `~/.config/git/ignore`
- `~/.config/home-manager/`（nix / home-manager 設定。Linux / macOS のみ）
- `~/.config/nix/nix.conf`（flakes 有効化。Linux / macOS のみ）
- `~/.codex/config.toml`
- `~/.claude/CLAUDE.md`, `~/.claude/hooks/`
- `~/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1`（Windows のみ）

## 新マシンでの展開

OS ごとに以下を上から順に実行する（コピペでよい）。

### Windows

```powershell
# 1. git と gh を入れる（Windows 11 標準の winget）
winget install --id Git.Git -e
winget install --id GitHub.cli -e

# 2. GitHub にログインする（ブラウザ認証。途中の git 認証連携は Yes を選ぶ）
gh auth login

# 3. chezmoi を入れて一気に展開する
iex "&{$(irm 'https://get.chezmoi.io/ps1')} -- init --apply --source ~/.dotfiles ekuinox/.dotfiles"
```

### Linux / macOS

```sh
# 1. git と gh を入れる（ディストリ/OS に合わせる）
#   Debian/Ubuntu/Raspberry Pi OS:  sudo apt update && sudo apt install -y git gh
#   Fedora:                          sudo dnf install -y git gh
#   Arch:                            sudo pacman -S --needed git github-cli
#   macOS (Homebrew):                brew install git gh

# 2. GitHub にログインする（ブラウザ認証。途中の git 認証連携は Yes を選ぶ）
gh auth login

# 3. chezmoi を ~/.local/bin に入れて一気に展開する
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply --source ~/.dotfiles ekuinox/.dotfiles
```

- `~/.local/bin` が PATH に無い環境では、展開後に `export PATH="$HOME/.local/bin:$PATH"` をシェルの rc に追加する（次回以降の `chezmoi` コマンド用。`chezmoi apply` 自体は上記一発で完了している）。
- Windows 固有の設定（PowerShell プロファイル、`~/.claude/settings.json` の toast フック・`defaultShell` 等）は `.chezmoiignore` と `*.tmpl` の OS 分岐により、Linux / macOS では自動的に除外される。

### nix / home-manager（Linux / macOS のみ）

chezmoi 展開後、nix と home-manager を別途セットアップする。

1. nix をインストールする（公式または Determinate インストーラ）。
2. chezmoi 展開で `~/.config/nix/nix.conf`（flakes 有効化）と `~/.config/home-manager` が配置済みなので、初回は home-manager を直接実行して反映する。flakes は nix.conf で有効化済みのため `--extra-experimental-features` は不要。

   ```sh
   nix run home-manager/master -- switch -b bak --flake ~/.config/home-manager#wsl
   ```

3. 2 回目以降は home-manager が PATH に入るため、次で反映する（`<host>` は対象マシンの鍵。現状は `wsl`）。

   ```sh
   home-manager switch --flake ~/.config/home-manager#<host>
   ```

`.bashrc` は home-manager（`programs.bash`）が所有する。既存の `.bashrc` がある初回は `-b bak` で退避される。

### 共通の補足

- このリポジトリは private のため、clone には GitHub 認証が必要。`gh auth login` の対話で「Authenticate Git with your GitHub credentials?」に Yes を選ぶと、chezmoi が system の git 経由で認証付き clone できる（このために git も入れている）。
- `sourceDir`（`~/.dotfiles`）はリポジトリの `.chezmoi.toml.tmpl` から `chezmoi init` が自動生成するため、設定の手書きは不要。
- 初回の chezmoi 自体は公式インストーラで入る（ブートストラップ用）。Linux / macOS では claude-code と chezmoi を home-manager（nix）が `home.packages` で管理するため、`home-manager switch` 後は nix 側の chezmoi も利用できる。
- mise 本体は home-manager（`programs.mise`）が入れるが、グローバルの tool バージョンは固定しない方針のため mise の `config.toml` は chezmoi 管理対象外。node 等が必要ならプロジェクト単位の `mise.toml` 等で都度入れる。

## マシン固有設定

`~/.gitconfig.local` に `[safe]` directory などマシン固有の git 設定を置く（このリポジトリでは管理しない）。

## 日常運用

```
chezmoi edit <file>   # ソースを編集
chezmoi apply         # home へ反映
chezmoi cd            # ソースディレクトリへ移動して git commit / push
```

nix 設定（`~/.config/home-manager`）は通常どおり `chezmoi edit` → `chezmoi apply` で編集・反映する。ただし `nix flake update` は chezmoi の**ターゲット側** `~/.config/home-manager/flake.lock` を書き換えるため、更新後はソースへ取り込み直す。

```sh
nix flake update --flake ~/.config/home-manager   # lock 更新（ターゲット側）
chezmoi re-add ~/.config/home-manager/flake.lock  # ソースへ取り込み直す
home-manager switch --flake ~/.config/home-manager#<host>
```
