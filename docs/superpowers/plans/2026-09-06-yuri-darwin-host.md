# yuri（macOS ホスト）追加 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MacBook Air（Apple Silicon、`LocalHostName` = `yuri`）を chezmoi + home-manager の管理下に置き、`home-manager switch --flake ~/.config/home-manager#yuri` で再現できる状態にする。

**Architecture:** `common.nix` に混在している Linux 固有設定（systemd ユニット、Linux 限定パッケージ、podman 一式、coreutils）を `hosts/linux.nix` へ切り出して `common.nix` を OS 非依存にする。yuri 固有の差分は `hosts/yuri.nix` に置き、どのホストが何を読むかは `flake.nix` の `hosts` 定義に集約する。

**Tech Stack:** chezmoi、nix flakes、home-manager（standalone）、Homebrew（GUI と `uv` のみ残す）

## Global Constraints

- ドキュメント・コメント・コミットメッセージは日本語。絵文字は使わない
- home 側ファイル（`~/.gitconfig` 等）を直接編集しない。必ず chezmoi source を編集して `chezmoi apply` で反映する
- 反映前に `chezmoi diff` で差分を確認する
- master へ直接 push しない。作業ブランチは `feat/yuri-darwin-host`
- 秘密情報はコミットしない。`allowed_signers` に入れてよいのは公開鍵のみ
- `nix flake update` でターゲット側 `flake.lock` を更新したら `chezmoi re-add` でソースへ取り込み直す
- コミット末尾には次の 2 行を付ける

  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01Wcz5d2BcQV9z3bU7byDqYc
  ```

## File Structure

| ファイル | 責務 | 変更 |
| --- | --- | --- |
| `dot_config/home-manager/common.nix` | OS 非依存の共通設定（パッケージ、`programs.*`、シェル共通エイリアス） | 変更 |
| `dot_config/home-manager/hosts/linux.nix` | Linux 3 ホスト共通。systemd ユニットと Linux 限定パッケージ | 新規 |
| `dot_config/home-manager/hosts/yuri.nix` | yuri 固有。zsh 有効化、nushell、cargo の PATH | 新規 |
| `dot_config/home-manager/flake.nix` | ホスト名 → system とモジュール一覧の対応表 | 変更 |
| `dot_claude/settings.json.tmpl` | 全ホスト共通の Claude Code 設定 | 変更 |
| `dot_config/git/allowed_signers` | 署名検証用の「メールアドレス → 公開鍵」対応表 | 変更 |
| `README.md` | 展開手順とホスト一覧 | 変更 |

---

### Task 1: yuri に chezmoi を導入して展開する

`~/.dotfiles` を既存 clone へのシンボリックリンクにし、chezmoi をブートストラップして現在のブランチ内容を展開する。この時点ではリポジトリの darwin 対応はまだ入っていないが、`~/.config/nix/nix.conf` と `~/.config/home-manager/` を先に配置しておくことで、後続の nix 導入がそのまま進められる。

**Files:**
- 変更なし（yuri のローカル環境のみ）

**Interfaces:**
- Consumes: なし
- Produces: `~/.dotfiles`（シンボリックリンク）、`~/.local/bin/chezmoi`、`~/.config/chezmoi/chezmoi.toml`、展開済みの `~/.config/nix/nix.conf` と `~/.config/home-manager/`

- [ ] **Step 1: `~/.dotfiles` をシンボリックリンクにする**

```bash
ln -s "$HOME/Documents/works/repos/git/ekuinox/.dotfiles" "$HOME/.dotfiles"
ls -ld "$HOME/.dotfiles"
```

期待: `~/.dotfiles -> /Users/ekuinox/Documents/works/repos/git/ekuinox/.dotfiles` と表示される。

- [ ] **Step 2: chezmoi をブートストラップする**

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
"$HOME/.local/bin/chezmoi" --version
```

期待: バージョンが表示される。nix 導入後は home-manager の `pkgs.chezmoi` が PATH に入るが、ここではブートストラップ用に公式インストーラを使う。

- [ ] **Step 3: chezmoi の設定を生成する**

```bash
"$HOME/.local/bin/chezmoi" init --source "$HOME/.dotfiles"
cat "$HOME/.config/chezmoi/chezmoi.toml"
```

期待: `sourceDir = "~/.dotfiles"` の 1 行。`.chezmoi.toml.tmpl` から生成される。リポジトリは既に clone 済みなので引数にリポジトリ名は渡さない。

- [ ] **Step 4: 差分を確認する**

