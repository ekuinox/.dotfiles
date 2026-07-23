# home-manager ホスト構成モジュール分割 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** home-manager のホスト構成をモジュール分割し、yomogi が pi を `imports` で継承する本物の継承構造へ置き換える。

**Architecture:** 全ホスト共通の設定を `common.nix`（旧 home.nix）に残し、ホスト固有差分を `hosts/{wsl,pi,yomogi}.nix` に切り出す。`flake.nix` の `hosts` をホスト名 → `{ system, modules }` のマップにし、yomogi の modules を `[ ./hosts/pi.nix ./hosts/yomogi.nix mube... ]` とすることで pi.nix への追記が自動で yomogi に効くようにする。host 文字列比較の条件分岐は各ホストモジュールの無条件設定へ移す。

**Tech Stack:** Nix flakes, home-manager, chezmoi（このリポジトリが source）。

## Global Constraints

- 対象ファイルは chezmoi の source。`dot_config/home-manager/` 配下を直接編集する = source 編集。ターゲット（`~/.config/home-manager/`）は直接触らない。
- 秘密情報はコミットしない。door-lock の tunnelId / hostname / picoOrigin は既存 home.nix から移設する既知の値であり秘密ではない（現行 home.nix にも平文で存在）。
- ドキュメント文体は日本語・簡潔・絵文字なし。コメントは既存の密度・トーンに合わせる。
- コミットメッセージは日本語。末尾に `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` を付ける。
- master へ直接 push しない（現ブランチ durable-moth で作業）。
- Nix flake は git 管理下のファイルしか評価対象にしないため、`nix build` / `nix eval` の前に新規・リネームファイルを `git add` してステージする。
- リポジトリルート: `/home/ekuinox/.paseo/worktrees/16an41p0/durable-moth`。以降のコマンドはこのルートから実行する。

---

## File Structure

```
dot_config/home-manager/
  flake.nix          # 変更: hosts を { system, modules } 形式へ、mkHome を書き換え
  common.nix         # 新規(旧 home.nix をリネーム): 全ホスト共通。host 条件を削除
  hosts/
    wsl.nix          # 新規: herdr パッケージ + herdr config.toml
    pi.nix           # 新規: pi 系(aarch64)共通。現状は空
    yomogi.nix       # 新規: services.mube-door-lock
  scripts/
    gog-setup-credentials.sh  # 変更: コメントの home.nix 参照を common.nix へ
  packages/          # 変更なし
```

---

### Task 1: モジュール分割と flake 書き換え

全ホストが同じ `home.nix` を共有する現状を、`common.nix` + `hosts/*.nix` の継承構造へ置き換える。Nix の評価は全ピースが揃うまで通らないため、本タスクは一括で行い、末尾でまとめて検証する。

**Files:**
- Rename: `dot_config/home-manager/home.nix` → `dot_config/home-manager/common.nix`
- Modify: `dot_config/home-manager/common.nix`（リネーム後、host 条件を削除）
- Create: `dot_config/home-manager/hosts/wsl.nix`
- Create: `dot_config/home-manager/hosts/pi.nix`
- Create: `dot_config/home-manager/hosts/yomogi.nix`
- Modify: `dot_config/home-manager/flake.nix`
- Modify: `dot_config/home-manager/scripts/gog-setup-credentials.sh:2`（コメント）

**Interfaces:**
- specialArgs（全ホストへ渡す）: `host`（string）, `paseo`（package）, `herdr`（package）。
- `common.nix` の関数シグネチャ: `{ config, pkgs, lib, host, paseo, ... }`（`herdr` を外す）。
- `hosts/wsl.nix` の関数シグネチャ: `{ pkgs, herdr, ... }`。
- `hosts/pi.nix` / `hosts/yomogi.nix` の関数シグネチャ: `{ ... }`。
- yomogi は `services.mube-door-lock` オプションを使う。このオプションの提供元 `mube.homeManagerModules.default` は flake.nix で yomogi の modules にのみ import する。

- [ ] **Step 1: home.nix を common.nix にリネーム**

```bash
cd /home/ekuinox/.paseo/worktrees/16an41p0/durable-moth
git mv dot_config/home-manager/home.nix dot_config/home-manager/common.nix
```

- [ ] **Step 2: common.nix から host 条件を削除する**

`dot_config/home-manager/common.nix` に対し 3 箇所を編集する。

(a) 関数シグネチャから `herdr` を外す（1 行目）:

```nix
{ config, pkgs, lib, host, paseo, ... }:
```

(b) `home.packages` 末尾の herdr 追加を削除する。現状:

