# dotfiles を chezmoi で管理する実装プラン

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Windows + Mac/Linux 混在環境で同期できるよう、選定した設定ファイルを chezmoi（ソース `~/.dotfiles`）で git 管理し、GitHub の private リポジトリへ push する。

**Architecture:** chezmoi のソースディレクトリを `~/.dotfiles` に設定する。`~/.dotfiles` はすでに git リポジトリで、`docs/` に設計書とこのプランを持つ。設定ファイルを `chezmoi add` で取り込み、`.chezmoiignore` でリポジトリ付随物（`docs` 等）の home への展開を防ぎ、PowerShell プロファイルを非 Windows で無視する。秘密情報・キャッシュは取り込まない。

**Tech Stack:** chezmoi, git, GitHub CLI (`gh`), PowerShell 5.1 (Windows), winget

実装前提（確認済みの環境事実）:
- `chezmoi` 未インストール。`winget` `mise` `choco` 利用可。
- `gh` は GitHub アカウント `ekuinox` で認証済み。
- `~/.dotfiles` は `git init -b main` 済みで、`docs/` 配下に設計書とこのプランをコミット済み。
- `~/.gitconfig` は `[user]`（共有したい）と `[safe]`（Windows 絶対パス。マシン固有）が混在。
- `~/.claude/settings.json` は live な Figma トークンを含むため管理対象から除外する（`CLAUDE.md` と `hooks/` のみ管理）。
- 秘密スキャン済みでクリーン: `~/.config/mise/config.toml`, `~/.codex/config.toml`, `~/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1`。

最終的な管理対象:
- `~/.gitconfig`（`[user]` + `[include]` に再構成）
- `~/.config/git/ignore`
- `~/.config/mise/config.toml`
- `~/.codex/config.toml`
- `~/.claude/CLAUDE.md`
- `~/.claude/hooks/`（`toast-start.ps1`, `toast-stop.ps1`）
- `~/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1`（非 Windows では無視）

管理対象外（home に残すがリポジトリには入れない）:
- `~/.gitconfig.local`（`[safe]` 等マシン固有設定の退避先）
- `~/.config/chezmoi/chezmoi.toml`（chezmoi のローカル設定）

---

### Task 1: chezmoi をインストールする

**Files:**
- 変更なし（ツール導入のみ）

- [ ] **Step 1: winget で chezmoi をインストール**

Run:
```powershell
winget install --id twpayne.chezmoi --source winget --accept-package-agreements --accept-source-agreements
```
Expected: `Successfully installed` で終了。

- [ ] **Step 2: 新しいシェルでバージョン確認**

PATH を反映するため新しい PowerShell を開いてから:
```powershell
chezmoi --version
```
Expected: `chezmoi version v2.x.x ...` のような行が表示される。`chezmoi : 用語 ... 認識されません` の場合は PATH 反映のためシェルを開き直す。

---

### Task 2: chezmoi のソースディレクトリを `~/.dotfiles` に設定する

**Files:**
- Create: `~/.config/chezmoi/chezmoi.toml`（マシン固有・リポジトリ対象外）

- [ ] **Step 1: chezmoi 設定ディレクトリを作成**

Run:
```powershell
New-Item -ItemType Directory -Force "$HOME/.config/chezmoi" | Out-Null
```
Expected: エラーなく完了。

- [ ] **Step 2: `~/.config/chezmoi/chezmoi.toml` を作成**

次の内容で作成する:
```toml
sourceDir = "~/.dotfiles"
```

- [ ] **Step 3: ソースパスが `~/.dotfiles` を指すか確認**

Run:
```powershell
chezmoi source-path
```
Expected: `C:\Users\ekuinox\.dotfiles` が出力される。別パス（例: `...\.local\share\chezmoi`）が出る場合は設定ファイルが読まれていないので、`chezmoi source-path --debug` で探索パスを確認し、表示された設定探索先に `chezmoi.toml` を置き直す。

---

### Task 3: `.chezmoiignore` を作成してリポジトリ付随物の展開を防ぐ

