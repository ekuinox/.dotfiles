# yuri（macOS / aarch64-darwin）をホストとして追加する

## 背景

home-manager の構成は `wsl`（x86_64-linux）と `pi` / `yomogi`（aarch64-linux）の 3 ホストで、いずれも Linux を前提にしている。新しく MacBook Air（Apple Silicon、`LocalHostName` = `yuri`）を管理下に置きたい。

`flake.nix` には `mac = { system = "aarch64-darwin"; ... }` の予約コメントがあるが、`common.nix` が Linux 固有の設定を含むため、そのままでは darwin で評価が通らない。

### yuri の現状

- macOS 25.4、Apple Silicon（T8103）。ログインシェルは `/bin/zsh`
- 未導入: chezmoi、nix、home-manager、`~/.dotfiles`
- 導入済み: Homebrew（`awscli` `gh` `just` `mise` `nushell` `starship` `uv` `zoxide`、cask は `flameshot`）
- このリポジトリは `~/Documents/works/repos/git/ekuinox/.dotfiles` に clone 済み
- `~/.zshrc` が対話起動時に `nu` へ exec し、`~/.zshenv` が Homebrew の mise と cargo env を読み込む
- SSH 鍵は `id_ecdsa` のみ。署名用の `id_ed25519` は無い
- claude-code はネイティブインストーラ版（`~/.local/share/claude/versions/2.1.263`、自動更新あり）

### darwin で評価が通らない箇所

- `systemd.user.services.paseo`: home-manager は非 Linux で systemd 定義を assertion で弾く
- `strace` / `pciutils` / `usbutils`: nixpkgs 上で Linux 限定

## 方針

Linux 固有の設定を `hosts/linux.nix` へ切り出し、`common.nix` を OS 非依存にする。yuri 固有の差分は `hosts/yuri.nix` に置く。`yomogi` が `pi.nix` を継承する既存の構成に倣い、分岐は `flake.nix` の `hosts` 定義に集約して「どのホストが何を読むか」を一箇所で読めるようにする。

`common.nix` 内で `lib.mkIf pkgs.stdenv.isLinux` を使う案も検討したが、`common.nix` が条件だらけになり共通設定の見通しが落ちるため採らない。

## リポジトリ側の変更

### `hosts/linux.nix`（新規）

Linux 3 ホストが共通で読む。`common.nix` から次を移す。

- Linux 限定パッケージ: `strace`、`pciutils`、`usbutils`
- `coreutils`: Ubuntu 標準の uutils ls が非 ASCII ファイル名を化けさせる問題への対策であり、macOS には該当しない。yuri で BSD ls を上書きしないよう Linux 限定にする
- `podman`、`podman-compose`、`docker` / `docker-compose` 互換ラッパー、および `~/.config/containers/` の `policy.json` / `registries.conf` / `containers.conf`: macOS では podman machine（VM）が別途必要で、ラッパーがそのままでは機能しない
- `paseo` パッケージと `systemd.user.services.paseo`（`iproute2` 参照を含む）: リモートからエージェントを操作する常駐サーバーで、手元のノートでは用途が薄い。darwin ビルドのリスクも避ける

モジュール引数として `paseo` を受け取る。

### `common.nix`

- 上記を削除し、モジュール引数から `paseo` を落とす
- `hms` エイリアスを `programs.bash.shellAliases` から `home.shellAliases` へ移す。bash と zsh の両方に効くようになり、ホスト鍵の埋め込み（`${host}`）は変わらない
- `programs.bash` はそのまま残す。macOS でも bash は存在し、スクリプト実行時の設定として無害

### `hosts/yuri.nix`（新規）

- `programs.zsh.enable = true`。macOS の既定シェルに乗せることで、starship / zoxide / fzf / mise / direnv / yazi の zsh 統合と `home.shellAliases` の `hms` が home-manager 生成の `.zshrc` に入る
- `programs.nushell` を有効化する。`exec nu` による自動起動はやめ、使いたいときに手で起動する。管理下に置かないと starship 等の初期化ファイルが生成時の絶対パスを抱えたまま取り残される（Homebrew 版 starship を外した際に実際に壊れた）。`home.shellAliases` は home-manager が nushell にも渡すが、nushell は `#` をコメント開始として扱うため、flake 参照を含む `hms` だけは絶対パスをクォートした形へ `lib.mkForce` で差し替える
- `programs.nushell` の `settings` で `show_banner` と `edit_mode` を既定として固定する
- `home.sessionPath` に `~/.cargo/bin` を追加し、現在 `~/.zshenv` が担っている cargo の PATH 設定を home-manager 側へ引き取る。`home.sessionPath` は bash / zsh にしか届かないため、nushell には `programs.nushell.extraEnv` で同じパスを通す。値は `hosts/yuri.nix` の `let` で 1 箇所に持ち、片方だけ更新する事故を防ぐ

