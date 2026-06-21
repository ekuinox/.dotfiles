# GNU coreutils 採用による ls マルチバイト表示根治 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GNU coreutils を home-manager で導入し、uutils ls を PATH 上で上書きして日本語ファイル名の文字化けを根治する。

**Architecture:** chezmoi ソース `dot_config/home-manager/home.nix` の `home.packages` に `pkgs.coreutils` を 1 行追加する。PATH 先頭の `~/.nix-profile/bin` に GNU 版 coreutils が入り、`/usr/bin` の uutils を全経路で上書きする。`chezmoi apply` → `home-manager switch` で反映し、実 PTY で日本語表示を検証する。最後に PR を出し、エイリアスのみの PR #11 をクローズして一本化する。

**Tech Stack:** Nix flakes, home-manager, chezmoi, GNU coreutils, git / gh CLI

## Global Constraints

- 作業リポジトリ: `~/.dotfiles`（chezmoi ソース。ここを編集して `chezmoi apply` で反映）
- home 側ファイル（`~/.config/...`）は直接編集しない
- master 直 push 禁止。PR ベース。コミットメッセージは日本語
- コミット末尾に `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- PR 本文末尾に `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
- 作業ブランチ: `feat/gnu-coreutils-ls`（設計ドキュメントは既にこのブランチにコミット済み）
- home-manager switch コマンド: `home-manager switch --flake ~/.config/home-manager#wsl`（エイリアス `hms`）
- 秘密ファイルを別経路で読まない（グローバル CLAUDE.md 準拠）

---

### Task 1: home.nix に GNU coreutils を追加して反映・検証

**Files:**
- Modify: `~/.dotfiles/dot_config/home-manager/home.nix`（`home.packages` リスト、現状 26-43 行付近）

**Interfaces:**
- Consumes: なし（既存の `pkgs` 引数を使う）
- Produces: `~/.nix-profile/bin/ls`（GNU coreutils 版）が PATH 上で `/usr/bin/ls`（uutils）を上書きする状態

- [ ] **Step 1: 現状の「壊れている」ことを検証（事前確認）**

実 PTY 上で uutils ls が日本語を `?` にすることを確認する。

```bash
cd /tmp && touch 'テスト.txt'
python3 - <<'PY'
import os,subprocess,pty
m,s=pty.openpty()
p=subprocess.Popen(['ls','テスト.txt'],stdout=s,stderr=s,cwd='/tmp');os.close(s)
buf=b''
while True:
    try:d=os.read(m,1024)
    except OSError:break
    if not d:break
    buf+=d
p.wait()
print(' '.join(f'{b:02x}' for b in buf if b not in (0x0d,0x0a)))
PY
```

Expected: `3f 3f 3f 3f 3f 3f 3f 3f 3f 2e 74 78 74`（`?????????.txt`＝化けている）

- [ ] **Step 2: home.nix の home.packages に pkgs.coreutils を追加**

`home.packages` リストの先頭付近（`pkgs.claude-code` の前）に 1 行追加する。意図のコメントを添える。

```nix
    packages = [
      # Ubuntu 26.04 標準の uutils ls はロケールを見ず日本語ファイル名を ? に化けさせる。
      # 成熟した GNU coreutils を PATH 先頭(nix-profile)に置き uutils(/usr/bin) を上書きする。
      pkgs.coreutils
      pkgs.claude-code
      pkgs.chezmoi
```

- [ ] **Step 3: chezmoi diff で差分確認**

Run: `cd ~ && chezmoi diff ~/.config/home-manager/home.nix`
Expected: `home.packages` に `pkgs.coreutils` 行とコメントが追加される差分のみが表示される

- [ ] **Step 4: chezmoi apply で home 側へ反映**

Run: `cd ~ && chezmoi apply ~/.config/home-manager/home.nix && echo OK`
Expected: `OK`（エラーなし）

- [ ] **Step 5: home-manager switch で適用**

Run: `home-manager switch --flake ~/.config/home-manager#wsl 2>&1 | tail -5`
Expected: エラーなく `Activating ...` 群が流れて完了する（衝突警告が出ないこと）

- [ ] **Step 6: GNU ls に切り替わったか検証**

Run: `type -a ls; ~/.nix-profile/bin/ls --version | head -1`
Expected: `ls` が `~/.nix-profile/bin/ls` を先に指す。バージョンが `ls (GNU coreutils) ...`

- [ ] **Step 7: 日本語ファイル名が直ったか実 PTY で検証**

