# SSH 署名付きコミットの導入

## 背景

`works/repo/wonder-soft/d-prompt-manager` の `.claude/references/commit-style.md` が「`-S` オプションを必ずつけて署名付きのコミットを指定してください」と要求しており、署名鍵が無いため従えない状態だった。

当初は GPG が必要だと想定していたが、`-S` は「GPG で署名する」ではなく「`gpg.format` で指定した方式で署名する」の意味であり、SSH 署名でも満たせる。実際に `gpg.format=ssh` で `git commit -S` を実行し、`%G?` が `G`、`git verify-commit` が終了コード 0 になることを確認した。

要求元は GitHub のブランチ保護でも CI でもない。当該リポジトリに ruleset は無く、`main` にブランチ保護も掛かっておらず、ワークフローにも署名検証は無い。したがって「`git commit -S` が成功すること」だけが要件になる。

## SSH 署名を選ぶ理由

- 既存の `~/.ssh/id_ed25519` を流用でき、新たな鍵の生成も GitHub への鍵追加も最小で済む。
- この鍵にはパスフレーズが無いため、pinentry・エージェントのキャッシュ・「端末を持たない文脈で署名に失敗する」といった GPG 特有の問題が発生しない。
- 署名の検証に使う `allowed_signers` は公開鍵しか含まないため、public なこのリポジトリで宣言的に管理できる。GPG では鍵 ID をリポジトリ外へ隔離する必要があった。

## ゴール

- `git commit -S` が全ホストで成功する（`commit.gpgsign` により `-S` 無しでも署名される）。
- 自分のコミットをローカルで検証できる（`git log --show-signature` が `Good "git" signature` を返す）。
- GitHub 上で Verified バッジが付く。
- 秘密鍵はリポジトリに入れない。

## allowed_signers の扱い

SSH 鍵は GPG と違い鍵自体に UID を持たないため、「メールアドレス → 公開鍵」の対応表を外部に持つ必要がある。これが `allowed_signers` であり、`gpg.ssh.allowedSignersFile` で git に場所を教える。

この表を用意しないと、署名自体は成功するものの検証が一切できない。実測した挙動は次のとおり。

| 状態 | `%G?` | `git verify-commit` | `--show-signature` |
|---|---|---|---|
| 未設定 | `N` | 終了コード 1 | `No signature` |
| 設定済み・表に載っている鍵 | `G` | 終了コード 0 | `Good "git" signature for ...` |
| 設定済み・表に無い鍵 | `U` | 終了コード 1 | - |

未設定時に `No signature`（署名なし）と表示される点は紛らわしい。実際には署名は付いており、検証できないだけである。

管理は chezmoi が `dot_config/git/allowed_signers` として行う。公開鍵しか含まないため public リポジトリに置いて問題はない。ホストごとに鍵が異なるため、ホストを追加したらこのファイルに 1 行足す。全ホストぶんの鍵を 1 ファイルに集約することで、あるホストで作ったコミットを別のホストでも検証できる。

管理対象は自分の鍵のみとする。他人の公開鍵は `gh api users/<login>/ssh_signing_keys` で取得できるが、principal に書くメールアドレスとの対応付けを自前で持つ必要があり、他人のコミットの検証は GitHub の Verified バッジに委ねる。

`git-setup-signing` はこのファイルを書き換えない。chezmoi と二重管理になり `chezmoi apply` で上書きされるため、必要な行を出力して手動での追加を促すに留める。

## chezmoi の変更

### dot_gitconfig

```ini
[user]
	signingkey = ~/.ssh/id_ed25519.pub
[commit]
	gpgsign = true
[tag]
	gpgsign = true
[gpg]
	format = ssh
[gpg "ssh"]
	allowedSignersFile = ~/.config/git/allowed_signers
```

`user.signingkey` と `allowedSignersFile` はチルダ展開が効くことを実測で確認済み。パスは全ホストで同一（鍵の実体だけがホストごとに違う）ため、ホスト固有設定として `~/.gitconfig.local` へ逃がす必要はなく、ここに直接書ける。

### dot_config/git/allowed_signers

```
depkey@me.com namespaces="git" ssh-ed25519 AAAA... ekuinox@Hizake
```

`namespaces="git"` はこの鍵を git の署名検証にのみ使うことを明示し、他用途の署名に流用されるのを防ぐ。

`dot_config/git` は `exact_` 接頭辞を持たないため、chezmoi はこのディレクトリ内の未管理ファイルを削除しない。既存の `ignore` と共存する。

## home-manager の変更

`git-setup-signing` を `home.packages` に追加する。既存の `gog-setup-credentials` と同じ構成（`packages/*.nix` の `writeShellApplication` + `scripts/*.sh` を `readFile`）で実装する。

署名には `ssh-keygen`（`gpg.ssh.program` の既定値）を使う。openssh は各ホストに導入済みのため、パッケージの追加は行わない。

## git-setup-signing

ホストごとに 1 回実行する。処理の流れ:

1. `~/.ssh/id_ed25519` が無ければ ed25519 鍵を生成する（パスフレーズは対話入力）。
2. 自分の鍵の行が `~/.config/git/allowed_signers` にあるか確認する。無ければ追加すべき行を出力し、chezmoi ソースへの追加を促して終了する。
3. GitHub へ signing key として登録する（`gh ssh-key add --type signing`）。既に登録済みならスキップする。
4. 使い捨てリポジトリで `git commit -S` と `git verify-commit` を実行し、署名と検証の両方が通ることを確認する。

### 失敗時の扱い

- `writeShellApplication` により `set -euo pipefail` と shellcheck が効く。
- GitHub への登録には `gh` のトークンに `admin:ssh_signing_key` スコープが必要。無い場合は処理を止めず、`gh auth refresh -s admin:ssh_signing_key` を案内したうえで公開鍵を出力し、手動登録の退路を残す。GitHub への登録は署名の成立とは独立している。
- 手順 2 で終了した場合は非ゼロ終了する。設定を反映してから再実行すれば続きから通る。

## 既知の制約

- `commit.gpgsign = true` は global 設定のため、署名したくないリポジトリでは `git config commit.gpgsign false` を個別に設定する。
- 認証用の `id_ed25519` を署名にも流用する。用途ごとに鍵を分けるほうが本来は望ましいが、鍵の管理点を増やさないことを優先した。
- 既存のコミットは遡って署名されない。

## 動作確認

- `nix build .#homeConfigurations.wsl.activationPackage` が通ること。
- `chezmoi diff` の差分が意図どおりであること。
- `git-setup-signing` が最後まで通ること。
- `git log --show-signature` が `Good "git" signature` を返すこと。
- GitHub に push したコミットに Verified バッジが付くこと。

## スコープ外 (YAGNI)

- pi / yomogi での設定。同じ `git-setup-signing` を叩き allowed_signers に 1 行足すだけで、手順は変わらない。
- 他人の公開鍵の `allowed_signers` への取り込み。
- Proton Pass（`pass-cli ssh-agent`）での鍵管理。SSH 署名にしたことで選択肢としては開けたが、今回は既存鍵の流用に留める。
- 署名専用鍵の分離、鍵ローテーション（`valid-after` / `valid-before`）の運用。
