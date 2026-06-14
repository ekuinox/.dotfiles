# 新マシン展開の簡略化 設計

## 目的

新マシン（主に Windows）での dotfiles 展開を、現状の複数手順から
「git/gh を入れてログイン → コピペ1発で chezmoi 導入と apply まで」に簡略化する。

## 現状と課題

現在の README「新マシンでの展開」手順:

```
mise use -g chezmoi@latest
chezmoi init --apply git@github.com:ekuinox/dotfiles.git
```

加えて `~/.dotfiles` をソース置き場にしたい場合は、事前に
`~/.config/chezmoi/chezmoi.toml` に `sourceDir = "~/.dotfiles"` を手書きする必要がある。

課題:

1. **mise が前提** — chezmoi を入れるためだけに mise を先に入れる必要がある。
2. **SSH 鍵が前提** — `git@github.com:...` は新マシンにまだ無い SSH 鍵を要求する。
   リポジトリは private のため認証が必須。
3. **sourceDir の手書き** — `chezmoi.toml` を手動作成する手順が残っている。
4. **README の記述ズレ** — README は `ekuinox/dotfiles`（ドット無し）と書いているが、
   実際のリモートは `https://github.com/ekuinox/.dotfiles.git`（ドット有り）。

## 決定事項

- ゴールは「1コマンドに近い展開」。ツール（mise 本体や node 等）の自動導入は対象外。
- リポジトリは private のまま。認証は **gh CLI ログイン**に統一する。
- ローカルのソース置き場は **`~/.dotfiles` を維持**する。
- GitHub リポジトリ名は **`.dotfiles`（先頭ドット付き）のまま**。リネームしない。
  - chezmoi のユーザー名ショートハンド（`chezmoi init ekuinox`）は規約上必ず
    `dotfiles`（ドット無し）を引くため使えないが、コピペで
    `ekuinox/.dotfiles` と明示するので問題にしない。
- sourceDir の永続化は **`.chezmoi.toml.tmpl` をリポジトリにコミット**して実現する
  （Option X）。`chezmoi.toml` の手書きを廃止する。

### 代替案（不採用）

- **Option Y**: テンプレートを足さず、コピペブロック先頭で `chezmoi.toml` を
  その場で書き出す。リポ変更ゼロだがコピペが増え、設定がリポ管理外に残るため不採用。

## 変更内容

### 1. `.chezmoi.toml.tmpl` を新規追加（リポジトリ直下）

```toml
sourceDir = "~/.dotfiles"
```

`chezmoi init` はクローン後にこのテンプレートを読み、
`~/.config/chezmoi/chezmoi.toml` を自動生成する。これにより:

- 手書きの `chezmoi.toml` 作成手順が不要になる。
- 以後の `chezmoi apply` が `~/.dotfiles` を正しくソースとして参照する。

chezmoi の特殊ファイルなので home には展開されない（`.chezmoiignore` 追記は不要）。

### 2. README「新マシンでの展開」を差し替え

新しいコピペ手順（Windows）:

```powershell
# 1. git と gh を入れる（Win11 標準の winget）
winget install Git.Git GitHub.cli

# 2. GitHub にログイン（ブラウザ認証。途中の git 認証連携は Yes を選ぶ）
gh auth login

# 3. chezmoi を入れて一気に展開
iex "&{$(irm 'https://get.chezmoi.io/ps1')} -- init --apply --source ~/.dotfiles ekuinox/.dotfiles"
```

補足として README に明記する点:

- **git を入れる理由**: chezmoi が private repo を clone する際、gh が設定する
  git の credential helper を使うには system の git バイナリ経由でクローンさせる
  のが確実なため。`gh auth login` の対話で git 連携を Yes にすれば認証が通る。
- **mise はこの手順の外**: chezmoi 自体は公式インストーラで入るため、mise 本体や
  mise 管理ツール（node, pnpm, claude 等）の導入は別途。展開後に mise を入れて
  `mise install` する旨を1行補足する。
- README 内の誤記（`ekuinox/dotfiles`／SSH 前提の記述）を実態（`ekuinox/.dotfiles`／
  gh 認証）に合わせて修正する。

## スコープ外

- mise 本体や node/pnpm/claude 等のツール自動導入（run_once スクリプト等）。
- macOS/Linux 向けのブートストラップ最適化（PowerShell プロファイルは元々 Windows 専用）。
- GitHub リポジトリ名のリネーム。

## 確認方法

- README のコピペ手順が、上から順に実行して新マシンで展開を完了できる記述に
  なっていること（実機での fresh 検証は別途、新マシン入手時）。
- `.chezmoi.toml.tmpl` が追加され、`sourceDir = "~/.dotfiles"` を含むこと。
- README に古い `mise use -g chezmoi` 手順／SSH 前提の記述／誤った `dotfiles`
  表記が残っていないこと。
