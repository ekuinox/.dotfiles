# Claude settings.json のテンプレート管理 設計

## 目的

`~/.claude/settings.json` を chezmoi 管理に加え、新マシンでも hooks（toast 通知）や
各種プリファレンスがそのまま使える状態にする。現状 hooks のコマンドはユーザー名つきの
絶対パス（`C:\Users\ekuinox\.claude\hooks\*.ps1`）でハードコードされており、
コピーしても新マシンでは動かない。

## 現状と課題

`~/.claude/settings.json`（約28KB）の内訳:

- `permissions.allow`: 約200エントリ。ほぼ全てが過去に承認した d-prompt-manager /
  homepage の絶対パス付きコマンドで、マシン＋プロジェクト固有の堆積物。
  この中に Figma の Personal Access Token がベタ書きされた行が含まれる（要対処）。
- `permissions.deny`: 秘密ファイル（`.env`, `*.pem`, `id_rsa` 等）の Read 拒否リスト。
  マシン非依存で移植価値が高い。
- `permissions.additionalDirectories`: d-prompt-manager の絶対パス1件。プロジェクト固有。
- `hooks`: UserPromptSubmit / Stop に toast 通知スクリプトを登録。コマンドが
  `C:\Users\ekuinox\.claude\hooks\*.ps1` の絶対パス。スクリプト本体はすでに chezmoi 管理下
  （`dot_claude/hooks/toast-start.ps1` / `toast-stop.ps1`）で、apply 後は
  `~/.claude/hooks/` に存在する。
- `env.BASH_ENV`: `~/.claude/init_env.sh` を指す。init_env.sh は実在するが chezmoi 管理外。
- `defaultShell`, `enabledPlugins`, `effortLevel`, `autoUpdatesChannel`,
  `switchModelsOnFlag`, `agentPushNotifEnabled`: マシン非依存のプリファレンス。

`init_env.sh`（666バイト）は Windows のユーザー PATH を powershell 経由で取得し
Git Bash 形式に変換して `export PATH` するだけ。秘密もハードコードされた絶対パスも無く、
そのまま移植可能。ただし powershell.exe 依存で Windows 専用。

`settings.local.json` にはマシン固有 allow（`Bash(ssh *)`, `PowerShell(gh *)`）が入る。
chezmoi 管理外。

## 決定事項

- テンプレート化は「移植価値のある部分だけ」をキュレーションする方針。
- 管理する settings.json に **残す**: `env.BASH_ENV`（パスをテンプレート化）、
  `permissions.deny`、`hooks`（パスをテンプレート化）、`defaultShell`、
  `enabledPlugins`、`effortLevel`、`autoUpdatesChannel`、`switchModelsOnFlag`、
  `agentPushNotifEnabled`。
- 管理する settings.json から **外す**: `permissions.allow`（約200エントリ全部。
  マシン／プロジェクト固有かつトークンを含むため丸ごと除外）、
  `permissions.additionalDirectories`（プロジェクト固有の絶対パス）。
- `init_env.sh` も chezmoi 管理に加える（中身は移植可能・秘密なし）。Windows 専用なので
  非 Windows では ignore する。
- マシン固有の許可は今まで通り管理外の `settings.local.json` に置く。Claude Code が
  settings.json と settings.local.json をマージするため、管理ファイルは静的設定だけに保てる。

### パスのテンプレート化方式

`{{ .chezmoi.homeDir | replace "\\" "/" }}` でホームディレクトリをスラッシュ区切りに変換し、
`"…/.claude/hooks/toast-start.ps1"` のように埋め込む。PowerShell の `-File` も
bash の `BASH_ENV` も前方スラッシュのパスを受け付けるため、JSON 内でのバックスラッシュ
エスケープを避けられる。

## 変更内容

### 1. `dot_claude/settings.json.tmpl` を新規追加 → `~/.claude/settings.json`

キュレーション済みの設定をテンプレートとして配置する。構造（値は現状から移植）:

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

`permissions.allow` と `permissions.additionalDirectories` は意図的に含めない。

### 2. `dot_claude/init_env.sh` を新規追加 → `~/.claude/init_env.sh`

現状の `~/.claude/init_env.sh` の内容をそのままソースに取り込む（テンプレート化不要、
内容は移植可能）。chezmoi の `add` で取り込む想定。

### 3. `.chezmoiignore` を変更

非 Windows では `init_env.sh` を無視する（既存の PowerShell プロファイルと同じ扱い）。
既存の非 Windows ブロックに `.claude/init_env.sh` を追記する。

```
{{ if ne .chezmoi.os "windows" }}
Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1
.claude/init_env.sh
{{ end }}
```

## 運用上の前提

- 初回 `chezmoi apply` で現マシンの `~/.claude/settings.json` はキュレーション版に
  上書きされる。現在の約200の allow エントリは消える（必要な許可は使用時に再承認され
  settings.local.json に溜まる）。同時に生きている settings.json からトークン行も消える。
- 今後 Claude Code が settings.json を書き換えると chezmoi ソースとの差分が出る。
  その場合は `chezmoi re-add` でソースに取り込むか `chezmoi apply` で戻す運用とする。
  マシン固有の許可は settings.local.json に入るため、通常運用では管理ファイルは汚れにくい。

## セキュリティ

- allow を丸ごと外すことで、Figma トークンはリポジトリに一切入らない。
- ただしトークンは Figma 側で有効なままなので、**失効・再発行を推奨**する
  （本作業のスコープ外だが、リポジトリ化の前提として強く推奨）。

## スコープ外

- 非 Windows 対応（hooks も init_env.sh も powershell 前提。将来必要になれば
  `.chezmoi.os` でテンプレート分岐する）。
- 移植用にキュレーションした `permissions.allow` セットを別途持つこと。
- Figma トークンの実際の失効・再発行操作。

## 確認方法

- `chezmoi execute-template` で settings.json.tmpl が有効な JSON にレンダリングされ、
  hooks / BASH_ENV のパスが実ホームに解決されること。
- レンダリング結果に `permissions.allow`・`additionalDirectories`・トークン文字列
  （`figd_`）が含まれないこと。
- `.chezmoiignore` 非 Windows ブロックに `init_env.sh` が入っていること。
