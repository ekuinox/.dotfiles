# dotfiles

chezmoi で管理する個人 dotfiles。
秘密情報・キャッシュは含めない。

## 管理対象

- `~/.gitconfig`（`[user]` と署名設定。マシン固有設定は `~/.gitconfig.local` に置く）
- `~/.config/git/ignore`
- `~/.config/git/allowed_signers`（コミット署名の検証に使う公開鍵の一覧）
- `~/.config/home-manager/`（nix / home-manager 設定。Linux / macOS のみ）
- `~/.config/nix/nix.conf`（flakes 有効化。Linux / macOS のみ）
- `~/.claude/CLAUDE.md`, `~/.claude/hooks/`, `~/.claude/skills/`
- `~/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1`（Windows のみ）
- winget パッケージ一覧（Windows のみ。`.chezmoidata/packages.toml` に列挙、`chezmoi apply` で未導入のものを自動インストール）

## 新マシンでの展開

OS ごとに以下を上から順に実行する（コピペでよい）。

### Windows

```powershell
# 1. git と gh を入れる（Windows 11 標準の winget）
winget install --id Git.Git -e
winget install --id GitHub.cli -e

# 2. GitHub にログインする（ブラウザ認証。途中の git 認証連携は Yes を選ぶ）
gh auth login

# 3. chezmoi を入れて一気に展開する
iex "&{$(irm 'https://get.chezmoi.io/ps1')} -- init --apply --source ~/.dotfiles ekuinox/.dotfiles"
```

### Linux / macOS

```sh
# 1. git と gh を入れる（ディストリ/OS に合わせる）
#   Debian/Ubuntu/Raspberry Pi OS:  sudo apt update && sudo apt install -y git gh
#   Fedora:                          sudo dnf install -y git gh
#   Arch:                            sudo pacman -S --needed git github-cli
#   macOS (Homebrew):                brew install git gh

# 2. GitHub にログインする（ブラウザ認証。途中の git 認証連携は Yes を選ぶ）
gh auth login

# 3. chezmoi を ~/.local/bin に入れて一気に展開する
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply --source ~/.dotfiles ekuinox/.dotfiles
```

- `~/.local/bin` が PATH に無い環境では、展開後に `export PATH="$HOME/.local/bin:$PATH"` をシェルの rc に追加する（次回以降の `chezmoi` コマンド用。`chezmoi apply` 自体は上記一発で完了している）。
- Windows 固有の設定（PowerShell プロファイル、`~/.claude/settings.json` の toast フック・`defaultShell` 等）は `.chezmoiignore` と `*.tmpl` の OS 分岐により、Linux / macOS では自動的に除外される。

### nix / home-manager（Linux / macOS のみ）

chezmoi 展開後、nix と home-manager を別途セットアップする。

1. nix をインストールする（公式または Determinate インストーラ）。
2. chezmoi 展開で `~/.config/nix/nix.conf`（flakes 有効化）と `~/.config/home-manager` が配置済みなので、初回は home-manager を直接実行して反映する。flakes は nix.conf で有効化済みのため `--extra-experimental-features` は不要。

   ```sh
   nix run home-manager/master -- switch -b bak --flake ~/.config/home-manager#wsl
   ```

3. 2 回目以降は home-manager が PATH に入るため、次で反映する（`<host>` は対象マシンの鍵。現状は `wsl` / `pi` / `yomogi` / `yuri`）。

   ```sh
   home-manager switch --flake ~/.config/home-manager#<host>
   ```

構成は `common.nix`（OS を問わない全ホスト共通）と `hosts/<host>.nix`（ホスト固有）に分かれる。`flake.nix` の `hosts` がホストごとに読み込むモジュールを定義する。

- `hosts/linux.nix`: Linux 3 ホスト（`wsl` / `pi` / `yomogi`）が共通で読む。systemd ユニット、Linux 限定パッケージ、podman 一式、GNU coreutils はここに置く。これらは darwin で評価が通らないため `common.nix` には置かない。
- `hosts/wsl.nix`: WSL 固有。herdr（AI コーディングエージェント用ターミナルワークスペース管理）を入れて設定する。
- `hosts/pi.nix`: Raspberry Pi 共通。`yomogi` が継承するため、pi 系で共通化したい設定はここに書けば yomogi にも反映される。
- `hosts/yomogi.nix`: 自宅 Pi の個体名。door-lock 中継の設定を足す。
- `hosts/yuri.nix`: MacBook Air（Apple Silicon）。macOS の既定シェルに合わせて `programs.zsh` を有効にする。`linux.nix` は読まない。

`.bashrc` は home-manager（`programs.bash`）が所有する。yuri では `programs.zsh` と `programs.nushell` も有効なため、`.zshrc` / `.zshenv` と nushell の `config.nu` / `env.nu` も home-manager の所有になる。既存のファイルがある初回は `-b bak` で退避される。

### コミット署名（SSH 鍵）

`~/.gitconfig` で `commit.gpgsign` を有効にしており、`gpg.format = ssh` により GPG ではなく SSH 鍵で署名する。ホストごとに 1 回だけ次を実行する。

```sh
git-setup-signing
```

