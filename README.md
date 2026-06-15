# dotfiles

chezmoi で管理する個人 dotfiles。秘密情報・キャッシュは含めない。

## 管理対象

- `~/.gitconfig`（`[user]` のみ。マシン固有設定は `~/.gitconfig.local` に置く）
- `~/.config/git/ignore`
- `~/.config/mise/config.toml`
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

### 共通の補足

- このリポジトリは private のため、clone には GitHub 認証が必要。`gh auth login` の対話で「Authenticate Git with your GitHub credentials?」に Yes を選ぶと、chezmoi が system の git 経由で認証付き clone できる（このために git も入れている）。
- `sourceDir`（`~/.dotfiles`）はリポジトリの `.chezmoi.toml.tmpl` から `chezmoi init` が自動生成するため、設定の手書きは不要。
- chezmoi 自体は公式インストーラで入る。mise 本体や mise 管理ツール（node, pnpm, claude 等）はこの手順の外なので、必要なら展開後に mise を入れて `mise install` する。

## マシン固有設定

`~/.gitconfig.local` に `[safe]` directory などマシン固有の git 設定を置く（このリポジトリでは管理しない）。

## 日常運用

```
chezmoi edit <file>   # ソースを編集
chezmoi apply         # home へ反映
chezmoi cd            # ソースディレクトリへ移動して git commit / push
```
