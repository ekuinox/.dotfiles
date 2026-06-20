# chezmoi で winget パッケージを一覧管理する

- 日付: 2026-06-20
- ステータス: 設計合意済み（実装前）

## 背景・目的

新マシン展開時に「普段使う Windows アプリ」を winget で一括導入したい。chezmoi
は本来ファイル管理ツールでパッケージ一覧の専用機能を持たないが、`.chezmoidata`
（テンプレート用データ）と `run_onchange_` スクリプト（apply 時に内容が変わったら
実行されるフック）を組み合わせれば、宣言的な一覧管理を実現できる。

このリポジトリは既に OS 分岐（`.chezmoiignore` と `*.tmpl`）で Windows 固有設定を
切り分けており、同じ仕組みに乗せて winget 管理を Windows 限定で追加する。

## スコープ（合意事項）

- **管理レベル: 一覧管理（宣言的・既存はスキップ）**
  - 一覧に列挙したアプリを新マシンで一括導入する。
  - 既にインストール済みのものはスキップする。
  - **アンインストールは扱わない**（一覧から消しても既存マシンから消えない）。完全
    同期はスコープ外。
- **一覧の持ち方: 手キュレーション**
  - winget のパッケージ ID を自分で選んで `.chezmoidata` に列挙する。
  - バージョンは原則 latest。バージョン固定はしない（YAGNI）。
  - `winget export` による全インストール品スナップショットは採用しない（ノイズが多い
    ため）。
- **実行タイミング: `run_onchange`（自動・変更検知）**
  - `chezmoi apply` 時、一覧が前回から変われば自動でインストールが走る。
  - 新マシンはブートストラップ一発で全部入り、後から足したアプリも次の apply で導入。

## 全体構成

```
.dotfiles/
├── .chezmoidata/
│   └── packages.toml          # winget ID のキュレーション一覧（手で足し引き）
└── run_onchange_install-winget-packages.ps1.tmpl   # 導入スクリプト（テンプレート）
```

- **`.chezmoidata/packages.toml`**: chezmoi が起動時に自動読み込みし、全テンプレートから
  参照できるデータファイル。ここに winget ID を並べる。秘密情報を含まないためリポジトリ
  方針と整合する。
- **`run_onchange_install-winget-packages.ps1.tmpl`**: chezmoi がレンダリングし、前回
  apply 時とハッシュが変われば実行する。パッケージ ID をスクリプト本文に直接埋め込む
  ため、ID を1個足すだけでハッシュが変わり次の apply で再実行される（＝自動・変更検知）。

## データファイル

`.chezmoidata/packages.toml`:

```toml
[winget]
ids = [
  "Git.Git",
  "GitHub.cli",
  "Microsoft.VisualStudioCode",
  "7zip.7zip",
  # ここに足し引きするだけ
]
```

> git / gh は clone 前に必要なためブートストラップで手動導入済みだが、一覧に含めても
> `winget list` でスキップされるだけ。「このマシンに何を入れる方針か」のドキュメントと
> して含めるのは任意で可。

## 導入スクリプト

`run_onchange_install-winget-packages.ps1.tmpl`（要点）:

```powershell
{{- if eq .chezmoi.os "windows" -}}
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Warning "winget not found; skipping package install"
  exit 0
}

$ids = @(
{{- range .winget.ids }}
  "{{ . }}",
{{- end }}
)

$failed = @()
foreach ($id in $ids) {
  winget list --id $id -e *> $null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "skip (installed): $id"
    continue
  }
  Write-Host "installing: $id"
  winget install --id $id -e --silent `
    --accept-source-agreements --accept-package-agreements
  if ($LASTEXITCODE -ne 0) { $failed += $id }
}

if ($failed.Count -gt 0) {
  Write-Warning ("failed: " + ($failed -join ", "))
}
exit 0
{{- end -}}
```

### 設計上のポイント

- **OS ガード**: 先頭の `{{ if eq .chezmoi.os "windows" }}` により、Linux/macOS では
  レンダリング結果が空となり chezmoi はスクリプトを実行しない。`.chezmoiignore` を触ら
  ずに Windows 限定にできる。
- **スキップ判定**: 各 ID をまず `winget list` で確認し、入っていれば install をスキップ。
  再実行が静かで速く、「既存はスキップ」を満たす。
- **非対話化**: `--silent --accept-source-agreements --accept-package-agreements` で apply
  中の対話プロンプトを最小化。

## エラー処理・堅牢性

- **winget 不在**: 冒頭で `Get-Command winget` を確認し、無ければ warning を出して
  `exit 0`（apply 全体は失敗させない）。
- **個別インストール失敗**: `foreach` は1個の失敗で止めず続行。失敗 ID は最後にまとめて
  warning 表示。
- **終了コード**: スクリプトは基本 `exit 0`。apply を赤くせず、失敗は表示で気づける形。

## エッジケース

- **空リスト**: `ids` が空でも安全に no-op。
- **再実行の重さ**: `run_onchange` は一覧変更時のみ発火。発火時は全 ID をなめるが、
  `winget list` スキップで既存は即時 no-op。
- **バージョン固定**: 現状はしない。必要になれば将来 `[winget.pinned]` 等で拡張可能。

## 検証方法

- `chezmoi execute-template < run_onchange_install-winget-packages.ps1.tmpl` でレンダリング
  結果を目視（ID が正しく展開され、非 Windows では空になる）。
- `chezmoi apply --dry-run --verbose` で実行予定を確認。
- 実機で ID を1個足して `chezmoi apply` → 自動導入されること、既存がスキップされること
  を確認。

## 非スコープ（やらないこと）

- 一覧からの削除に連動したアンインストール（完全同期）。
- `winget export` による全インストール品スナップショット管理。
- バージョン固定 / ピン留め。
- winget 以外のパッケージマネージャ（apt/brew 等）の統合。既存どおり README の手順で対応。