Step 1 と同じスクリプトを、GNU ls を使う新しい環境で実行する。

```bash
cd /tmp && touch 'テスト.txt'
python3 - <<'PY'
import os,subprocess,pty
env=dict(os.environ); env['PATH']=os.path.expanduser('~/.nix-profile/bin')+':'+env['PATH']
m,s=pty.openpty()
p=subprocess.Popen(['ls','テスト.txt'],stdout=s,stderr=s,cwd='/tmp',env=env);os.close(s)
buf=b''
while True:
    try:d=os.read(m,1024)
    except OSError:break
    if not d:break
    buf+=d
p.wait()
line=bytes(b for b in buf if b not in (0x0d,0x0a))
print('hex:',' '.join(f'{b:02x}' for b in line))
print('str:',line.decode('utf-8'))
import os as _o; _o.remove('/tmp/テスト.txt')
PY
```

Expected: `hex: e3 83 86 e3 82 b9 e3 83 88 2e 74 78 74` / `str: テスト.txt`（生 UTF-8、`?` も `\343` も無し）

- [ ] **Step 8: コミット**

```bash
cd ~/.dotfiles && git add dot_config/home-manager/home.nix && git commit -F - <<'EOF'
feat: GNU coreutils を導入し ls の日本語表示を根治

Ubuntu 26.04 標準の uutils ls はロケールを参照せず、非 ASCII の
ファイル名を端末で ? や 8 進エスケープに化けさせる(最新版でも未修正)。
pkgs.coreutils を home.packages に追加し、PATH 先頭の nix-profile に
入る GNU 版 ls で /usr/bin の uutils を全経路上書きして根治する。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: PR 作成と PR #11 のクローズ一本化

**Files:** なし（git / gh 操作のみ）

**Interfaces:**
- Consumes: Task 1 のコミット（ブランチ `feat/gnu-coreutils-ls`）
- Produces: GitHub PR（base master）、PR #11 のクローズ

- [ ] **Step 1: ブランチを push**

Run: `cd ~/.dotfiles && git push -u origin feat/gnu-coreutils-ls 2>&1 | tail -3`
Expected: `feat/gnu-coreutils-ls -> feat/gnu-coreutils-ls` が表示され成功

- [ ] **Step 2: PR を作成**

```bash
cd ~/.dotfiles && gh pr create --base master --head feat/gnu-coreutils-ls \
  --title "feat: GNU coreutils を導入し ls の日本語表示を根治" \
  --body "$(cat <<'EOF'
## 概要

Ubuntu 26.04(WSL) 標準の uutils ls が、日本語など非 ASCII のファイル名を端末で `?` や `\343...` の 8 進エスケープに化けさせる問題を根治する。

## 原因

uutils ls はロケール(`LC_CTYPE`)を参照せず 0x80 以上のバイトを無条件に非表示文字扱いする。`LANG`/`LC_CTYPE=C.UTF-8` を設定しても `?` のまま(実測確認済み)。最新リリース 0.9.0 でも未修正で、版を上げても直らない。

## 対処

`home.packages` に `pkgs.coreutils` を追加。PATH 先頭の `~/.nix-profile/bin` に入る GNU 版 ls/cat/cp… が `/usr/bin` の uutils を全経路(対話・スクリプト・command・絶対パス以外)で上書きする。エイリアスのような抜け穴がない。

## 確認

- `ls --version` が GNU coreutils
- 実 PTY で `ls テスト.txt` が生 UTF-8 `e3 83 86 e3 82 b9 e3 83 88`(テスト) を出力
- mac 影響なし(flake は wsl のみビルド)、パッケージ衝突なし

設計: `docs/superpowers/specs/2026-06-21-gnu-coreutils-for-ls-multibyte-design.md`

エイリアスで対処していた #11 は本対応に置き換えるためクローズする。

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: 新しい PR の URL が表示される

- [ ] **Step 3: PR #11 をクローズ（一本化）**

```bash
cd ~/.dotfiles && gh pr close 11 --comment "GNU coreutils を導入する根治対応 (feat/gnu-coreutils-ls) に置き換えるためクローズします。エイリアスは抜け穴(command ls / 絶対パス / スクリプト)が残るため不採用。" --delete-branch
```

Expected: PR #11 が closed になり、`fix/ls-japanese-filename` ブランチが削除される

---

## 補足: 未決事項

- uutils 上流への issue 報告（ls の TTY マルチバイト表示）は任意。本対応で手元は解決する。実施する場合はこの計画外の別作業とする。