```nix
      paseo
      # herdr（エージェント多重化 TUI）は wsl のみ。pi では参照しない。
    ] ++ lib.optional (host == "wsl") herdr;
```

を次に置き換える:

```nix
      paseo
    ];
```

(c) herdr の config.toml ブロック全体（`file.".config/herdr/config.toml" = { ... };`、コメント行 `# herdr（エージェント多重化 TUI）の設定。...` から `};` まで）を削除する。この設定は wsl.nix へ移す。

(d) `services.mube-door-lock` ブロック全体（先頭コメント `# mube スマートロックの中継スタック...` から `};` まで）を削除する。この設定は yomogi.nix へ移す。

`home.username` / `hms` エイリアス（`#${host}`）/ paseo systemd サービス（`paseo` specialArg 使用）は残す。

- [ ] **Step 3: hosts/ ディレクトリと wsl.nix を作成する**

`dot_config/home-manager/hosts/wsl.nix`:

```nix
# WSL (x86_64-linux) 固有のホスト設定。
# herdr（AI コーディングエージェント用ターミナルワークスペース管理）は wsl のみで使う。
# パッケージ・設定ともこのモジュールが wsl でしか読まれないため host 判定は不要。
{ pkgs, herdr, ... }:
{
  # herdr 本体（flake input が公開する package）を PATH に入れる。
  # common.nix の home.packages リストへマージされる。
  home.packages = [ herdr ];

  # herdr の設定。プレーンな TOML なので nix で直接生成する。
  home.file.".config/herdr/config.toml".text = ''
    onboarding = false

    [terminal]
    default_shell = "bash"
    shell_mode = "auto"
    new_cwd = "follow"

    [keys]
    prefix = "ctrl+b"
    next_tab = "prefix+n"
    previous_tab = "prefix+p"

    [theme]
    name = "catppuccin"

    [ui.toast]
    delivery = "herdr"
  '';
}
```

- [ ] **Step 4: hosts/pi.nix を作成する**

`dot_config/home-manager/hosts/pi.nix`:

```nix
# Raspberry Pi (aarch64) 共通のホスト設定。yomogi はこのモジュールを継承する。
# 現状 pi 固有の差分は無い。pi 系で共通化したい設定をここに追記すると、
# flake.nix で yomogi の modules に本ファイルを含めているため yomogi にも自動で反映される。
{ ... }:
{
}
```

- [ ] **Step 5: hosts/yomogi.nix を作成する**

`dot_config/home-manager/hosts/yomogi.nix`:

```nix
# 自宅 Pi の個体 yomogi 固有の設定。pi.nix を継承しつつ door-lock 中継役を担う。
# mube スマートロックの中継スタック（Caddy ヘッダ削ぎプロキシ + cloudflared tunnel）。
# モジュール実体は flake input の mube 側（flake.nix で yomogi の modules に import 済み）。
# このモジュールは yomogi でしか読まれないため enable は無条件 true。
# 秘密物（~/.cloudflared/cert.pem と <tunnel-id>.json）は手動配置。linger 必須。
{ ... }:
{
  services.mube-door-lock = {
    enable = true;
    hostname = "door-lock-private.ekuinox.dev";
    tunnelId = "b45a50d5-24f6-4732-9568-7971f9772504";
    picoOrigin = "http://172.20.10.13:80"; # Pico の IP が変わったらここを更新して hms
    protocol = "http2"; # この回線は QUIC(UDP 7844) が塞がれているため必須
  };
}
```

- [ ] **Step 6: flake.nix を書き換える**

`dot_config/home-manager/flake.nix` の `let ... in` ブロック（`hosts` 定義と `mkHome`）を次に置き換える。inputs 部の herdr / mube コメントも実態（モジュール分割後）に合わせて更新する。

```nix
  outputs = { nixpkgs, home-manager, paseo, herdr, mube, ... }:
    let
      # ホスト名 -> { system, modules }。共通設定は common.nix、ホスト固有差分は
      # hosts/*.nix に置く。yomogi は pi.nix を継承（modules に含める）しつつ
      # 個体固有の door-lock 設定（yomogi.nix）と mube モジュールを足す。
      hosts = {
        wsl = {
          system = "x86_64-linux";
          modules = [ ./hosts/wsl.nix ];
        };
        # Raspberry Pi (Ubuntu, aarch64) の汎用ホスト
        pi = {
          system = "aarch64-linux";
          modules = [ ./hosts/pi.nix ];
        };
        # yomogi: 自宅 Pi の個体名。pi.nix を継承し、door-lock 中継役の設定を追加する。
        # mube.homeManagerModules.default は services.mube-door-lock オプションの提供元で、
        # yomogi だけが必要とするためここでのみ import する（wsl/pi はオプションを持たない）。
        yomogi = {
          system = "aarch64-linux";
          modules = [ ./hosts/pi.nix ./hosts/yomogi.nix mube.homeManagerModules.default ];
        };
        # 将来: mac = { system = "aarch64-darwin"; modules = [ ./hosts/mac.nix ]; };
      };
      mkHome = host: { system, modules }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ ./common.nix ] ++ modules;
          # host は hms エイリアスの flake 参照先。paseo/herdr は system 別 package。
          # herdr を参照するのは wsl.nix のみ。pi/yomogi のモジュールは herdr を
          # 引数に取らないため、遅延評価で aarch64 版 herdr は forced されずビルドされない。
          extraSpecialArgs = {
            inherit host;
            paseo = paseo.packages.${system}.default;
            herdr = herdr.packages.${system}.default;
          };
        };
    in {
      homeConfigurations = nixpkgs.lib.mapAttrs mkHome hosts;
    };
```