### `flake.nix`

- `hosts` に `yuri = { system = "aarch64-darwin"; modules = [ ./hosts/yuri.nix ]; }` を追加
- `wsl` / `pi` / `yomogi` の `modules` に `./hosts/linux.nix` を追加
- `extraSpecialArgs` の `paseo` / `herdr` は遅延評価のため、yuri がどちらも参照しない限り darwin 版パッケージは forced されない。既存の herdr（wsl 限定）と同じ理屈で、`aarch64-darwin` 版の有無に関係なく評価が通る
- `mac` の予約コメントは `yuri` の追加で役目を終えるため削除する

### `dot_claude/settings.json.tmpl`

`chezmoi apply` は `~/.claude/settings.json` をテンプレートの内容で上書きするため、yuri の現行設定のうち失われるものがある。

- `figma@claude-plugins-official` は `enabledPlugins` に追加する。figma のリモート MCP は `run_onchange_register-figma-mcp.sh.tmpl` が非 Windows で登録する建て付けであり、プラグイン有効化を共通テンプレートに置くほうが整合する
- `theme: auto` と `skipAutoPermissionPrompt: true` は共通テンプレートの値（`dark` / 未設定）に統一する。全ホストへ波及するため yuri 単独の都合では変えない

### `dot_config/git/allowed_signers`

`git-setup-signing` の出力に従い、yuri の公開鍵を 1 行追加する。鍵はセットアップ中に生成するため、行の追加は手順の途中で行う。

### `README.md`

- home-manager のホスト一覧の説明に `yuri`（macOS）を追記し、`<host>` の現状列挙を更新する
- macOS でのセットアップ差分（nix インストーラ、Homebrew との住み分け）を補う

## yuri のセットアップ手順

1. `~/.dotfiles` を既存 clone へのシンボリックリンクにする。`.chezmoi.toml.tmpl` が全ホスト共通で `sourceDir = ~/.dotfiles` を指定しているため、repos 配下でリポジトリを一元管理する既存のレイアウトを崩さずに合わせられる
2. chezmoi を公式インストーラで `~/.local/bin` に入れ、`chezmoi init --source ~/.dotfiles` で設定を生成する。`chezmoi diff` で差分を確認してから `chezmoi apply` する
3. nix を Determinate インストーラで入れる。`~/.config/nix/nix.conf` は手順 2 で配置済みのため flakes は有効
4. `nix run home-manager/master -- switch -b bak --flake ~/.config/home-manager#yuri` で初回反映する
5. `git-setup-signing` を実行して `id_ed25519` を生成・GitHub へ登録し、出力された行を `dot_config/git/allowed_signers` に追加、`chezmoi apply` 後に再実行して検証まで通す
6. Homebrew の重複を削除する（`awscli` `gh` `just` `mise` `nushell` `starship` `zoxide`）。`uv`、cask の `flameshot`、および `giflib` / `jpeg` / `librsvg` / `pkgconf`（依存）は残す
7. ネイティブ版 claude-code（`~/.local/bin/claude` と `~/.local/share/claude`）を削除する。nix 版へ統一するが、作業中のセッションがネイティブ版で動いているため最後に行う

## 検証

- yuri で `home-manager build --flake ~/.config/home-manager#yuri` を通す
- 既存ホストの構成は yuri 上ではビルドできない（別 system のバイナリが要る）ため、`nix eval ~/.config/home-manager#homeConfigurations.wsl.activationPackage.drvPath` のように評価だけを通し、`hosts/linux.nix` の切り出しで評価エラーが出ないことを wsl / pi / yomogi それぞれについて確認する
- 反映後、新しい zsh で `hms`、`starship`、`zoxide`、`mise`、`fzf` が効くことを確認する
- `git-setup-signing` が署名と検証の両方を通すところまで確認する

## リスク

`gcc`、`proton-pass-cli`、`mtr`、`dnsutils` など、`common.nix` に残るパッケージのうち darwin でビルドできないものが他にも出る可能性がある。nix を入れるまで評価できないため、初回 `home-manager switch` のエラーを見て該当分を `hosts/linux.nix` へ移す形で対処する。

## やらないこと

- WezTerm 設定の macOS 展開。yuri に WezTerm は入っていない
- Homebrew の完全撤去。`uv` と GUI アプリ（cask）は引き続き Homebrew で管理する
