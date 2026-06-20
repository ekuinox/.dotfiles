# dotfiles リポジトリ用 CLAUDE.md 設計

## 目的

このリポジトリ（chezmoi の source ディレクトリ）で Claude が作業するときの指針を
`CLAUDE.md` として用意する。chezmoi 固有の規約の誤解を防ぎ、安全な検証手順・コミット規約・
文体を揃える。構造の詳細は既存の `README.md` に委ね、本ファイルは「振る舞いのルール」に特化する。

## 配置と展開

- 置き場所: リポジトリルート `/home/ekuinox/.dotfiles/CLAUDE.md`
- ルート直下の `CLAUDE.md` は放置すると chezmoi が `~/CLAUDE.md` に展開してしまうため、
  `README.md` / `docs` と同様に `.chezmoiignore` へ `CLAUDE.md` を追加して展開対象から外す。
- home に展開される全プロジェクト共通の指針は別ファイル（`dot_claude/CLAUDE.md` → `~/.claude/CLAUDE.md`）
  が担う。本ファイルはこのリポジトリ専用。

## 構成（5セクション）

### 1. このリポジトリについて

- このリポジトリ自体が chezmoi の source ディレクトリ（`~/.dotfiles`）。
  ここでファイルを直接編集する = chezmoi ソースを編集すること。
- 構造・管理対象・展開手順の詳細は `README.md` を参照（重複して書かない）。

### 2. chezmoi 規約（誤解防止）

- `dot_` プレフィックス = home の `.` ファイル（例: `dot_gitconfig` → `~/.gitconfig`）。
- `.tmpl` 拡張子 = Go テンプレート。`{{ }}` と `.chezmoi.os` 等で OS 分岐する。
- home 側ファイル（`~/.gitconfig` 等）を直接編集しない。必ず source を編集して `chezmoi apply` で反映する。
- 新規ファイルを管理対象にするときは `chezmoi add` で取り込む。

### 3. 安全な検証手順

- 反映前に `chezmoi diff` で差分を確認し、`chezmoi apply --dry-run` で予行する。
- 秘密情報はコミットしない（README の方針: 秘密・キャッシュは含めない）。`.tmpl` に API キー等を直書きしない。
- `.tmpl` を編集したら `chezmoi execute-template` 等で展開結果を確認できる。
- グローバル CLAUDE.md の秘密ファイル取り扱いルール（deny されたパスを別経路で読まない）も踏襲する。

### 4. コミット / PR 規約

- コミットメッセージは日本語。必要に応じて `feat:` / `fix:` / `docs:` プレフィックスを付ける。
- PR ベースで進める（master へ直接 push しない）。
- コミット/PR 本文末尾の Co-Authored-By 規約を踏襲する。

### 5. 文体・言語・トーン / markdown の使い方

- ドキュメントは日本語で、簡潔に書く。絵文字は使わない。
- 見出し階層を整え、コードブロックには言語指定を付ける。
- 強調（太字/斜体）とコードブロックは本当に適切な箇所のみで使う:
  - 強調を見出しの代用にしない（見出しは見出し記法を使う）。
  - 強調は「見逃すとエラーや事故につながる点」に限定する。
  - コードブロックは実際のコマンド/コード/設定の引用にのみ使い、単なる強調目的では使わない。

## 成果物

- 新規: `/home/ekuinox/.dotfiles/CLAUDE.md`（上記5セクション）
- 変更: `.chezmoiignore` に `CLAUDE.md` を追加
