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

mise で chezmoi を導入してから展開する:

```
mise use -g chezmoi@latest
chezmoi init --apply git@github.com:ekuinox/dotfiles.git
```

ソースディレクトリを `~/.dotfiles` にしたい場合は、先に `~/.config/chezmoi/chezmoi.toml` に `sourceDir = "~/.dotfiles"` を書いてから `chezmoi init` する。

## マシン固有設定

`~/.gitconfig.local` に `[safe]` directory などマシン固有の git 設定を置く（このリポジトリでは管理しない）。

## 日常運用

```
chezmoi edit <file>   # ソースを編集
chezmoi apply         # home へ反映
chezmoi cd            # ソースディレクトリへ移動して git commit / push
```