`~/.dotfiles` 全体が chezmoi のソースとして home にマッピングされる。`docs/` や `README.md` をそのままにすると `~/docs` 等が作られてしまうため除外する。PowerShell プロファイルは Windows 専用なので非 Windows では無視する。

**Files:**
- Create: `~/.dotfiles/.chezmoiignore`

- [ ] **Step 1: `~/.dotfiles/.chezmoiignore` を作成**

次の内容で作成する:
```
# リポジトリ付随物（home に展開しない）
README.md
docs
docs/**

# PowerShell プロファイルは Windows 専用。他 OS では無視する
{{ if ne .chezmoi.os "windows" }}
Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1
{{ end }}
```

- [ ] **Step 2: 管理対象がまだ空（docs が混ざらない）ことを確認**

Run:
```powershell
chezmoi managed
```
Expected: 何も出力されない（まだ何も `add` していないため）。`docs` や `docs/...` が出る場合は `.chezmoiignore` のパターンを見直す。

- [ ] **Step 3: コミット**

```powershell
git -C "$HOME/.dotfiles" add .chezmoiignore
git -C "$HOME/.dotfiles" commit -m "chore: chezmoi の .chezmoiignore を追加" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `.gitconfig` を include 方式に再構成して取り込む

`[user]` のみ共有し、`[safe]` 等マシン固有設定は管理対象外の `~/.gitconfig.local` に退避する。

**Files:**
- Create: `~/.gitconfig.local`（マシン固有・リポジトリ対象外）
- Modify: `~/.gitconfig`
- 取り込み: `~/.dotfiles/dot_gitconfig`（`chezmoi add` が生成）

- [ ] **Step 1: `~/.gitconfig.local` を作成し `[safe]` を退避**

次の内容で作成する（現状の `~/.gitconfig` の `[safe]` ブロックをそのまま移す）:
```ini
[safe]
	directory = C:/Users/ekuinox/Documents/works/repos/git/ekuinox/gmail-archiver
	directory = C:/Users/ekuinox/Documents/works/repos/temp/plotter
```

- [ ] **Step 2: `~/.gitconfig` を共有用に書き換え**

次の内容で上書きする:
```ini
[user]
	email = depkey@me.com
	name = ekuinox

[include]
	path = ~/.gitconfig.local
```

- [ ] **Step 3: include が効いて従来の設定が読めることを確認**

Run:
```powershell
git config --get user.email
git config --show-origin --get-all safe.directory
```
Expected: 1 行目に `depkey@me.com`。2 行目以降に 2 つの `safe.directory` が表示され、origin が `.gitconfig.local`（例: `file:C:/Users/ekuinox/.gitconfig.local`）になっている。

- [ ] **Step 4: chezmoi に取り込む**

Run:
```powershell
chezmoi add "$HOME/.gitconfig"
```
Expected: エラーなく完了。`~/.dotfiles/dot_gitconfig` が作られる。

- [ ] **Step 5: 差分ゼロかつ `.gitconfig.local` が未管理であることを確認**

Run:
```powershell
chezmoi diff
chezmoi managed
```
Expected: `chezmoi diff` は空（ソースと home が一致）。`chezmoi managed` に `.gitconfig` が含まれ、`.gitconfig.local` は含まれない。

- [ ] **Step 6: 取り込んだ `dot_gitconfig` に秘密や `[safe]` が無いことを確認**

Run:
```powershell
chezmoi cat "$HOME/.gitconfig"
```
Expected: `[user]` と `[include]` のみ。`[safe]` や絶対パスが含まれていない。

- [ ] **Step 7: コミット**

```powershell
git -C "$HOME/.dotfiles" add dot_gitconfig
git -C "$HOME/.dotfiles" commit -m "feat: .gitconfig を chezmoi で管理（include 方式）" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `.config/git/ignore` と `.config/mise/config.toml` を取り込む

**Files:**
- 取り込み: `~/.dotfiles/dot_config/git/ignore`
- 取り込み: `~/.dotfiles/dot_config/mise/config.toml`

- [ ] **Step 1: chezmoi に取り込む**

