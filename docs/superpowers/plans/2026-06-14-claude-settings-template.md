# Claude settings.json テンプレート管理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `~/.claude/settings.json` をキュレーションしてテンプレート化し、`init_env.sh` とともに chezmoi 管理に加え、新マシンでも hooks とプリファレンスが動く状態にする。

**Architecture:** 移植価値のある設定だけを `dot_claude/settings.json.tmpl` に置き、hooks コマンドと `env.BASH_ENV` のパスを `{{ .chezmoi.homeDir | replace "\\" "/" }}` で解決する。`permissions.allow`（マシン固有の堆積物＋トークンを含む）と `additionalDirectories` は除外。`init_env.sh` はそのまま `dot_claude/init_env.sh` として管理し、非 Windows では ignore。bash スクリプトの改行が checkout で壊れないよう `.gitattributes` で LF 固定する。

**Tech Stack:** chezmoi v2（Go template + sprig）、PowerShell、Git Bash。

参照スペック: `docs/superpowers/specs/2026-06-14-claude-settings-template-design.md`

---

### Task 1: init_env.sh を chezmoi 管理に加え、改行と非 Windows ignore を設定する

**Files:**
- Create: `C:\Users\ekuinox\.dotfiles\dot_claude\init_env.sh`
- Create: `C:\Users\ekuinox\.dotfiles\.gitattributes`
- Modify: `C:\Users\ekuinox\.dotfiles\.chezmoiignore`

- [ ] **Step 1: `.gitattributes` を作成（.sh を LF 固定）**

`C:\Users\ekuinox\.dotfiles\.gitattributes` を新規作成する。BASH_ENV で source される
bash スクリプトが CRLF になると新マシンで壊れるため、`*.sh` を LF に固定する。

```
*.sh text eol=lf
```

- [ ] **Step 2: `dot_claude/init_env.sh` を作成**

`C:\Users\ekuinox\.dotfiles\dot_claude\init_env.sh` を、現行の `~/.claude/init_env.sh`
と同一内容（LF 改行）で新規作成する。

```bash
#!/usr/bin/env bash
# Dynamically load Windows user PATH into the bash environment.
# Called automatically by bash via BASH_ENV for non-interactive shells.
_win_path=$(powershell.exe -NoProfile -Command \
  "[Environment]::GetEnvironmentVariable('PATH','User') + ';' + [Environment]::GetEnvironmentVariable('PATH','Machine')" \
  2>/dev/null | tr -d '\r\n')

if [ -n "$_win_path" ]; then
  # Convert Windows path format (C:\foo\bar) to Git Bash format (/c/foo/bar)
  _bash_path=$(printf '%s' "$_win_path" \
    | tr '\\' '/' \
    | tr ';' '\n' \
    | sed 's|^\([A-Za-z]\):|/\l\1|' \
    | tr '\n' ':' \
    | sed 's/:$//')
  export PATH="${_bash_path}:${PATH}"
fi
```

- [ ] **Step 3: 取り込んだ内容が現行ファイルと一致することを確認**

Run (Bash tool):
```
diff <(tr -d '\r' < ~/.claude/init_env.sh) <(tr -d '\r' < ~/.dotfiles/dot_claude/init_env.sh) && echo IDENTICAL
```
Expected: `IDENTICAL`（改行差を無視して内容一致）。

- [ ] **Step 4: `.chezmoiignore` の非 Windows ブロックに init_env.sh を追記**

`C:\Users\ekuinox\.dotfiles\.chezmoiignore` を読み、非 Windows ブロックを次の形にする。
`Documents/WindowsPowerShell/...` の行の直後に `.claude/init_env.sh` を追加する。

変更後の `.chezmoiignore` 全体:

```
# リポジトリ付随物（home に展開しない）
README.md
docs
docs/**

# PowerShell プロファイルは Windows 専用。他 OS では無視する
{{ if ne .chezmoi.os "windows" }}
Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1
.claude/init_env.sh
{{ end }}
```

- [ ] **Step 5: chezmoiignore が Windows で init_env.sh を無視しないことを確認**

`chezmoi managed` は ignore 適用後の管理対象を出す。Windows 上では init_env.sh が
管理対象に含まれるはず。

Run (Bash tool):
```
chezmoi managed | grep -i 'claude/init_env.sh' && echo MANAGED
```
Expected: `.claude/init_env.sh` の行が出て `MANAGED` と表示される（Windows なので ignore されない）。

- [ ] **Step 6: コミット**

```
cd ~/.dotfiles
git add .gitattributes dot_claude/init_env.sh .chezmoiignore
git commit -m "feat: init_env.sh を chezmoi 管理に追加し非Windowsでignore（.sh はLF固定）"
```

---

### Task 2: キュレーション済み settings.json.tmpl を追加する

**Files:**
- Create: `C:\Users\ekuinox\.dotfiles\dot_claude\settings.json.tmpl`

- [ ] **Step 1: `dot_claude/settings.json.tmpl` を作成**

`C:\Users\ekuinox\.dotfiles\dot_claude\settings.json.tmpl` を以下の内容で新規作成する。
`permissions.allow` と `permissions.additionalDirectories` は含めない。
パスは `{{ .chezmoi.homeDir | replace "\\" "/" }}` でテンプレート化する。