```bash
"$HOME/.local/bin/chezmoi" diff
```

期待: 次が主な差分として出る。内容を読んで、意図しない上書きが無いことを確認する。

- `~/.gitconfig`: 現行の `[user]` のみの内容が、署名設定と gh credential helper を含む内容に置き換わる
- `~/.config/git/ignore`、`~/.config/git/allowed_signers`: 新規
- `~/.claude/CLAUDE.md`、`~/.claude/hooks/check-gh-markdown.sh`、`~/.claude/skills/`: 新規
- `~/.claude/settings.json`: 現行の内容が共通テンプレートに置き換わる（`figma@claude-plugins-official`、`theme: auto`、`skipAutoPermissionPrompt` が消える。figma プラグインは Task 4 でテンプレート側に戻す）
- `~/.config/nix/nix.conf`、`~/.config/home-manager/`: 新規

- [ ] **Step 5: 展開する**

```bash
"$HOME/.local/bin/chezmoi" apply
```

期待: エラーなく完了する。`run_onchange_register-figma-mcp.sh` が走り、`registering figma MCP (remote, user scope)` または `skip (already registered): figma` のいずれかが出る。

- [ ] **Step 6: 展開結果を確認する**

```bash
ls -l "$HOME/.config/home-manager" "$HOME/.config/nix/nix.conf"
git -C "$HOME/.dotfiles" status --short
```

期待: `common.nix` / `flake.nix` / `hosts/` / `packages/` / `scripts/` が `~/.config/home-manager` に置かれている。chezmoi source（リポジトリ）側に変更は無い。

---

### Task 2: yuri に nix を導入する

**Files:**
- 変更なし（yuri のローカル環境のみ）

**Interfaces:**
- Consumes: Task 1 が配置した `~/.config/nix/nix.conf`（flakes 有効化）
- Produces: PATH 上の `nix`

- [ ] **Step 1: Determinate インストーラで nix を入れる**

このコマンドは sudo と対話確認を伴うため、ユーザー自身がターミナルで実行する（Claude Code では先頭に `!` を付けて実行できる）。

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

期待: インストールが完了し、新しいシェルを開くよう案内される。

- [ ] **Step 2: 新しいシェルで nix と flakes を確認する**

```bash
nix --version
nix flake --help >/dev/null && echo "flakes ok"
```

期待: バージョンが表示され、`flakes ok` が出る。`experimental-features` は `~/.config/nix/nix.conf` で有効化済みのため `--extra-experimental-features` は不要。`nix` が見つからない場合はシェルを開き直す。

---

### Task 3: home-manager を darwin 対応にする

`common.nix` から Linux 固有の設定を `hosts/linux.nix` へ切り出し、`hosts/yuri.nix` と `flake.nix` の `yuri` エントリを追加する。

**Files:**
- Create: `dot_config/home-manager/hosts/linux.nix`
- Create: `dot_config/home-manager/hosts/yuri.nix`
- Modify: `dot_config/home-manager/common.nix`
- Modify: `dot_config/home-manager/flake.nix:29-46`

**Interfaces:**
- Consumes: `flake.nix` の `extraSpecialArgs` が渡す `host`（現ホスト名の文字列）、`paseo`（`paseo.packages.${system}.default`）、`herdr`
- Produces: `homeConfigurations.yuri`（`aarch64-darwin`）。`common.nix` はモジュール引数として `{ pkgs, lib, host, ... }` のみを取り、`config` と `paseo` は取らなくなる

- [ ] **Step 1: `hosts/linux.nix` を作る**