inputs 内の herdr コメント末尾「wsl 限定のため home.nix 側で host == "wsl" のときだけ参照する（pi では遅延評価でビルドされない）。」を「wsl 限定のため hosts/wsl.nix でのみ参照する（pi/yomogi では遅延評価でビルドされない）。」に更新する。inputs 内の mube コメント末尾「yomogi ホストのみ有効化（home.nix 参照）。」を「yomogi の modules でのみ import・有効化（hosts/yomogi.nix 参照）。」に更新する。

- [ ] **Step 7: gog-setup-credentials.sh のコメントを更新する**

`dot_config/home-manager/scripts/gog-setup-credentials.sh:2` の

```sh
# home.nix の pkgs.writeShellApplication が text として読み込む（builtins.readFile）。
```

を次に更新する:

```sh
# common.nix の pkgs.writeShellApplication が text として読み込む（builtins.readFile）。
```

- [ ] **Step 8: 変更をステージして flake が評価対象に含める**

Nix flake は git 追跡ファイルしか見ないため、新規・リネーム後のファイルをステージする。

```bash
cd /home/ekuinox/.paseo/worktrees/16an41p0/durable-moth
git add dot_config/home-manager/
git status --short dot_config/home-manager/
```

Expected: `common.nix`（R= リネーム）, `flake.nix`（M）, `hosts/wsl.nix` `hosts/pi.nix` `hosts/yomogi.nix`（A）, `scripts/gog-setup-credentials.sh`（M）が並ぶ。

- [ ] **Step 9: 3 ホストの評価が通ることを確認する**

`.activationPackage.drvPath` を eval すると、ビルドせずに構成全体の評価（instantiate）だけを行える。wsl(x86_64) を aarch64 上でネイティブ build はできないが、評価は通る。

```bash
cd /home/ekuinox/.paseo/worktrees/16an41p0/durable-moth/dot_config/home-manager
for h in wsl pi yomogi; do
  echo "=== $h ==="
  nix eval --raw ".#homeConfigurations.$h.activationPackage.drvPath" && echo
done
```

Expected: 3 ホストとも `/nix/store/....drv` の drvPath が出力され、評価エラーが無い。

- [ ] **Step 10: pi と yomogi をネイティブ build する**

```bash
cd /home/ekuinox/.paseo/worktrees/16an41p0/durable-moth/dot_config/home-manager
nix build --no-link ".#homeConfigurations.pi.activationPackage"
nix build --no-link ".#homeConfigurations.yomogi.activationPackage"
echo "build ok"
```

Expected: 両方ビルド成功し `build ok` が出る。

- [ ] **Step 11: door-lock の user unit が yomogi にのみ含まれることを確認する**

pi と yomogi の systemd user サービス名一覧を比較する。door-lock 由来のユニットは yomogi 側にのみ現れる。

```bash
cd /home/ekuinox/.paseo/worktrees/16an41p0/durable-moth/dot_config/home-manager
echo "=== pi ==="
nix eval --json ".#homeConfigurations.pi.config.systemd.user.services" --apply 'builtins.attrNames'
echo "=== yomogi ==="
nix eval --json ".#homeConfigurations.yomogi.config.systemd.user.services" --apply 'builtins.attrNames'
```

Expected: pi は paseo のみ（door-lock 関連なし）。yomogi は pi の一覧に加えて mube door-lock 中継の user unit が 2 本増える（mube モジュールが定義する caddy 相当 + cloudflared の 2 サービス）。yomogi の一覧から pi の一覧を引いた差分がちょうど 2 本であることを確認する。

補足: 増分がちょうど 2 本かを機械的に確かめるには次を実行する。