Run:
```powershell
chezmoi add "$HOME/.config/git/ignore" "$HOME/.config/mise/config.toml"
```
Expected: エラーなく完了。

- [ ] **Step 2: 取り込み結果を確認**

Run:
```powershell
chezmoi managed
chezmoi diff
```
Expected: `chezmoi managed` に `.config/git/ignore` と `.config/mise/config.toml` が現れる。`chezmoi diff` は空。

- [ ] **Step 3: コミット**

```powershell
git -C "$HOME/.dotfiles" add dot_config
git -C "$HOME/.dotfiles" commit -m "feat: .config/git/ignore と mise 設定を chezmoi で管理" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: `.codex/config.toml` を取り込む

`~/.codex` は `auth.json` や各種 sqlite/ログを含むため、`config.toml` のみを個別指定で取り込む。

**Files:**
- 取り込み: `~/.dotfiles/dot_codex/config.toml`

- [ ] **Step 1: config.toml のみ取り込む**

Run:
```powershell
chezmoi add "$HOME/.codex/config.toml"
```
Expected: エラーなく完了。

- [ ] **Step 2: codex の秘密ファイルが取り込まれていないことを確認**

Run:
```powershell
chezmoi managed | Select-String "codex"
```
Expected: `.codex/config.toml` の 1 行のみ。`auth.json` や `*.sqlite` が出ないこと。

- [ ] **Step 3: コミット**

```powershell
git -C "$HOME/.dotfiles" add dot_codex
git -C "$HOME/.dotfiles" commit -m "feat: .codex/config.toml を chezmoi で管理" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: `.claude` の `CLAUDE.md` と `hooks/` を取り込む

`~/.claude` は `.credentials.json` `history.jsonl` `config.json` 等の秘密/状態ファイルを含むため、`CLAUDE.md` と `hooks/` のみを個別指定で取り込む。`settings.json`（Figma トークンを含む）と `settings.local.json` は取り込まない。

**Files:**
- 取り込み: `~/.dotfiles/dot_claude/CLAUDE.md`
- 取り込み: `~/.dotfiles/dot_claude/hooks/toast-start.ps1`, `~/.dotfiles/dot_claude/hooks/toast-stop.ps1`

- [ ] **Step 1: CLAUDE.md と hooks ディレクトリを取り込む**

Run:
```powershell
chezmoi add "$HOME/.claude/CLAUDE.md" "$HOME/.claude/hooks"
```
Expected: エラーなく完了。

- [ ] **Step 2: 秘密/状態ファイルが取り込まれていないことを確認**

Run:
```powershell
chezmoi managed | Select-String "claude"
```
Expected: `.claude/CLAUDE.md`, `.claude/hooks/toast-start.ps1`, `.claude/hooks/toast-stop.ps1` の 3 行のみ。`settings.json` `settings.local.json` `.credentials.json` `history.jsonl` `config.json` が含まれないこと。

- [ ] **Step 3: コミット**

```powershell
git -C "$HOME/.dotfiles" add dot_claude
git -C "$HOME/.dotfiles" commit -m "feat: .claude の CLAUDE.md と hooks を chezmoi で管理" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: PowerShell プロファイルを取り込む

`.chezmoiignore`（Task 3）で非 Windows では無視される。Windows では管理対象になる。

**Files:**
- 取り込み: `~/.dotfiles/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1`

- [ ] **Step 1: プロファイルを取り込む**

Run:
```powershell
chezmoi add "$HOME/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1"
```
Expected: エラーなく完了。

- [ ] **Step 2: 取り込み結果を確認**

Run:
```powershell
chezmoi managed | Select-String "WindowsPowerShell"
chezmoi diff
```
Expected: `Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1` が 1 行表示される。`chezmoi diff` は空。

- [ ] **Step 3: コミット**

```powershell
git -C "$HOME/.dotfiles" add Documents
git -C "$HOME/.dotfiles" commit -m "feat: PowerShell プロファイルを chezmoi で管理（Windows 専用）" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: README に新マシンのブートストラップ手順を書く

複数マシン同期が目的なので、新マシンでの展開手順をリポジトリに残す。

