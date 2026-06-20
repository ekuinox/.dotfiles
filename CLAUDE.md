# CLAUDE.md

このリポジトリで作業するときの指針。構造・管理対象・展開手順の詳細は [README.md](README.md) を参照する。

## このリポジトリについて

- このリポジトリ自体が chezmoi の source ディレクトリ（`~/.dotfiles`）。ここでファイルを直接編集する = chezmoi ソースを編集すること。
- home に展開される全プロジェクト共通の Claude 指針は `dot_claude/CLAUDE.md`（→ `~/.claude/CLAUDE.md`）が担う。このファイルはこのリポジトリ専用で、home には展開しない。

## chezmoi 規約

- `dot_` プレフィックスは home の `.` ファイルを表す（例: `dot_gitconfig` → `~/.gitconfig`）。
- `.tmpl` 拡張子は Go テンプレート。`{{ }}` と `.chezmoi.os` 等で OS 分岐する。
- home 側ファイル（`~/.gitconfig` 等）を直接編集しない。必ず source を編集して `chezmoi apply` で反映する。
- 新規ファイルを管理対象にするときは `chezmoi add` で取り込む。

## 安全な検証手順

- 反映前に `chezmoi diff` で差分を確認し、`chezmoi apply --dry-run` で予行する。
- 秘密情報はコミットしない（README の方針: 秘密・キャッシュは含めない）。`.tmpl` に API キー等を直書きしない。
- `.tmpl` を編集したら `chezmoi execute-template` で展開結果を確認できる。
- グローバル CLAUDE.md の秘密ファイル取り扱いルール（deny されたパスを別経路で読まない）も踏襲する。
- `nix flake update` で `~/.config/home-manager/flake.lock` を更新したら、`chezmoi re-add` でソースへ取り込み直す（ターゲットのみ更新されソースと乖離するため）。

## コミット / PR 規約

- コミットメッセージは日本語。必要に応じて `feat:` / `fix:` / `docs:` プレフィックスを付ける。
- PR ベースで進める。master へ直接 push しない。
- コミット / PR 本文末尾の Co-Authored-By 規約を踏襲する。

## 文体・言語・トーン / markdown の使い方

- ドキュメントは日本語で、簡潔に書く。絵文字は使わない。
- 見出し階層を整え、コードブロックには言語指定を付ける。
- 強調（太字 / 斜体）とコードブロックは本当に適切な箇所のみで使う。
  - 強調を見出しの代用にしない。見出しは見出し記法を使う。
  - 強調は、見逃すとエラーや事故につながる点に限定する。
  - コードブロックは実際のコマンド / コード / 設定の引用にのみ使い、単なる強調目的では使わない。