```bash
diff <(nix eval --json ".#homeConfigurations.pi.config.systemd.user.services" --apply 'builtins.attrNames' | tr ',' '\n') \
     <(nix eval --json ".#homeConfigurations.yomogi.config.systemd.user.services" --apply 'builtins.attrNames' | tr ',' '\n')
```

Expected: yomogi 側にのみ 2 エントリ（door-lock の caddy 相当 + cloudflared）が `>` として現れる。

- [ ] **Step 12: コミット**

```bash
cd /home/ekuinox/.paseo/worktrees/16an41p0/durable-moth
git add dot_config/home-manager/
git commit -m "refactor: home-manager のホスト構成をモジュール分割し yomogi が pi を継承 (#29)

home.nix を common.nix にリネームし、hosts/{wsl,pi,yomogi}.nix へ
ホスト固有差分を分離。flake.nix の hosts を { system, modules } 形式にし、
yomogi の modules に pi.nix を含めることで本物の継承にする。
host 文字列比較（herdr の wsl 限定、door-lock の yomogi 限定）は
各ホストモジュールの無条件設定へ移した。

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: README にホストモジュール構成を追記

home-manager の構成説明に、ホストごとのモジュール分割と継承関係を一言添える。過剰な記述はしない。

**Files:**
- Modify: `README.md`（nix / home-manager セクション、53 行目付近）

**Interfaces:**
- 参照する事実: ホストは `wsl` / `pi` / `yomogi`。共通は `common.nix`、ホスト固有は `hosts/*.nix`。yomogi は `hosts/pi.nix` を継承する。

- [ ] **Step 1: README の該当セクションを確認する**

```bash
cd /home/ekuinox/.paseo/worktrees/16an41p0/durable-moth
sed -n '53,72p' README.md
```

Expected: 「### nix / home-manager（Linux / macOS のみ）」の手順が表示される。

- [ ] **Step 2: 構成の一文を追記する**

「### nix / home-manager（Linux / macOS のみ）」セクションの手順本文の直後（`nix run home-manager/master ...` の手順群の後、`.bashrc` の段落の前後で自然な位置）に、次の段落を追加する。既存の文体に合わせ簡潔にする。

```markdown
構成は `common.nix`（全ホスト共通）と `hosts/<host>.nix`（ホスト固有）に分かれる。`flake.nix` の `hosts` がホストごとに読み込むモジュールを定義する。`yomogi`（自宅 Pi の個体名）は `hosts/pi.nix` を継承したうえで door-lock 中継の設定を足す構成のため、pi 系で共通化したい設定は `hosts/pi.nix` に書けば yomogi にも反映される。
```

配置位置の判断がつかない場合は、`<host>` の説明がある手順 3（64〜67 行目付近）の直後に置く。

- [ ] **Step 3: 差分を確認する**

```bash
cd /home/ekuinox/.paseo/worktrees/16an41p0/durable-moth
git diff README.md
```

Expected: 上記段落が 1 箇所追加されているだけ。

- [ ] **Step 4: コミット**

```bash
cd /home/ekuinox/.paseo/worktrees/16an41p0/durable-moth
git add README.md
git commit -m "docs: home-manager のホストモジュール構成を README に追記 (#29)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- 共通設定を common.nix に残す → Task 1 Step 1-2。
- hosts/{wsl,pi,yomogi}.nix 作成、flake の hosts を { system, modules } に → Task 1 Step 3-6。
- yomogi の modules = [ ./hosts/pi.nix ./hosts/yomogi.nix (+mube) ] → Task 1 Step 6。
- herdr の wsl 限定を hosts/wsl.nix へ → Task 1 Step 3。
- door-lock を hosts/yomogi.nix へ → Task 1 Step 5。
- hms の host specialArg を維持 → Task 1 Step 6（extraSpecialArgs に host）。
- コメント参照の更新（home.nix → common.nix）→ Task 1 Step 6-7。
- 3 ターゲットの検証・door-lock 2 本の確認 → Task 1 Step 9-11。
- README 追記 → Task 2。

**Placeholder scan:** 実コード・実コマンドを各ステップに記載済み。door-lock ユニットの厳密名は mube 側依存のため、名前直書きではなく pi/yomogi の差分比較で 2 本増を確認する方式にしている（プレースホルダではなく検証手法の選択）。

**Type consistency:** specialArgs（host/paseo/herdr）、関数シグネチャ（common=`{...,host,paseo,...}`、wsl=`{pkgs,herdr,...}`、pi/yomogi=`{...}`）、`services.mube-door-lock` の属性名は spec と一致。flake の `hosts` エントリ形状 `{ system, modules }` と `mkHome host: { system, modules }:` の分解が一致。
