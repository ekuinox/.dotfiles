# chezmoi winget パッケージ一覧管理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** chezmoi で winget パッケージを `.chezmoidata` の一覧から `chezmoi apply` 時に一括導入できるようにする（Windows 限定・既存はスキップ）。

**Architecture:** winget パッケージ ID を `.chezmoidata/packages.toml` にキュレーションし、`run_onchange_install-winget-packages.ps1.tmpl` がその一覧をテンプレート展開して保持する。`chezmoi apply` 時、一覧が前回からハッシュ変化していれば PowerShell スクリプトが実行され、未導入のものだけ `winget install` する。

**Tech Stack:** chezmoi（Go template）、TOML（`.chezmoidata`）、Windows PowerShell、winget。

## Global Constraints

- 対象 OS は Windows のみ。テンプレート先頭の `{{ if eq .chezmoi.os "windows" }}` ガードで非 Windows ではレンダリング結果を空にし、chezmoi がスクリプトを実行しないようにする（`.chezmoiignore` は触らない）。
- 秘密情報・キャッシュはリポジトリに含めない。
- バージョンは原則 latest。バージョン固定 / ピン留めはしない（YAGNI）。
- アンインストール連動（完全同期）はスコープ外。一覧から消しても既存マシンからは削除しない。
- 既存マシンの破壊を避けるため、検証は必ず `--dry-run` で行い、実 install をプラン実行中に走らせない。
- ソースディレクトリは `~/.dotfiles`。作業はこのリポジトリ内で行う。

---

## File Structure

- `.chezmoidata/packages.toml`（新規）— winget パッケージ ID のキュレーション一覧。chezmoi が起動時に自動読み込みし、全テンプレートから `.winget.ids` として参照可能。
- `run_onchange_install-winget-packages.ps1.tmpl`（新規）— 一覧をテンプレート展開して埋め込み、apply 時に未導入パッケージを `winget install` する PowerShell スクリプト。
- `README.md`（修正）— 管理対象と運用手順に winget パッケージ管理を追記。

---

### Task 1: winget 導入スクリプトとパッケージ一覧

**Files:**
- Create: `run_onchange_install-winget-packages.ps1.tmpl`
- Create: `.chezmoidata/packages.toml`

**Interfaces:**
- Consumes: chezmoi のテンプレートデータ `.winget.ids`（`.chezmoidata/packages.toml` の `[winget] ids` 配列）、`.chezmoi.os`。
- Produces: `chezmoi apply` 時に実行される run_onchange スクリプト。後続タスク（README）はこのファイル名 `run_onchange_install-winget-packages.ps1.tmpl` とデータファイルパス `.chezmoidata/packages.toml` を参照する。

このタスクの「テスト」は chezmoi のテンプレート展開（`chezmoi execute-template`）。データファイルが無い状態でスクリプトが `.winget.ids` を参照するとレンダリングが失敗する（chezmoi は既定で missingkey=error）。これを red とし、データファイル作成で green にする。

- [ ] **Step 1: スクリプトテンプレートを作成（データファイルはまだ作らない）**

`run_onchange_install-winget-packages.ps1.tmpl` を作成する:

```powershell
{{- if eq .chezmoi.os "windows" -}}
# このスクリプトは chezmoi apply 時に run_onchange として実行される。
# winget パッケージ一覧は .chezmoidata/packages.toml で管理する。
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Warning "winget not found; skipping package install"
  exit 0
}

$ids = @(
{{- range .winget.ids }}
  "{{ . }}",
{{- end }}
)

$failed = @()
foreach ($id in $ids) {
  winget list --id $id -e *> $null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "skip (installed): $id"
    continue
  }
  Write-Host "installing: $id"
  winget install --id $id -e --silent `
    --accept-source-agreements --accept-package-agreements
  if ($LASTEXITCODE -ne 0) { $failed += $id }
}