```bash
cat > dot_config/home-manager/hosts/linux.nix <<'EOF'
# Linux 共通のホスト設定。wsl / pi / yomogi が読む。
# common.nix を OS 非依存に保つため、Linux でしか成立しない設定はここへ置く。
#   - systemd.user.* は home-manager が非 Linux で assertion により弾く
#   - strace / pciutils / usbutils は nixpkgs 上で Linux 限定
#   - podman 一式は macOS だと podman machine(VM) が別途要り、ラッパーが成立しない
#   - coreutils は Ubuntu の uutils ls 対策であり、macOS では BSD ls を上書きしてしまう
{ config, pkgs, paseo, ... }:
let
  # docker は導入せず podman へ委譲する。エイリアスは対話シェルにしか効かず
  # justfile やスクリプトの sh からは見えないため、PATH 上に実体のラッパーを置く。
  docker-compat = pkgs.writeShellScriptBin "docker" ''
    exec ${pkgs.podman}/bin/podman "$@"
  '';
  docker-compose-compat = pkgs.writeShellScriptBin "docker-compose" ''
    exec ${pkgs.podman-compose}/bin/podman-compose "$@"
  '';
in
{
  # common.nix の home.packages リストへマージされる。
  home.packages = [
    # Ubuntu 26.04 標準の uutils ls はロケールを見ず、日本語など非 ASCII の
    # ファイル名を端末で ? や 8 進エスケープに化けさせる（最新版でも未修正）。
    # 成熟した GNU coreutils を PATH 先頭(nix-profile)に置き uutils(/usr/bin) を上書きする。
    pkgs.coreutils
    # lspci。PCI デバイス一覧
    pkgs.pciutils
    pkgs.podman
    pkgs.podman-compose
    pkgs.strace
    # lsusb。USB デバイス一覧
    pkgs.usbutils
    docker-compat
    docker-compose-compat
    paseo
  ];

  # rootless podman 用の containers 設定。非 NixOS では /etc/containers を
  # 誰も用意しないため、ユーザー側 (~/.config/containers) を home-manager で管理する。
  home.file = {
    # イメージ署名ポリシー。これが無いと "no policy.json file found" で起動できない
    ".config/containers/policy.json".text = ''
      {
        "default": [{ "type": "insecureAcceptAnything" }]
      }
    '';
    # 短縮名 (hello-world 等) を docker.io から解決できるようにする
    ".config/containers/registries.conf".text = ''
      unqualified-search-registries = ["docker.io"]
    '';
    # docker compose ... 実行時の "Executing external compose provider" 警告を抑制する
    ".config/containers/containers.conf".text = ''
      [engine]
      compose_warning_logs = false
    '';
  };

  # Paseo デーモンを常駐させる。状態は $HOME 配下 (~/.paseo, ~/.claude) に
  # 永続するため、再起動でエージェント（セッション）は保持され、進行中ターン
  # だけが中断される。systemd user の環境は最小限で .bashrc も /etc/profile も
  # 読まないため、デーモンが生成するエージェント (claude 等) 用に PATH を明示する。
  # nix 本体 (nix, nix-build 等) は ~/.nix-profile ではなく multi-user の default
  # プロファイル配下にあるので、エージェントから nix が引けるよう明示的に含める。
  # ヘッドレス運用で未ログイン時も動かすには `loginctl enable-linger` が別途必要。
  systemd.user.services.paseo = {
    Unit = {
      Description = "Paseo daemon (control AI coding agents remotely)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      # ダウンロードはブラウザが daemon の HTTP エンドポイントへ直接アクセスする
      # 方式のため、0.0.0.0 待ち受け時はブラウザに広告する LAN IP が必要になる。
      # paseo の既定選択(インターフェイス名の辞書順で最初の非内部 IPv4)は
      # Docker ブリッジ(br-*, 172.19.0.1 等)を誤選択するので、既定ルートの
      # 送信元アドレスから起動時に動的解決して PASEO_PRIMARY_LAN_IP に渡す。
      # インターフェイス名に依存せず、DHCP や eth0→wlan0 の切り替えにも追従し、
      # IP の直書きを避けられる。
      ExecStart = pkgs.writeShellScript "paseo-start" ''
        export PASEO_PRIMARY_LAN_IP="$(${pkgs.iproute2}/bin/ip -4 route get 1.1.1.1 2>/dev/null | ${pkgs.gnugrep}/bin/grep -oP 'src \K\S+')"
        exec ${paseo}/bin/paseo start --foreground
      '';
      Restart = "on-failure";
      RestartSec = 5;
      Environment = [
        "PATH=${config.home.profileDirectory}/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"
      ];
    };
    Install.WantedBy = [ "default.target" ];
  };
}
EOF
```

- [ ] **Step 2: `hosts/yuri.nix` を作る**

```bash
cat > dot_config/home-manager/hosts/yuri.nix <<'EOF'
# yuri: MacBook Air (Apple Silicon, aarch64-darwin) 固有のホスト設定。
# macOS の既定の対話シェルは zsh のため、common.nix の programs.* が用意する
# ツール統合（starship / zoxide / fzf / mise / direnv / yazi）と home.shellAliases は
# programs.zsh を有効にして初めて対話シェルへ入る。
{ config, pkgs, ... }:
{
  home.packages = [
    # 対話シェルとして手で起動する。zsh からの自動 exec はしない
    pkgs.nushell
  ];

  # rustup 管理の cargo / rustc は nix の外にあるため、PATH は home-manager で通す。
  # 従来は ~/.zshenv の `. "$HOME/.cargo/env"` が担っていた。
  home.sessionPath = [ "$HOME/.cargo/bin" ];

  programs.zsh = {
    enable = true;
    history = {
      # 既定は $XDG_DATA_HOME/zsh/zsh_history。既存の履歴を引き継ぐため従来の場所に固定する
      path = "${config.home.homeDirectory}/.zsh_history";
      ignoreDups = true;
      ignoreSpace = true;
      size = 10000;
      save = 20000;
    };
  };
}
EOF
```

