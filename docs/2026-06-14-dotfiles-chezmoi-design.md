# dotfiles の git 管理（chezmoi）設計

- 日付: 2026-06-14
- ステータス: 承認待ち → 実装計画へ

## 目的

Windows + Mac/Linux 混在環境で、設定ファイルを git 管理し複数マシンで同期する。
秘密情報・キャッシュ・生成物は管理対象に含めない。

## 方式

**chezmoi** を採用する。

- クロスプラットフォーム前提の dotfiles 管理ツールで、OS ごとのパス差やマシン固有値をテンプレートで吸収できる。今回の「OS をまたいで同じ設定を再現する」という目的に最も合致する。
- ソースディレクトリは既定の `~/.local/share/chezmoi` ではなく **`~/.dotfiles`** とする。リポジトリの実体が見つけやすく、仕様書もリポジトリ内に同居できる。
- ソースディレクトリ `~/.dotfiles` を git リポジトリとし、**GitHub の private リポジトリ**でホストする（個人メール等を含むため public にはしない）。

### 採用しなかった案

- **ベアリポジトリ + alias 方式**: 追加ツール不要だが、OS 差（パス・シェルの違い）の吸収を自前で書く必要があり、混在環境では煩雑。
- **シンボリックリンク方式（GNU Stow 等）**: Unix では定番だが、Windows はシンボリックリンクに管理者権限/開発者モードが必要で混在環境向きではない。

## 管理対象ファイル

| ファイル | 扱い |
|---|---|
| `~/.gitconfig` | `[user]` のみ管理。末尾に `[include] path = ~/.gitconfig.local` を追加。`[safe]` 等マシン固有設定は管理対象外の `~/.gitconfig.local` へ退避する |
| `Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` | Windows 固有パス。`.chezmoiignore` を OS テンプレートで分岐し、非 Windows では無視する |
| `~/.config/git/ignore` | そのまま管理 |
| `~/.config/mise/config.toml` | そのまま管理 |
| `~/.codex/config.toml` | 設定のみ管理（`auth.json`・各種 sqlite/DB・ログ・状態ファイルは対象外） |
| `~/.claude/` 一部 | `settings.json` / `CLAUDE.md` / `hooks/` / `keybindings.json` のみ管理。`settings.local.json`・`.claude.json`・`cache/`・`file-history/`・`backups/`・`debug/` 等は対象外 |

## 明示的に除外するもの

- **秘密情報**: `.ssh` `.gnupg` `.aws` `.azure` `.mcp-auth`、`~/.codex/auth.json`・`.sandbox-secrets`、`~/.gemini/oauth_creds.json`、`~/.docker/.token_seed`、`~/.claude.json`（履歴・MCP トークン込み）、`~/.cargo/credentials`、`~/.config/configstore` など。
- **キャッシュ / 生成物 / 履歴 / ツール自己管理領域**: `.cache` `.chocolatey` `.matplotlib` `.ivy2` `.jdks` `.rustup` `.xargo` `.cargo`(registry等) `.metals` `.local` `.vscode*` `.storybook` `.rest-client` `.mcp-hybrid-search` `.cline`、`.dotty_history` `.lesshst` `.node_repl_history` `.zoxide.nu`(生成物) `.vivaldi_reporting_data` `.claude.json.*`(バックアップ)、空の `.biome` `.ms-ad`。
- **今回は見送り**（必要になったら追加）: `.yarnrc` `.gemini/settings.json` `.docker/daemon.json` `.crossnote` `.wol-rs.toml`。

## .gitconfig の部分管理（include 方式）

現状の `~/.gitconfig` は次の 2 種が混在している。

```ini
[user]                        # 共有したい（identity）
    email = depkey@me.com
    name = ekuinox
[safe]                        # マシン固有（Windows 絶対パス。他 OS では無意味）
    directory = C:/Users/ekuinox/Documents/works/repos/...
    directory = C:/Users/ekuinox/Documents/works/repos/...
```

git の `[include]` 機能を使い、共有部分とマシン固有部分を分離する。

- **管理対象 `~/.gitconfig`**（chezmoi で同期）:

  ```ini
  [user]
      email = depkey@me.com
      name = ekuinox

  [include]
      path = ~/.gitconfig.local
  ```

- **管理対象外 `~/.gitconfig.local`**（各マシンが個別に保持）: `[safe]` directory などマシン固有設定を移動する。

これにより「`[user]` は全マシン共有、`[safe]` 等はマシンごと」が実現できる。
email を将来マシンごとに分けたくなった場合は、`[user]` 自体を `.gitconfig.local` 側へ移すか chezmoi テンプレート化する（今回は対象外）。

## 構成・データフロー

1. chezmoi をインストールする（Windows 側）。
2. ソースディレクトリを `~/.dotfiles` に設定して `chezmoi init` する。
3. `[safe]` を `~/.gitconfig.local` へ手動退避し、`~/.gitconfig` を include 方式に書き換える。
4. `chezmoi add` で管理対象ファイルを取り込む。
5. `.chezmoiignore` を作成し、OS 分岐（非 Windows では PowerShell プロファイルを無視）と誤取り込み防止を設定する。
6. GitHub に private リポジトリを作成し、`~/.dotfiles` を push する。
7. **新マシン**: chezmoi をインストールし、`chezmoi init --apply <repo>` で展開する。
8. **日常編集**: `chezmoi edit <file>` → `chezmoi apply` → `git commit` / `push`。

## エラー処理・検証

- 取り込み後に `chezmoi diff` を実行し、既存ファイルとの差分がゼロ（完全一致）であることを確認する。
- 適用前に `chezmoi apply --dry-run` で副作用を確認する。
- **秘密混入チェック**: push 前に `chezmoi managed` で管理対象一覧を目視確認し、ソースを `token` / `secret` / `password` / `key` 等で grep して秘密が混入していないことを確認する。

## スコープ外（YAGNI）

- 秘密情報の暗号化管理（chezmoi + age 等）。今回は秘密を一切含めない方針のため不要。
- Mac/Linux 実機での適用。当面は Windows 1 台。ただし将来の追加を妨げない構成にする（`.chezmoiignore` の OS 分岐で素地は用意）。
- 見送りファイル群の管理。
