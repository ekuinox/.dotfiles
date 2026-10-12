# aoi-gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** aoi の HTTP サーバーを `<サービス名>-aoi.ekuinox.dev` で Cloudflare Access の後ろに公開する入口（Caddy + cloudflared）を home-manager モジュールとして用意し、kgd 側の文書を合わせて更新する。

**Architecture:** `modules/aoi-gateway.nix` が Caddyfile と cloudflared の設定を生成し、2 つの systemd ユーザーサービスと確認スクリプトを定義する。`hosts/aoi.nix` が aoi の値を与える。kgd はコードを変えず、ADR と README だけを更新する。

**Tech Stack:** nix / home-manager、Caddy、cloudflared、bash（writeShellApplication）

**Spec:** `docs/superpowers/specs/2026-10-12-aoi-gateway-design.md`

## Global Constraints

- 公開ホスト名は `<サービス名>${hostSuffix}.${domain}`（aoi では `-aoi` と `ekuinox.dev`）。`routes` のキーはサービス名で、モジュールがホスト名を組み立てる
- Caddy は Host の完全一致で振り分け、一致しなければ 404。`header_up -Cf-*` と `header_up -Cdn-Loop` で Cf-* ヘッダを削る
- Caddy は `http://:<port>` で受け、`default_bind 127.0.0.1` で待ち受けを絞る（door-lock で踏んだ空の 200 の罠を避ける）
- cloudflared の ingress は catch-all の 1 ルールのみで、`originRequest.access`（required、teamName、audTag）を付ける
- 秘密物（`cert.pem`、`<UUID>.json`）はリポジトリにも /nix/store にも置かない。開きもしない
- kgd のコードは変えない
- コミットメッセージは日本語。PR 本文は装飾を控える

## Review Focus

- サービス名に `.` や大文字が入る：ホスト名が規約から外れるため、評価時の assertion で止まること
- `routes` が空：Caddy は全リクエストに 404 を返し、評価は通ること
- 2 階層目の Host（`x.kgd-aoi.ekuinox.dev`）：Caddy が 404 を返すこと（Task 1 の機能テストで確かめる）
- Cf-* ヘッダ付きのリクエスト：転送先に Cf-* が届かないこと（同上）
- 確認スクリプトで curl が接続に失敗する：`000` を FAIL として扱い、`set -e` で途中終了しないこと

---

### Task 1: aoi-gateway モジュールと aoi のホスト設定

**Files:**
- Create: `dot_config/home-manager/modules/aoi-gateway.nix`
- Create: `dot_config/home-manager/hosts/aoi.nix`
- Modify: `dot_config/home-manager/flake.nix`（aoi の modules に `./hosts/aoi.nix`）

**Interfaces:**
- Produces: `services.aoi-gateway.{enable, domain, hostSuffix, routes, tunnelId, teamName, audTags, proxyPort, protocol, credentialsFile}`、ユーザーサービス `aoi-gateway-proxy` と `cloudflared-aoi-gateway`、コマンド `aoi-gateway-check`

- [ ] **Step 1: モジュールとホスト設定を書く**（コードは本 PR の該当ファイルを参照）
- [ ] **Step 2: 新規ファイルを git に載せる**（flake は git 管理下のファイルしか見ないため `git add -N`）
- [ ] **Step 3: aoi の設定が評価できることを確かめる**

Run: `nix eval --raw './dot_config/home-manager#homeConfigurations.aoi.activationPackage.drvPath'`
Expected: `/nix/store/...-home-manager-generation.drv`

- [ ] **Step 4: 有効にした変種で生成物をビルドする**

`/tmp/aoi-gateway-test/t.nix` で `home-manager.lib.homeManagerConfiguration` に `hosts/aoi.nix` と、`enable = true`、ダミーの `tunnelId` / `teamName` / `audTags`、`proxyPort = 18080`、`routes.kgd = "http://127.0.0.1:18081"` を与える上書きを渡し、2 つのユーザーサービスの `ExecStart` と `aoi-gateway-check` をビルドする。

Expected: ビルドが通る（`aoi-gateway-check` は shellcheck を通る）

- [ ] **Step 5: 不正なサービス名で評価が止まることを確かめる**

上書きで `routes."Bad.Name" = "http://127.0.0.1:1";` を与えて評価する。
Expected: assertion のメッセージで失敗する

- [ ] **Step 6: 生成した Caddyfile の機能テスト**

127.0.0.1:18081 にリクエストヘッダを返すエコーサーバーを立て、生成した Caddyfile で Caddy を起動し、次を確かめる。

| リクエスト | Expected |
| --- | --- |
| `Host: kgd-aoi.ekuinox.dev`、`Cf-Connecting-IP` と `Cf-Ray` と `Cdn-Loop` 付き | 200、エコーに Cf-* と Cdn-Loop が無く、Host は `kgd-aoi.ekuinox.dev` |
| `Host: KGD-AOI.ekuinox.dev` | 200 |
| `Host: x.kgd-aoi.ekuinox.dev` | 404 |
| `Host: zzz-aoi.ekuinox.dev` | 404 |
| `Host: 127.0.0.1` | 404 |

Caddy が 127.0.0.1 だけで待ち受けていることも `ss -ltn` で確かめる。

- [ ] **Step 7: 生成した cloudflared の設定を確かめる**

Run: `cloudflared tunnel --config <生成した設定> ingress validate` と `... ingress rule https://kgd-aoi.ekuinox.dev`
Expected: OK、catch-all（rule 0）に一致する。YAML に `access.required: true` と teamName、audTag が入っている

- [ ] **Step 8: Commit**

### Task 2: dotfiles の文書

**Files:**
- Modify: `README.md`（ホスト表の aoi の行、`hosts/aoi.nix` の説明、aoi-gateway の展開とサーバー追加の手順への参照）
- Modify: `docs/superpowers/specs/2026-10-12-aoi-gateway-design.md`（`routes` のキーをサービス名にした変更、`domain` / `hostSuffix` オプション、待ち受けポートの確認）

- [ ] **Step 1: README と spec を更新する**
- [ ] **Step 2: Commit**

### Task 3: kgd の文書

kgd のリポジトリで `origin/master` から新しいブランチ `docs/aoi-gateway` を切り、別の worktree で作業する。

**Files:**
- Create: `docs/adr/0015-publish-viewer-through-aoi-gateway.md`
- Modify: `docs/adr/0013-guard-viewer-sharing-the-owntracks-listener.md`（ステータスに 0015 で一部を置き換えたことを書く）
- Modify: `docs/adr/README.md`（一覧に 0015 を足す）
- Modify: `README.md`（「Cloudflare Access は使わない」の範囲、ビューアを外から開く方法、`route dns` を UUID で指定）

- [ ] **Step 1: ADR と README を書く**
- [ ] **Step 2: Commit**

### Task 4: PR

- [ ] **Step 1: dotfiles のブランチを push し、PR を作る**
- [ ] **Step 2: kgd のブランチを push し、PR を作る。dotfiles の PR を本文で参照する**
- [ ] **Step 3: dotfiles の PR 本文に kgd の PR を追記する**