- [ ] **Step 3: `common.nix` から Linux 固有の設定を取り除く**

`dot_config/home-manager/common.nix` を次のとおり編集する。

1. 1 行目のモジュール引数から `config` と `paseo` を落とす。

   変更前:

   ```nix
   { config, pkgs, lib, host, paseo, ... }:
   ```

   変更後:

   ```nix
   { pkgs, lib, host, ... }:
   ```

2. `let` ブロックの `docker-compat` と `docker-compose-compat` の定義（コメント行を含む 9〜16 行目相当）を削除する。削除後の `let` ブロックは次のようになる。

   ```nix
   let
     # nixpkgs に無い自前パッケージは packages/ 配下に 1 ファイルずつ分離し、
     # callPackage で nixpkgs の依存（stdenv/fetchurl 等）を自動注入して読み込む。
     redmine-go = pkgs.callPackage ./packages/redmine-go.nix { };
     ntn = pkgs.callPackage ./packages/ntn.nix { };
     gog-setup-credentials = pkgs.callPackage ./packages/gog-setup-credentials.nix { };
     git-setup-signing = pkgs.callPackage ./packages/git-setup-signing.nix { };
   in
   ```

3. `home.packages` から次の行を（直前のコメント行ごと）削除する。`pkgs.coreutils` は 3 行のコメントを伴う。

   - `pkgs.coreutils`
   - `pkgs.pciutils`
   - `pkgs.podman`
   - `pkgs.podman-compose`
   - `pkgs.strace`
   - `pkgs.usbutils`
   - `docker-compat`
   - `docker-compose-compat`
   - `paseo`

4. `home.file` から `.config/containers/policy.json` / `.config/containers/registries.conf` / `.config/containers/containers.conf` の 3 定義を、先頭の 2 行コメント（`# rootless podman 用の containers 設定。...`）ごと削除する。`.nanorc` の定義は残す。

5. `programs.eza` のコメントにある「coreutils の ls を上書きしてしまうため」は、coreutils を入れないホストでも `ls` を上書きしない意図は変わらないため、次のとおり書き換える。

   変更前:

   ```nix
     # ls 代替。enableBashIntegration を有効にすると ls→eza エイリアスが張られ
     # coreutils の ls を上書きしてしまうため、意図的に enable のみとする。
     eza.enable = true;
   ```

   変更後:

   ```nix
     # ls 代替。enableBashIntegration を有効にすると ls→eza エイリアスが張られ
     # 既定の ls を上書きしてしまうため、意図的に enable のみとする。
     eza.enable = true;
   ```

6. `programs.bash.shellAliases` を丸ごと削除し、同じエイリアスを `home.shellAliases` として定義する。`home.shellAliases` は bash / zsh の両方へ反映されるため、yuri の zsh でも `hms` が効く。

   `programs.bash` から削除する部分:

   ```nix
         shellAliases = {
           # home-manager switch。ホスト鍵は flake から渡される現ホスト名を使う。
           hms = "home-manager switch --flake ~/.config/home-manager#${host}";
         };
   ```

   `home` ブロックの `sessionVariables = { };` の直後に追加する部分:

   ```nix
     # bash / zsh の両方へ反映される共通エイリアス。
     shellAliases = {
       # home-manager switch。ホスト鍵は flake から渡される現ホスト名を使う。
       hms = "home-manager switch --flake ~/.config/home-manager#${host}";
     };
   ```

7. ファイル末尾の `systemd.user.services.paseo = { ... };` を、直前の 7 行のコメント（`# Paseo デーモンを常駐させる。...`）ごと削除する。削除後、ファイルは `programs = { ... };` を閉じたあと `}` で終わる。

- [ ] **Step 4: `flake.nix` の `hosts` を更新する**

`dot_config/home-manager/flake.nix` の 26〜47 行目相当（`hosts` の定義とその上のコメント）を次で置き換える。

