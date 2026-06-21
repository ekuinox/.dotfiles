# GNU coreutils 採用による ls マルチバイト表示問題の根治

## 背景

Ubuntu 26.04 (WSL) は coreutils として uutils 版 (`coreutils-from-uutils`、`/usr/bin/ls` = uutils coreutils 0.8.0) を標準採用している。この `ls` は端末 (TTY) 出力時に日本語など非 ASCII のファイル名を `\343...` の 8 進エスケープや `?` に化けさせる。

## 原因

uutils ls は端末出力時、GNU と同じく次の既定挙動を持つ。

- shell-escape クォート → 非表示文字をエスケープ
- `-q` (hide-control-chars) → 非表示文字を `?` に置換

問題は「文字が表示可能かどうか」の判定にある。GNU ls は UTF-8 ロケール下でマルチバイト文字を表示可能と正しく認識するため化けない。一方 uutils ls はロケール (`LC_CTYPE`) を参照せず、0x80 以上のバイトを無条件に非表示文字として扱う。

実測で裏付け済み (uutils 0.8.0、実 PTY):

```
LANG 未設定 (POSIX)         -> 3f 3f 3f ... .txt   (?????????.txt)
LANG=C.UTF-8                -> 3f 3f 3f ... .txt
LC_ALL/LC_CTYPE=C.UTF-8     -> 3f 3f 3f ... .txt
```

ロケールをどう設定しても `?` のまま = 設定や版ではなく実装の穴。

## 上流の状況

- 最新リリース 0.9.0 の変更履歴にこの表示の修正は無い。0.8.0 → 0.9.0 に上げても直らない。
- uutils には `J - Locale` ラベルがあり、ロケール対応の未完了が公式に追跡されている (例: #12305 chinese localization、#12474 ls の LC_COLLATE 非対応)。pr / touch / stat / od など他コマンドでもマルチバイトでの不具合 issue が複数ある。

結論として、現時点で「最新版に乗れば解決」とは言えない。マルチバイト/ロケール対応が成熟していない若いプロジェクトの穴であり、ls に限らず再発リスクがある。

## 方針

成熟した GNU coreutils を採用し、uutils を全経路で上書きする。

- `~/.dotfiles/dot_config/home-manager/home.nix` の `home.packages` に `pkgs.coreutils` を追加する。
- 前回 PR #11 で入れた `ls` エイリアス (`--quoting-style=literal --show-control-chars`) を削除する。GNU ls は UTF-8 端末で日本語をフラグなしで正しく表示するため不要であり、回避策を残すと意図が濁る。

### なぜ効くか

PATH は `~/.nix-profile/bin` が `/usr/bin` より前に位置する。`pkgs.coreutils` を入れると GNU 版 `ls`/`cat`/`cp` 等が profile に入り、uutils (`/usr/bin`) を全経路 (対話シェル・スクリプト・`command ls`・絶対パス以外) で上書きする。エイリアスと違い抜け穴がない。

### 代替案と不採用理由

- ls だけ GNU で上書き (案 B): uutils に乗り続けつつ ls だけ退避できるが、touch/stat 等の将来のマルチバイト地雷が残る。日本語ファイルを日常的に扱うため、全体を GNU に揃える方を採用。
- エイリアス維持 (現状): 対話 bash 限定で `command ls`・絶対パス・スクリプトでは効かず、根治にならない。

## スコープ / 影響範囲

- ls 以外の coreutils (cat/cp/mv/rm/...) も GNU 標準挙動になる。GNU は歴史的標準であり一般に望ましい変化。
- パッケージ衝突: 現状の `home.packages` に coreutils 系バイナリを提供するものは無く、衝突しない。
- mac 影響: flake は `homeConfigurations.wsl` (x86_64-linux) のみをビルドし、`mac = mkHome "aarch64-darwin"` はコメントアウトされた将来分。現時点で mac への影響は無い。将来 mac を有効化する際は BSD ls → GNU ls の挙動変化に留意する。

## 確認方法 (home-manager switch 後)

- `type ls` が `~/.nix-profile/bin/ls` を指す
- `ls --version` が `GNU coreutils` を表示する
- 日本語ファイル名がエイリアスなしでそのまま表示される (実 PTY で生 UTF-8 バイトを出力する)

## 反映手順

1. chezmoi ソース `dot_config/home-manager/home.nix` を編集
2. `chezmoi diff` で差分確認 → `chezmoi apply`
3. `home-manager switch --flake ~/.config/home-manager#wsl` (`hms`)
4. 新しいターミナルを開いて確認

## PR 運用

- master 直 push 禁止、PR ベース。日本語コミットメッセージ。
- 本対応は新ブランチ・新 PR にまとめ、エイリアスのみの PR #11 はクローズして一本化する (#11 が先にマージ済みの場合は新 PR でエイリアス削除 + coreutils 追加)。

## 未決事項

- uutils 上流への issue 報告 (ls の TTY マルチバイト表示) を行うかは別途判断する。本対応で手元は解決するが、報告は uutils 改善に寄与する。