if ($failed.Count -gt 0) {
  Write-Warning ("failed: " + ($failed -join ", "))
}
exit 0
{{- end -}}
```

- [ ] **Step 2: テンプレート展開を実行し、失敗することを確認（red）**

Run: `chezmoi execute-template < run_onchange_install-winget-packages.ps1.tmpl`
Expected: FAIL。`map has no entry for key "winget"` 系のエラーで終了する（`.winget.ids` がまだ存在しないため）。

- [ ] **Step 3: パッケージ一覧データファイルを作成**

`.chezmoidata/packages.toml` を作成する:

```toml
[winget]
ids = [
  "Git.Git",
  "GitHub.cli",
  "Microsoft.VisualStudioCode",
  "7zip.7zip",
]
```

- [ ] **Step 4: テンプレート展開を再実行し、成功することを確認（green）**

Run: `chezmoi execute-template < run_onchange_install-winget-packages.ps1.tmpl`
Expected: PASS。エラーなく PowerShell が出力され、`$ids` 配列に `"Git.Git"`, `"GitHub.cli"`, `"Microsoft.VisualStudioCode"`, `"7zip.7zip"` の4行が展開されている。先頭に `if (-not (Get-Command winget ...` が含まれる（Windows 実機で実行しているため OS ガードが通る）。

- [ ] **Step 5: dry-run で apply 予定を確認（実 install はしない）**

Run: `chezmoi apply --dry-run --verbose`
Expected: エラーなく完了し、`run_onchange_install-winget-packages.ps1` に相当するスクリプトが実行対象として表示される（dry-run なので実際の winget install は走らない）。既存の管理ファイルに想定外の差分が出ていないこと。

- [ ] **Step 6: コミット**

```bash
git add run_onchange_install-winget-packages.ps1.tmpl .chezmoidata/packages.toml
git commit -m "feat: winget パッケージを chezmoi で一覧管理する"
```

---

### Task 2: README に winget パッケージ管理を追記

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 1 が作成したファイル名 `.chezmoidata/packages.toml` と `run_onchange_install-winget-packages.ps1.tmpl`。
- Produces: なし（ドキュメントのみ）。

ドキュメントのみのため TDD のテストコードは無い。検証はレンダリング崩れが無いかの目視と、参照パスが Task 1 と一致しているかの確認とする。

- [ ] **Step 1: 「## 管理対象」リストに項目を追加**

`README.md` の `## 管理対象` の箇条書き末尾（`~/Documents/WindowsPowerShell/...（Windows のみ）` の行の直後）に、次の1行を追加する:

```markdown
- winget パッケージ一覧（Windows のみ。`.chezmoidata/packages.toml` に列挙、`chezmoi apply` で未導入のものを自動インストール）
```

- [ ] **Step 2: winget パッケージ管理の運用セクションを追加**

`README.md` の `## マシン固有設定` セクションの直前に、次のセクションを丸ごと挿入する:

```markdown
## winget パッケージ管理（Windows）

普段使う Windows アプリは winget で一覧管理する。アンインストールは扱わない（一覧から消しても既存マシンからは削除されない）。

- 一覧: `.chezmoidata/packages.toml` の `[winget] ids` に winget のパッケージ ID を列挙する。
- 導入: `run_onchange_install-winget-packages.ps1.tmpl` が `chezmoi apply` 時に実行され、一覧が前回から変わっていれば未導入のものだけ `winget install` する（既存はスキップ）。
- 追加: `chezmoi edit ~/.dotfiles/.chezmoidata/packages.toml` 相当でソースの `packages.toml` に ID を足し、`chezmoi apply` する。
- ID の調べ方: `winget search <名前>` で出る「ID」列の値（例: `Microsoft.VisualStudioCode`）を使う。
- Windows 以外では、テンプレートの OS ガードによりスクリプトは実行されない。

```

- [ ] **Step 3: レンダリングと整合性を目視確認**

Run: `chezmoi execute-template < run_onchange_install-winget-packages.ps1.tmpl`（パスが README の記述と一致していることの再確認）
Expected: Task 1 と同じく PASS。README 内のパス `.chezmoidata/packages.toml` と `run_onchange_install-winget-packages.ps1.tmpl` が実ファイル名と一致していること、Markdown の見出しレベル・箇条書きが既存スタイルと揃っていること。

- [ ] **Step 4: コミット**

```bash
git add README.md
git commit -m "docs: README に winget パッケージ管理の運用を追記"
```

---

## Self-Review

**1. Spec coverage:**
- 一覧管理（宣言的・既存スキップ）→ Task 1（`winget list` スキップ判定）✓
- 手キュレーション `.chezmoidata`（latest）→ Task 1 Step 3 ✓
- `run_onchange` 自動・変更検知 → Task 1（ID をスクリプトに埋め込みハッシュ変化で再発火）✓
- Windows 限定 OS ガード → Task 1 Step 1（`{{ if eq .chezmoi.os "windows" }}`）✓
- 非対話化 `--silent --accept-*` → Task 1 Step 1 ✓
- winget 不在ガード / 個別失敗継続 / `exit 0` → Task 1 Step 1 ✓
- 検証（execute-template / dry-run）→ Task 1 Step 2,4,5 ✓
- 非スコープ（アンインストール・export・バージョン固定）→ プランで実装していない ✓
- ドキュメント反映 → Task 2 ✓

**2. Placeholder scan:** "TBD"/"TODO"/「適切に」等の曖昧表現なし。全コードブロックは完成形。✓

**3. Type consistency:** データキー `.winget.ids` は `.chezmoidata/packages.toml` の `[winget] ids` と一致。ファイル名 `run_onchange_install-winget-packages.ps1.tmpl` / `.chezmoidata/packages.toml` は全タスクで同一表記。✓