```nix
      # ホスト名 -> { system, modules }。共通設定は common.nix、ホスト固有差分は
      # hosts/*.nix に置く。linux.nix は Linux 3 ホストが共通で読む（systemd や
      # Linux 限定パッケージは darwin で評価が通らないため common.nix には置かない）。
      # yomogi は pi.nix を継承（modules に含める）しつつ、個体固有の door-lock 設定
      # （yomogi.nix）と mube モジュールを足す。
      hosts = {
        wsl = {
          system = "x86_64-linux";
          modules = [ ./hosts/linux.nix ./hosts/wsl.nix ];
        };
        # Raspberry Pi (Ubuntu, aarch64) の汎用ホスト
        pi = {
          system = "aarch64-linux";
          modules = [ ./hosts/linux.nix ./hosts/pi.nix ];
        };
        # yomogi: 自宅 Pi の個体名。pi.nix を継承し、door-lock 中継役の設定を追加する。
        # mube.homeManagerModules.default は services.mube-door-lock オプションの提供元で、
        # yomogi だけが必要とするためここでのみ import する（wsl/pi はオプションを持たない）。
        yomogi = {
          system = "aarch64-linux";
          modules = [ ./hosts/linux.nix ./hosts/pi.nix ./hosts/yomogi.nix mube.homeManagerModules.default ];
        };
        # yuri: MacBook Air (Apple Silicon)。linux.nix は読まない。
        yuri = {
          system = "aarch64-darwin";
          modules = [ ./hosts/yuri.nix ];
        };
      };
```

続けて `mkHome` の上のコメントを、paseo の参照元が linux.nix に移ったことに合わせて更新する。

変更前:

```nix
          # host は hms エイリアスの flake 参照先。paseo/herdr は system 別 package。
          # herdr を参照するのは wsl.nix のみ。pi/yomogi のモジュールは herdr を
          # 引数に取らないため、遅延評価で aarch64 版 herdr は forced されずビルドされない。
```

変更後:

```nix
          # host は hms エイリアスの flake 参照先。paseo/herdr は system 別 package。
          # paseo を参照するのは linux.nix、herdr は wsl.nix のみ。yuri のモジュールは
          # どちらも引数に取らないため、遅延評価で darwin 版は forced されずビルドされない。
```

- [ ] **Step 5: 展開して yuri の構成をビルドする**

```bash
# この時点ではまだ nix 版 chezmoi が PATH に無いため、ブートストラップ版を明示して呼ぶ
cd "$HOME/.dotfiles" && "$HOME/.local/bin/chezmoi" diff && "$HOME/.local/bin/chezmoi" apply
nix build --no-link ~/.config/home-manager#homeConfigurations.yuri.activationPackage
```

期待: ビルドが成功する。`common.nix` に残るパッケージのうち darwin 非対応のもの（`gcc` / `proton-pass-cli` / `mtr` / `dnsutils` などが候補）でエラーが出たら、そのパッケージ行を `common.nix` から `hosts/linux.nix` の `home.packages` へ移し、移した理由をコメントに 1 行残してから再実行する。エラーが出なくなるまで繰り返す。

- [ ] **Step 6: 既存 3 ホストの評価が壊れていないことを確認する**

別 system のバイナリが必要なため yuri 上ではビルドできない。評価だけを通す。

```bash
for h in wsl pi yomogi; do
  echo "== $h =="
  nix eval --raw ~/.config/home-manager#homeConfigurations.$h.activationPackage.drvPath
  echo
done
```

期待: 3 ホストとも `/nix/store/...-home-manager-generation.drv` が出力される。評価エラーが出た場合は `hosts/linux.nix` の切り出し漏れ（`config` / `paseo` の引数、`docker-compat` の定義位置）を疑う。

- [ ] **Step 7: 初回の home-manager switch を実行する**

```bash
nix run home-manager/master -- switch -b bak --flake ~/.config/home-manager#yuri
```

期待: `Activating ...` が並び、エラーなく完了する。既存の `~/.zshrc` と `~/.zshenv` は `-b bak` により `.bak` として退避される。

- [ ] **Step 8: 新しい zsh で動作を確認する**

```bash
zsh -l -i -c 'type hms; command -v starship zoxide mise fzf home-manager; echo $PATH | tr ":" "\n" | grep cargo'
```

期待: `hms` がエイリアスとして表示され、各コマンドが `~/.nix-profile/bin/` 配下で解決され、`~/.cargo/bin` が PATH に含まれる。

- [ ] **Step 9: 署名鍵を用意してからコミットする**

