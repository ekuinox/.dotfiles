# 新マシン展開の簡略化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新マシンでの dotfiles 展開を「winget で git/gh 導入 → gh ログイン → chezmoi 公式インストーラのコピペ1発」に簡略化する。

**Architecture:** リポジトリ直下に `.chezmoi.toml.tmpl` を追加し、`chezmoi init` がクローン後に `~/.config/chezmoi/chezmoi.toml` を自動生成して `sourceDir = "~/.dotfiles"` を永続化する。これにより手書きの設定作成が不要になる。README の「新マシンでの展開」を新手順に差し替え、あわせて誤記（`dotfiles`／SSH 前提）を実態（`.dotfiles`／gh 認証）へ修正する。

**Tech Stack:** chezmoi v2（Go template）、gh CLI、winget、PowerShell。

参照スペック: `docs/superpowers/specs/2026-06-14-simplify-bootstrap-design.md`

---

### Task 1: `.chezmoi.toml.tmpl` を追加して sourceDir を永続化する

**Files:**
- Create: `C:\Users\ekuinox\.dotfiles\.chezmoi.toml.tmpl`

- [ ] **Step 1: テンプレートファイルを作成**

`C:\Users\ekuinox\.dotfiles\.chezmoi.toml.tmpl` を以下の内容で新規作成する。

```toml
sourceDir = "~/.dotfiles"
```

- [ ] **Step 2: テンプレートが正しくレンダリングされることを確認**

chezmoi のテンプレートエンジンで構文エラーが無いことを確認する。
`execute-template` は現在の設定・state を変更しない読み取り専用コマンド。

Run:
```bash
chezmoi execute-template < ~/.dotfiles/.chezmoi.toml.tmpl
```
Expected: 次の1行がそのまま出力される（テンプレート関数を使っていないため素通し）。
```
sourceDir = "~/.dotfiles"
```
エラー（`template: ...` のような出力）が出ないこと。

- [ ] **Step 3: chezmoi がこのファイルを home へ展開しないことを確認**

`.chezmoi.toml.tmpl` は chezmoi の特殊ファイルで、managed なターゲットには含まれない。

Run:
```bash
chezmoi managed | grep -i chezmoi.toml
```
Expected: 何も出力されない（grep がマッチ0で終了）。`.config/chezmoi/...` 等が
managed 一覧に出てこないこと。

- [ ] **Step 4: コミット**

```bash
cd ~/.dotfiles
git add .chezmoi.toml.tmpl
git commit -m "feat: .chezmoi.toml.tmpl で sourceDir を管理し chezmoi.toml 手書きを廃止"
```

---

### Task 2: README の「新マシンでの展開」を新手順へ差し替える

**Files:**
- Modify: `C:\Users\ekuinox\.dotfiles\README.md`（14-23 行目「## 新マシンでの展開」節）

- [ ] **Step 1: 現状の該当節を確認**

Run:
```bash
sed -n '14,23p' ~/.dotfiles/README.md
```
Expected: 以下が表示される（これから置き換える対象）。
```
## 新マシンでの展開

mise で chezmoi を導入してから展開する:

```
mise use -g chezmoi@latest
chezmoi init --apply git@github.com:ekuinox/dotfiles.git
```

ソースディレクトリを `~/.dotfiles` にしたい場合は、先に `~/.config/chezmoi/chezmoi.toml` に `sourceDir = "~/.dotfiles"` を書いてから `chezmoi init` する。
```

- [ ] **Step 2: 「## 新マシンでの展開」節を以下で全置換**

`## 新マシンでの展開` の見出しから、その節の最後の段落
（`ソースディレクトリを ~/.dotfiles にしたい場合は…` の行）までを、次の内容に置き換える。
直後の `## マシン固有設定` の見出しはそのまま残すこと。

````markdown
## 新マシンでの展開

Windows の新マシンで、以下を上から順に実行する（コピペでよい）。

```powershell
# 1. git と gh を入れる（Windows 11 標準の winget）
winget install Git.Git GitHub.cli

# 2. GitHub にログインする（ブラウザ認証。途中の git 認証連携は Yes を選ぶ）
gh auth login

# 3. chezmoi を入れて一気に展開する
iex "&{$(irm 'https://get.chezmoi.io/ps1')} -- init --apply --source ~/.dotfiles ekuinox/.dotfiles"
```

- このリポジトリは private のため、clone には GitHub 認証が必要。`gh auth login` の
  対話で「Authenticate Git with your GitHub credentials?」に Yes を選ぶと、chezmoi が
  system の git 経由で認証付き clone できる（このために git も入れている）。
- `sourceDir`（`~/.dotfiles`）はリポジトリの `.chezmoi.toml.tmpl` から
  `chezmoi init` が自動生成するため、設定の手書きは不要。
- chezmoi 自体は公式インストーラで入る。mise 本体や mise 管理ツール（node, pnpm,
  claude 等）はこの手順の外なので、必要なら展開後に mise を入れて `mise install` する。
````

- [ ] **Step 3: 古い記述が残っていないことを確認**

Run:
```bash
grep -nE 'mise use -g chezmoi|git@github.com:ekuinox/dotfiles|chezmoi\.toml.*sourceDir' ~/.dotfiles/README.md
```
Expected: 何も出力されない（旧手順・SSH 前提・手書き sourceDir の記述が消えている）。

- [ ] **Step 4: 新手順が入っていることを確認**

Run:
```bash
grep -nE 'winget install Git.Git GitHub.cli|gh auth login|get.chezmoi.io/ps1|ekuinox/\.dotfiles' ~/.dotfiles/README.md
```
Expected: 4 行すべてマッチして表示される。

- [ ] **Step 5: コミット**

```bash
cd ~/.dotfiles
git add README.md
git commit -m "docs: 新マシン展開手順を gh 認証＋chezmoi 公式インストーラのコピペ1発に簡略化"
```

---

## Self-Review

- **Spec coverage:**
  - `.chezmoi.toml.tmpl` 追加 → Task 1 ✓
  - sourceDir 手書き廃止 → Task 1（テンプレートで自動生成）✓
  - README 手順差し替え（winget/gh/installer）→ Task 2 Step 2 ✓
  - 誤記修正（`dotfiles`→`.dotfiles`、SSH→gh）→ Task 2 Step 2・Step 3 ✓
  - mise 補足1行 → Task 2 Step 2 の箇条書き ✓
  - リポ名リネームなし・`~/.dotfiles` 維持 → 設計通り、リネーム手順は含めない ✓
- **Placeholder scan:** TBD/TODO 無し。各ステップに実コマンド・実内容を記載済み。
- **Type consistency:** ファイルパス・コマンド名（`chezmoi init --source`、`ekuinox/.dotfiles`）は
  全タスクで一致。

## スコープ外（このプランに含めない）

- mise／node/pnpm/claude 等ツールの自動導入。
- macOS/Linux 向けブートストラップ。
- GitHub リポジトリ名のリネーム。
- 新マシン実機での fresh 検証（実機入手時に別途）。