```json
{
  "env": {
    "BASH_ENV": "{{ .chezmoi.homeDir | replace "\\" "/" }}/.claude/init_env.sh"
  },
  "permissions": {
    "deny": [
      "Read(./.env)",
      "Read(./**/.env)",
      "Read(./.env.local)",
      "Read(./**/.env.local)",
      "Read(./.env.production)",
      "Read(./**/.env.production)",
      "Read(./.env.development)",
      "Read(./**/.env.development)",
      "Read(./.envrc)",
      "Read(./**/.envrc)",
      "Read(./**/credentials.json)",
      "Read(./**/credentials.yaml)",
      "Read(./**/secrets.json)",
      "Read(./**/secrets.yaml)",
      "Read(./**/secrets.yml)",
      "Read(./**/*.pem)",
      "Read(./**/id_rsa)",
      "Read(./**/id_ed25519)",
      "Read(./**/service-account*.json)"
    ]
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"{{ .chezmoi.homeDir | replace "\\" "/" }}/.claude/hooks/toast-start.ps1\"",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"{{ .chezmoi.homeDir | replace "\\" "/" }}/.claude/hooks/toast-stop.ps1\"",
            "timeout": 15,
            "statusMessage": "完了通知を確認中..."
          }
        ]
      }
    ]
  },
  "defaultShell": "powershell",
  "enabledPlugins": {
    "rust-analyzer-lsp@claude-plugins-official": true,
    "superpowers@claude-plugins-official": true,
    "skill-creator@claude-plugins-official": true,
    "code-review@claude-plugins-official": true,
    "github@claude-plugins-official": true,
    "typescript-lsp@claude-plugins-official": true
  },
  "effortLevel": "high",
  "autoUpdatesChannel": "latest",
  "switchModelsOnFlag": true,
  "agentPushNotifEnabled": true
}
```

- [ ] **Step 2: テンプレートが有効な JSON にレンダリングされることを確認**

`chezmoi execute-template` でレンダリングし、`python -m json.tool` で JSON として
parse できることを確認する（parse 成功 = 整形済み JSON が出力される）。

Run (Bash tool):
```
chezmoi execute-template < ~/.dotfiles/dot_claude/settings.json.tmpl | python -m json.tool > /dev/null && echo VALID_JSON
```
Expected: `VALID_JSON`（エラーが出ない）。

- [ ] **Step 3: パスが実ホームに解決されていることを確認**

Run (Bash tool):
```
chezmoi execute-template < ~/.dotfiles/dot_claude/settings.json.tmpl | grep -E 'BASH_ENV|toast-start.ps1'
```
Expected: 次のように `C:/Users/ekuinox` 形式（前方スラッシュ）で解決された行が出る。
```
    "BASH_ENV": "C:/Users/ekuinox/.claude/init_env.sh"
            ... toast-start.ps1 を含む command 行に C:/Users/ekuinox/.claude/hooks/toast-start.ps1 ...
```
`{{` や `}}` がレンダリング結果に残っていないこと。

- [ ] **Step 4: 除外対象とトークンが含まれないことを確認**

Run (Bash tool):
```
chezmoi execute-template < ~/.dotfiles/dot_claude/settings.json.tmpl | grep -nE '"allow"|additionalDirectories|figd_'
```
Expected: 何も出力されない（allow / additionalDirectories / Figma トークンが含まれていない）。

- [ ] **Step 5: コミット**

```
cd ~/.dotfiles
git add dot_claude/settings.json.tmpl
git commit -m "feat: Claude settings.json をキュレーションしてテンプレート管理（hooks/BASH_ENVパスを解決）"
```

---

## 適用について（実装スコープ外・ユーザーが意識的に実行）

このプランはソース作成と検証・コミットまで。`chezmoi apply` で実際に
`~/.claude/settings.json` をキュレーション版へ上書きする操作は、現マシンの allow リストが
消えることをユーザーが了承した上で別途行う（設計の合意事項）。実装タスク内では apply しない。

適用する場合の差分プレビュー: `chezmoi diff ~/.claude/settings.json`

## Self-Review

- **Spec coverage:**
  - settings.json をキュレーションしてテンプレート化（deny/hooks/plugins/prefs 残す、allow/additionalDirectories 外す）→ Task 2 Step 1 ✓
  - パスを `{{ .chezmoi.homeDir | replace "\\" "/" }}` で解決 → Task 2 Step 1・Step 3 ✓
  - init_env.sh を chezmoi 管理に追加 → Task 1 Step 2 ✓
  - 非 Windows で init_env.sh を ignore → Task 1 Step 4 ✓
  - トークンがリポに入らないこと → Task 2 Step 4 で検証 ✓
  - レンダリング検証（有効 JSON・パス解決・除外確認）→ Task 2 Step 2-4 ✓（スペックの確認方法に対応）
  - 改行による bash スクリプト破損の防止（スペック外だが管理上の correctness）→ Task 1 Step 1 `.gitattributes` ✓
- **Placeholder scan:** TBD/TODO 無し。各ステップに実内容・実コマンド・期待出力を記載。
- **Type consistency:** ファイルパス（`dot_claude/settings.json.tmpl`、`dot_claude/init_env.sh`、
  ターゲット `.claude/init_env.sh`）、テンプレート式（`{{ .chezmoi.homeDir | replace "\\" "/" }}`）は
  全タスクで一致。

## スコープ外（このプランに含めない）

- `chezmoi apply`（現マシンの settings.json 上書き）。
- Figma トークンの失効・再発行。
- 非 Windows 向けの hooks / settings.json 分岐。
- 移植用にキュレーションした allow セット。