Task 1 の `chezmoi apply` で `~/.gitconfig` に `commit.gpgsign = true` が入る一方、署名鍵 `~/.ssh/id_ed25519` は Task 5 で作られる。鍵が無い状態でコミットすると `error: Load key ... No such file or directory` で失敗するため、**先に Task 5 を最後まで実施してから**このステップに戻る。Task 5 が依存する `git-setup-signing` は Step 7 の switch で PATH に入っているため、この順序で回る。

```bash
cd "$HOME/.dotfiles"
git add dot_config/home-manager
git commit -m "$(cat <<'MSG'
feat(home-manager): yuri（aarch64-darwin）をホストに追加する

Linux 固有の設定（systemd の paseo ユニット、Linux 限定パッケージ、podman
一式、coreutils）を hosts/linux.nix へ切り出し、common.nix を OS 非依存にする。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Wcz5d2BcQV9z3bU7byDqYc
MSG
)"
```

---

### Task 4: Claude Code の共通設定に figma プラグインを加える

`chezmoi apply` で `~/.claude/settings.json` が共通テンプレートに置き換わり、yuri で有効だった figma プラグインが落ちる。figma のリモート MCP は `run_onchange_register-figma-mcp.sh.tmpl` が非 Windows で登録する建て付けなので、プラグイン有効化も共通テンプレートに置く。`theme` と `skipAutoPermissionPrompt` は全ホストへ波及するためテンプレートの値に統一し、戻さない。

**Files:**
- Modify: `dot_claude/settings.json.tmpl:74-81`

**Interfaces:**
- Consumes: なし
- Produces: `~/.claude/settings.json` の `enabledPlugins` に `figma@claude-plugins-official`

- [ ] **Step 1: テンプレートを編集する**

`dot_claude/settings.json.tmpl` の `enabledPlugins` を次に置き換える。

変更前:

```json
  "enabledPlugins": {
    "rust-analyzer-lsp@claude-plugins-official": true,
    "superpowers@claude-plugins-official": true,
    "skill-creator@claude-plugins-official": true,
    "code-review@claude-plugins-official": true,
    "github@claude-plugins-official": true,
    "typescript-lsp@claude-plugins-official": true
  },
```

変更後:

```json
  "enabledPlugins": {
    "rust-analyzer-lsp@claude-plugins-official": true,
    "superpowers@claude-plugins-official": true,
    "skill-creator@claude-plugins-official": true,
    "code-review@claude-plugins-official": true,
    "github@claude-plugins-official": true,
    "typescript-lsp@claude-plugins-official": true,
    "figma@claude-plugins-official": true
  },
```

- [ ] **Step 2: 展開結果を確認する**

```bash
cd "$HOME/.dotfiles"
chezmoi execute-template < dot_claude/settings.json.tmpl | python3 -m json.tool | grep -A 8 enabledPlugins
```

期待: JSON として妥当で、`"figma@claude-plugins-official": true` を含む。

- [ ] **Step 3: 適用する**

```bash
chezmoi diff && chezmoi apply
python3 -m json.tool < "$HOME/.claude/settings.json" >/dev/null && echo "valid json"
```

期待: `valid json` が出る。

- [ ] **Step 4: コミットする**

```bash
git add dot_claude/settings.json.tmpl
git commit -m "$(cat <<'MSG'
feat(claude): figma プラグインを共通設定で有効にする

figma のリモート MCP は run_onchange で非 Windows に登録しているため、
プラグインの有効化も共通テンプレート側に置く。

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Wcz5d2BcQV9z3bU7byDqYc
MSG
)"
```

---

### Task 5: yuri のコミット署名鍵を用意する

**実施順序:** Task 3 の Step 8 が終わった直後に実施する。Task 1 の `chezmoi apply` で `commit.gpgsign = true` が有効になっており、署名鍵が無いと Task 3 以降のコミットがすべて失敗するため。

**Files:**
- Modify: `dot_config/git/allowed_signers`

**Interfaces:**
- Consumes: Task 3 で PATH に入った `git-setup-signing`
- Produces: `~/.ssh/id_ed25519` と `allowed_signers` の yuri 行

- [ ] **Step 1: 署名鍵を生成して GitHub に登録する**

```bash
git-setup-signing
```

期待: `~/.ssh/id_ed25519` が生成され、GitHub に signing key として登録され、`allowed_signers` に追加すべき 1 行が出力される。`gh` のトークンに `admin:ssh_signing_key` スコープが無いと登録に失敗するので、その場合は `gh auth refresh -s admin:ssh_signing_key` のうえ再実行する。

- [ ] **Step 2: 出力された行を `allowed_signers` に追加する**