`~/.ssh/id_ed25519` が無ければ生成し、GitHub へ signing key として登録し、使い捨てリポジトリで署名と検証が通るところまで確認する。何度実行してもよい。

新しいホストでは、初回に `dot_config/git/allowed_signers` へそのホストの公開鍵を 1 行足す必要がある。`git-setup-signing` が追加すべき行をそのまま出力するので、chezmoi ソースに貼って `chezmoi apply` してから再実行する。SSH 鍵は GPG と違い鍵自体に UID を持たないため、この「メールアドレス → 公開鍵」の対応表が無いと検証ができない。公開鍵しか含まないためリポジトリで管理して問題ない。

GitHub への自動登録には `gh` のトークンに `admin:ssh_signing_key` スコープが必要。無い場合はコマンドが公開鍵と手順を出力するので、`gh auth refresh -s admin:ssh_signing_key` のうえ再実行するか、手動で登録する。認証用の鍵として登録済みでも、署名用は別枠のため改めて登録が必要。

署名したくないリポジトリでは `git config commit.gpgsign false` を個別に設定する。

### 共通の補足

- このリポジトリは public のため、秘密情報（鍵・トークン・資格情報）は一切含めない。`allowed_signers` に置くのは公開鍵のみ。clone に認証は不要だが、`gh auth login` の対話で「Authenticate Git with your GitHub credentials?」に Yes を選んでおくと push 時の認証が通る（このために git も入れている）。
- `sourceDir` は全ホストで `~/.dotfiles`。リポジトリの `.chezmoi.toml.tmpl` から `chezmoi init` が自動生成するため、設定の手書きは不要。別の場所にリポジトリを置きたい場合は `~/.dotfiles` をそこへのシンボリックリンクにする。
- 初回の chezmoi 自体は公式インストーラで入る（ブートストラップ用）。Linux / macOS では claude-code と chezmoi を home-manager（nix）が `home.packages` で管理するため、`home-manager switch` 後は nix 側の chezmoi も利用できる。
- mise 本体は home-manager（`programs.mise`）が入れるが、グローバルの tool バージョンは固定しない方針のため mise の `config.toml` は chezmoi 管理対象外。node 等が必要ならプロジェクト単位の `mise.toml` 等で都度入れる。
- macOS では Homebrew と併用する。CLI は home-manager（nix）に寄せ、Homebrew は GUI アプリ（cask）と nixpkgs に無いものだけに使う。両方に同じコマンドを入れると PATH 順で実体が変わり分かりにくくなる。

## winget パッケージ管理（Windows）

普段使う Windows アプリは winget で一覧管理する。
アンインストールは扱わない（一覧から消しても既存マシンからは削除されない）。

- 一覧: `.chezmoidata/packages.toml` の `[winget] ids` に winget のパッケージ ID を列挙する。
- 導入: `run_onchange_install-winget-packages.ps1.tmpl` が `chezmoi apply` 時に実行され、一覧が前回から変わっていれば未導入のものだけ `winget install` する（既存はスキップ）。
- 追加: `chezmoi edit ~/.dotfiles/.chezmoidata/packages.toml` 相当でソースの `packages.toml` に ID を足し、`chezmoi apply` する。
- ID の調べ方: `winget search <名前>` で出る「ID」列の値（例: `Microsoft.VisualStudioCode`）を使う。
- Windows 以外では、テンプレートの OS ガードによりスクリプトは実行されない。

## Figma MCP（Claude Code）

Claude Code から Figma を参照するためのリモート MCP サーバーを user スコープで登録する。
リモート版（`https://mcp.figma.com/mcp`）を使い、認証はブラウザ OAuth なので設定にシークレットは含めない。

- 導入: `run_onchange_register-figma-mcp.sh.tmpl` が `chezmoi apply` 時に実行され、未登録なら `claude mcp add --scope user --transport http figma https://mcp.figma.com/mcp` を実行する（登録済みはスキップ）。
- 認証: 登録後に `claude` を起動し、`/mcp` から `figma` を選んで Authenticate（ブラウザで Allow access）する。`~/.claude.json` に登録され、認証トークンもそこに保存される（このリポジトリでは管理しない）。
- 確認: `claude mcp get figma` でスコープと接続状態を確認できる。
- Windows 以外で実行される（テンプレートの OS ガード）。Claude Code を WSL/Linux 側で使う前提。

## マシン固有設定

`~/.gitconfig.local` に `[safe]` directory などマシン固有の git 設定を置く（このリポジトリでは管理しない）。

## 日常運用

```
chezmoi edit <file>   # ソースを編集
chezmoi apply         # home へ反映
chezmoi cd            # ソースディレクトリへ移動して git commit / push
```

nix 設定（`~/.config/home-manager`）は通常どおり `chezmoi edit` → `chezmoi apply` で編集・反映する。ただし `nix flake update` は chezmoi の**ターゲット側** `~/.config/home-manager/flake.lock` を書き換えるため、更新後はソースへ取り込み直す。

```sh
nix flake update --flake ~/.config/home-manager   # lock 更新（ターゲット側）
chezmoi re-add ~/.config/home-manager/flake.lock  # ソースへ取り込み直す
home-manager switch --flake ~/.config/home-manager#<host>
```