**Files:**
- Create: `~/.dotfiles/README.md`

- [ ] **Step 1: `~/.dotfiles/README.md` を作成**

次の内容で作成する（内側のコードフェンスは実際には三連バッククォート ``` で書く。下では外側を `~~~` にして表現している）:
~~~markdown
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

chezmoi をインストール後:

```
chezmoi init --apply git@github.com:ekuinox/dotfiles.git
```

ソースディレクトリを `~/.dotfiles` にしたい場合は、先に `~/.config/chezmoi/chezmoi.toml` に
`sourceDir = "~/.dotfiles"` を書いてから `chezmoi init` する。

## マシン固有設定

`~/.gitconfig.local` に `[safe]` directory などマシン固有の git 設定を置く（このリポジトリでは管理しない）。

## 日常運用

```
chezmoi edit <file>   # ソースを編集
chezmoi apply         # home へ反映
chezmoi cd            # ソースディレクトリへ移動して git commit / push
```
~~~

- [ ] **Step 2: コミット**

```powershell
git -C "$HOME/.dotfiles" add README.md
git -C "$HOME/.dotfiles" commit -m "docs: README にブートストラップ手順を追加" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: 秘密スキャン後、GitHub に private リポジトリを作成して push する

**Files:**
- 変更なし（リモート作成と push のみ）

- [ ] **Step 1: 管理対象一覧を目視確認**

Run:
```powershell
chezmoi managed
```
Expected: 次の 7 エントリのみ（パス区切りは環境により `/` 表示）。秘密ファイル（`auth.json` `settings.json` `.credentials.json` `*.sqlite` 等）が無いこと。
```
.claude/CLAUDE.md
.claude/hooks/toast-start.ps1
.claude/hooks/toast-stop.ps1
.codex/config.toml
.config/git/ignore
.config/mise/config.toml
.gitconfig
Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1
```
（`Documents/...` を入れて 8 行。Windows での実行時。）

- [ ] **Step 2: ソースを秘密パターンで grep**

Run:
```powershell
git -C "$HOME/.dotfiles" grep -n -I -E -i "api[_-]?key|secret|token|password|passwd|bearer|sk-|ghp_|figd_|client[_-]?secret|BEGIN (RSA|OPENSSH|PRIVATE)"
```
Expected: マッチなし（終了コード 1）。`.chezmoiignore` のコメント語などの良性マッチが出た場合は内容を目視し、実トークンでないことを確認する。実トークンが出た場合はそのファイルを `chezmoi forget` で外して原因を取り除くまで push しない。

- [ ] **Step 3: GitHub に private リポジトリを作成して push**

Run:
```powershell
gh repo create dotfiles --private --source "$HOME/.dotfiles" --remote origin --push
```
Expected: `Created repository ekuinox/dotfiles on GitHub` と push 成功のメッセージ。

- [ ] **Step 4: リモートと push 内容を確認**

Run:
```powershell
git -C "$HOME/.dotfiles" remote -v
git -C "$HOME/.dotfiles" log --oneline origin/main -1
```
Expected: `origin` が `github.com/ekuinox/dotfiles`（fetch/push）。`origin/main` の最新コミットがローカルと一致。

- [ ] **Step 5: GitHub 上に秘密が無いことを最終確認**

Run:
```powershell
gh repo view ekuinox/dotfiles --web
```
Expected: ブラウザで private リポジトリが開く。`dot_claude` に `settings.json` が無いこと、`dot_gitconfig` に `[safe]` やトークンが無いことを目視確認する。

---

## 完了の定義

- `chezmoi managed` が上記 8 エントリのみを示し、秘密ファイルを含まない。
- `chezmoi diff` が空（ソースと home が一致）。
- `git -C ~/.dotfiles grep` の秘密スキャンでマッチなし。
- GitHub の private リポジトリ `ekuinox/dotfiles` に push 済みで、`origin/main` がローカルと一致。
- `~/.gitconfig.local`（`[safe]`）と `~/.config/chezmoi/chezmoi.toml` は管理対象外のまま home に存在する。