`dot_config/git/allowed_signers` の末尾に、ホスト名のコメントと出力された行を足す。`<出力された行>` は Step 1 の出力をそのまま貼る。

```
# yuri (MacBook Air)
<出力された行>
```

- [ ] **Step 3: 適用して検証まで通す**

```bash
cd "$HOME/.dotfiles" && chezmoi diff && chezmoi apply
git-setup-signing
```

期待: 2 回目の `git-setup-signing` が、使い捨てリポジトリでの署名と検証まで通って正常終了する。

- [ ] **Step 4: コミットする**

このコミット自体が新しい署名鍵で署名される。

```bash
git add dot_config/git/allowed_signers
git commit -m "$(cat <<'MSG'
feat: yuri の署名用公開鍵を allowed_signers に追加する

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Wcz5d2BcQV9z3bU7byDqYc
MSG
)"
git log --show-signature -1 | head -5
```

期待: `Good "git" signature for depkey@me.com` が表示される。

---

### Task 6: Homebrew と claude-code の重複を解消する

nix 側に同じものが入ったので、Homebrew の重複を外して実体を 1 つにする。

**Files:**
- 変更なし（yuri のローカル環境のみ）

**Interfaces:**
- Consumes: Task 3 で反映済みの home-manager 環境
- Produces: 重複の無い PATH

- [ ] **Step 1: 重複しているものが nix 側で解決されることを確認する**

```bash
zsh -l -i -c 'command -v aws gh just mise nu starship zoxide'
```

期待: すべて `~/.nix-profile/bin/` または `/opt/homebrew/bin/` のいずれかが出る。この時点では PATH 順により Homebrew 側が勝っている場合がある。

- [ ] **Step 2: Homebrew の重複を削除する**

`uv`、cask の `flameshot`、および `giflib` / `jpeg` / `librsvg` / `pkgconf` は nix 側に無い、あるいは他の用途で入れているため残す。

```bash
brew uninstall awscli gh just mise nushell starship zoxide
brew leaves
```

期待: 削除が完了し、`brew leaves` に `giflib` `jpeg` `librsvg` `pkgconf` `uv` だけが残る。依存関係で削除を拒否された場合はそのパッケージを残し、何が依存しているかを記録する。

- [ ] **Step 3: nix 側で解決されることを確認する**

```bash
zsh -l -i -c 'command -v aws gh just mise nu starship zoxide; node --version'
```

期待: すべて `~/.nix-profile/bin/` 配下で解決される。`node` は mise 管理（`~/.local/share/mise/installs/node/...`）のままバージョンが出る。mise のデータディレクトリはインストール方法に依存しないため、Homebrew 版を消しても導入済みの node はそのまま使える。

- [ ] **Step 4: ネイティブ版 claude-code を削除する**

nix 版に統一する。実行中の Claude Code セッションはネイティブ版のバイナリで動いているため、削除後は新しいセッションから nix 版に切り替わる。

```bash
rm "$HOME/.local/bin/claude"
rm -rf "$HOME/.local/share/claude"
zsh -l -i -c 'command -v claude; claude --version'
```

期待: `~/.nix-profile/bin/claude` が出て、バージョンが表示される。

---

### Task 7: README を更新する

**Files:**
- Modify: `README.md:54-73`（nix / home-manager 節）

**Interfaces:**
- Consumes: Task 3 で確定したホスト構成
- Produces: yuri を含む手順書

- [ ] **Step 1: ホスト構成の説明を更新する**

`README.md` の nix / home-manager 節にある次の段落を書き換える。

変更前:

```
構成は `common.nix`（全ホスト共通）と `hosts/<host>.nix`（ホスト固有）に分かれる。`flake.nix` の `hosts` がホストごとに読み込むモジュールを定義する。`yomogi`（自宅 Pi の個体名）は `hosts/pi.nix` を継承したうえで door-lock 中継の設定を足す構成のため、pi 系で共通化したい設定は `hosts/pi.nix` に書けば yomogi にも反映される。
```

変更後:

```
構成は `common.nix`（OS を問わない全ホスト共通）と `hosts/<host>.nix`（ホスト固有）に分かれる。`flake.nix` の `hosts` がホストごとに読み込むモジュールを定義する。

- `hosts/linux.nix`: Linux 3 ホスト（`wsl` / `pi` / `yomogi`）が共通で読む。systemd ユニット、Linux 限定パッケージ、podman 一式、GNU coreutils はここに置く。これらは darwin で評価が通らないため `common.nix` には置かない。
- `hosts/pi.nix`: Raspberry Pi 共通。`yomogi` が継承するため、pi 系で共通化したい設定はここに書けば yomogi にも反映される。
- `hosts/yomogi.nix`: 自宅 Pi の個体名。door-lock 中継の設定を足す。
- `hosts/yuri.nix`: MacBook Air（Apple Silicon）。macOS の既定シェルに合わせて `programs.zsh` を有効にする。`linux.nix` は読まない。
```

- [ ] **Step 2: ホスト鍵の例を更新する**

変更前:

```
3. 2 回目以降は home-manager が PATH に入るため、次で反映する（`<host>` は対象マシンの鍵。現状は `wsl`）。
```

変更後:

```
3. 2 回目以降は home-manager が PATH に入るため、次で反映する（`<host>` は対象マシンの鍵。現状は `wsl` / `pi` / `yomogi` / `yuri`）。
```

- [ ] **Step 3: macOS 向けの補足を「共通の補足」に追加する**

`## 共通の補足` の箇条書き末尾に次の 2 項目を追加する。

```
- macOS では Homebrew と併用する。CLI は home-manager（nix）に寄せ、Homebrew は GUI アプリ（cask）と nixpkgs に無いものだけに使う。両方に同じコマンドを入れると PATH 順で実体が変わり分かりにくくなる。
- `sourceDir` は全ホストで `~/.dotfiles`。別の場所にリポジトリを置きたい場合は `~/.dotfiles` をそこへのシンボリックリンクにする。
```

- [ ] **Step 4: 書式を確認する**

```bash
cd "$HOME/.dotfiles"
grep -n 'linux.nix\|yuri\|シンボリックリンク' README.md
```

期待: 追記した箇所がすべて出力される。

- [ ] **Step 5: コミットする**

```bash
git add README.md
git commit -m "$(cat <<'MSG'
docs: yuri と hosts/linux.nix を README に反映する

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Wcz5d2BcQV9z3bU7byDqYc
MSG
)"
```

---

### Task 8: PR を作る

**Files:**
- 変更なし

**Interfaces:**
- Consumes: Task 3〜7 のコミット
- Produces: `feat/yuri-darwin-host` の PR

- [ ] **Step 1: 差分を確認する**

```bash
cd "$HOME/.dotfiles"
git log --oneline master..HEAD
git diff master...HEAD --stat
```

期待: 設計・実装・ドキュメントのコミットが並び、変更ファイルが File Structure の表と一致する。

- [ ] **Step 2: push して PR を作る**

```bash
git push -u origin feat/yuri-darwin-host
gh pr create --base master --title "feat: yuri（macOS ホスト）を追加する" --body "$(cat <<'BODY'
## 概要

MacBook Air（Apple Silicon、`LocalHostName` = `yuri`）を chezmoi + home-manager の管理下に置く。

`common.nix` に混在していた Linux 固有の設定を `hosts/linux.nix` へ切り出し、`common.nix` を OS 非依存にした。

## 変更点

- `hosts/linux.nix` を新設し、systemd の paseo ユニット、Linux 限定パッケージ（strace / pciutils / usbutils）、podman 一式と docker 互換ラッパー、GNU coreutils を移した
- `hosts/yuri.nix` を新設し、`programs.zsh` の有効化、nushell、`~/.cargo/bin` の PATH を定義した
- `common.nix` の `hms` エイリアスを `programs.bash.shellAliases` から `home.shellAliases` へ移し、bash と zsh の両方に効くようにした
- `flake.nix` に `yuri`（aarch64-darwin）を追加し、Linux 3 ホストの modules に `linux.nix` を加えた
- figma プラグインを Claude Code の共通設定で有効にした
- yuri の署名用公開鍵を `allowed_signers` に追加した

## 検証

- yuri で `nix build ~/.config/home-manager#homeConfigurations.yuri.activationPackage` が通る
- `wsl` / `pi` / `yomogi` の `activationPackage.drvPath` が評価できる
- yuri で `home-manager switch` 後、zsh から `hms` とツール統合が効く
- `git-setup-signing` が署名と検証まで通る

## 設計

`docs/superpowers/specs/2026-09-06-yuri-darwin-host-design.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Wcz5d2BcQV9z3bU7byDqYc
BODY
)"
```

期待: PR の URL が出力される。

- [ ] **Step 3: 他ホストでの反映を案内する**

`hosts/linux.nix` の切り出しは wsl / pi / yomogi にも影響するため、マージ後に各ホストで次を実行する必要がある旨をユーザーへ伝える。

```sh
chezmoi update
hms
```
