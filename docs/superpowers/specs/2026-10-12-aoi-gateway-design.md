# aoi の HTTP サーバーを Cloudflare Access の後ろにまとめて公開する設計

## 背景と目的

aoi（Raspberry Pi, aarch64-linux）では kgd が動いており、位置ログのビューアを `http://aoi.local:8081/viewer/` で配信している。
ビューアにはログインが無く、kgd 自身のガード（kgd の ADR-0013）によって LAN の中からしか開けない。

このビューアを外出先のブラウザからも開きたい。
今後 aoi に載せる HTTP サーバーも、同じ入口から Cloudflare Access のログインを経て開けるようにしたい。

要件は次のとおり。

- 外部のブラウザから、Cloudflare Access のログインを経て開ける
- サーバーを載せるときに、アプリのコードを変えない
- サーバーを載せるときに、Cloudflare 側の設定作業を要さない
- 無料プランの範囲に収める
- `ekuinox.dev` の他の用途のサブドメイン（`www`、`kokage`、`b` など）に影響を与えない。今後も別の用途にサブドメインを割り当てうる

## 調査で確認した事実

### 公開ホスト名は 1 階層目に限られる

`ekuinox.dev` は Cloudflare のフルセットアップ（ネームサーバーが `liz` / `kip`.ns.cloudflare.com）であり、Universal SSL の証明書は apex と `*.ekuinox.dev` だけを覆う。
crt.sh でも、`*.ekuinox.dev ekuinox.dev` の証明書が 2026-09 に更新されていることを確認した。
`.dev` は HSTS preload 済みで HTTPS 以外を受け付けないため、証明書の無い名前は開けない。

2 階層目（`kgd.aoi.ekuinox.dev` など）を通す手段は、いずれも無料の範囲に無い。

- Total TLS は Advanced Certificate Manager（有料）が前提で、しかも Tunnel で使うホスト名には証明書を発行しないと明記されている
- `aoi.ekuinox.dev` を別ゾーンに切り出すサブドメインセットアップは Enterprise 限定である

### Access アプリは部分ワイルドカードを受け付ける

公式ドキュメント（Application paths）は、Subdomain の先頭または末尾のワイルドカードを認めている。
例として、`*test.example.com` が `test.example.com` と `alphatest.example.com` を覆い、`beta.test.example.com` を覆わないことが示されている。
制限は、ドットとドットの間にワイルドカードが 1 つまでであることだけである。

2026-10-12 にダッシュボードで実際に確かめた。

1. Self-hosted のアプリを `*-aoi.ekuinox.dev` で作成できた（ポリシーは自分のメールアドレスのみ Allow）
2. テスト用に `test-aoi.ekuinox.dev` の CNAME を既存のトンネルへ向けると、未ログインでは Access のログイン画面へ飛ばされ、ログイン後はトンネル側の 404 が返った
3. `www.ekuinox.dev` などの既存のサブドメインは、これまでどおりログイン無しで開けた

テスト用のレコードは削除済みで、Access アプリは本番で使うため残してある。

### ワイルドカード DNS は既存のレコードを上書きしない

公式ドキュメント（Wildcard DNS records）によれば、プロキシ付きのワイルドカードレコードはすべてのプランで作れる。
ワイルドカードは、その名前に明示したレコードが無いときにだけ使われる。
明示したレコードの下の名前（`x.kokage.ekuinox.dev` など）にもワイルドカードは効かない。
一方、明示したレコードの無い名前については、下の階層（`x.y.ekuinox.dev`）にも効く。

### cloudflared は全ホスト名を 1 つのサービスへ流せ、Access の JWT を検証できる

ローカル管理のトンネルの ingress では、ホスト名を書かないルールがすべてのホスト名に一致する。
最後のルールはこの形の catch-all である必要があり、ルールがこれ 1 つだけでもよい。

ingress の `originRequest.access`（ダッシュボードでの名前は Protect with Access）を有効にすると、cloudflared はオリジンへ転送する前に `Cf-Access-Jwt-Assertion` ヘッダの JWT を検証する。
cloudflared のソース（`ingress/middleware/jwtvalidator.go`、`proxy/proxy.go`）で次の挙動を確認した。

- ヘッダが無ければ 403 を返す
- 署名、発行元、有効期限は `https://<チーム名>.cloudflareaccess.com/cdn-cgi/access/certs` の鍵で検証する。失敗すればエラーとして扱い、オリジンへ転送しない
- トークンの `aud` が設定した AUD タグのいずれとも一致しなければ 403 を返す

いずれの失敗でもオリジンへは転送されない。

### `cloudflared tunnel route dns` は別のトンネルを指すことがある

2026-10-12 の確認作業で、yomogi で `cloudflared tunnel route dns kgd-owntracks test-aoi.ekuinox.dev` を実行したところ、CNAME が door-lock のトンネル（`b45a50d5-...`）に向いた。

cloudflared のソース（`subcommand_context.go` の `findID`）を読むと、トンネルの指定が UUID の形でないとき、cloudflared は先に `credentials-file` で指定された認証情報ファイルを読み、その中のトンネル ID を返す。
`credentials-file` は `config.yml` か環境変数 `TUNNEL_CRED_FILE` から来る。
このとき、認証情報が引数の名前のトンネルのものかどうかを確かめていない。
yomogi の cloudflared の設定が door-lock の認証情報を指しているため、どの名前を渡しても door-lock の ID になったと考えられる（yomogi のどの設定から来たかは確かめていない）。

トンネルを UUID で指定すれば、cloudflared は UUID をそのまま使うため、この問題は起きない。

### door-lock の中継で得た知見

yomogi の door-lock の中継（mube の `nix/door-lock-relay.nix`）は、Caddy と cloudflared を home-manager の systemd ユーザーサービスとして動かしており、本設計とほぼ同じ形をしている。
そこで得た知見をそのまま使う。

- Caddy のサイトアドレスを `127.0.0.1:<port>` にすると、Caddy はそれを Host 名として照合し、cloudflared からのリクエストに一致せず空の 200 を返す。`http://:<port>` で受け、待ち受けアドレスは `default_bind 127.0.0.1` で絞る
- この回線は QUIC（UDP 7844）が塞がれているため、cloudflared の `protocol` に `http2` を指定する
- ユーザーサービスを常駐させるため、linger が必要である
- 秘密物（`~/.cloudflared/cert.pem` と `<トンネル ID>.json`）はモジュールに含めず、手で置く

## 検討して退けた選択肢

- パスで振り分ける（`aoi.ekuinox.dev/kgd/viewer/`）：kgd のビューアは資産と API を `/viewer/...` の絶対パスで参照している。プロキシがリクエストのパスを書き換えても、応答の中の絶対パスには手が届かない。接頭辞の下で動けるようにする改修が、載せるアプリごとに要る
- `kgd.aoi.ekuinox.dev` のように 2 階層目で分ける：無料の証明書が無い
- Access アプリを `*.ekuinox.dev` で作る：他の用途のサブドメインまでログインが必要になる
- サーバーごとに Access アプリと DNS レコードを作る：サーバーを載せるたびに Cloudflare 側の作業が要る。Access アプリを作り忘れると、そのサーバーはログイン無しで公開される
- kgd で Access の JWT を検証する：載せるアプリごとに同じ実装が要る。cloudflared の Protect with Access で代替できる
- `*.trycloudflare.com`（Quick Tunnel）：自分のゾーンではないため Access を張れず、ホスト名も起動のたびに変わる
- Tailscale や Cloudflare WARP のプライベートネットワーク：開く端末にクライアントが要る。今回は、任意の端末のブラウザから開けることを優先した

## 方針

### 構成

```
ブラウザ
  → Cloudflare エッジ … Access アプリ *-aoi.ekuinox.dev（自分のメールアドレスのみ Allow）
  → DNS *.ekuinox.dev（プロキシ付き CNAME）→ トンネル aoi-gateway
  → cloudflared（aoi） … catch-all で全ホスト名を Caddy へ。Protect with Access で JWT を検証
  → Caddy 127.0.0.1:8090（aoi） … Host の完全一致で振り分け、Cf-* ヘッダを削る。一致しなければ 404
  → 各サーバー（kgd は 172.20.1.1:8081）
```

既存の OwnTracks 用トンネル（`kgd-owntracks`、`private-owntracks.ekuinox.dev`）と kgd の compose には触らない。

### 命名規約

aoi のサーバーの公開ホスト名は `<サービス名>-aoi.ekuinox.dev` とする（kgd は `kgd-aoi.ekuinox.dev`）。
この形の名前は、作った時点で Access アプリ `*-aoi.ekuinox.dev` に覆われる。

### 各層の役割

| 層 | 役割 | サーバー追加時の作業 |
| --- | --- | --- |
| Access アプリ `*-aoi.ekuinox.dev` | ログインを強制する | なし |
| DNS `*.ekuinox.dev` | 明示したレコードの無い名前をトンネルへ向ける | なし |
| cloudflared | 全ホスト名を Caddy へ流す。Access を通っていないリクエストを止める | なし |
| Caddy | Host でサーバーへ振り分ける。Cf-* ヘッダを削る | `routes` に 1 行 |
| 各サーバー | 変更なし（Host の許可リストを持つアプリは、公開ホスト名を足す） | アプリの設定のみ |

Protect with Access があるため、Access の外の名前（`foo.ekuinox.dev` や 2 階層目の `x.kgd-aoi.ekuinox.dev`）がワイルドカード DNS でトンネルに届いても、cloudflared が 403 を返して Caddy まで届かない。
Access アプリを消したりホスト名を書き換えたりした場合も、公開されるのではなく 403 になる。
Caddy の Host の完全一致は、その手前で漏れたリクエストを止める二段目になる。

Caddy で Cf-* ヘッダを削るのは、kgd のガード 3（`Cf-Connecting-IP`、`Cf-Ray`、`Cdn-Loop` があれば拒否）がトンネル経由のリクエストをすべて拒否するためである。

### ホスト単位で丸ごと振り分ける

Caddy はホスト名だけで振り分け、パスは見ない。
そのため `kgd-aoi.ekuinox.dev` では、ビューアだけでなく 8081 番の待ち受け全体（OwnTracks の受け口の `/pub` と `/healthz` を含む）が Access の後ろに出る。
`/pub` は kgd の Basic 認証で守られたままであり、Access の後ろにも出ることで新たに開くものは無い。
パスで絞らないことで、モジュールは「サービス名から転送先への対応表」以上の知識をアプリについて持たずに済む。

### 転送先は aoi の LAN アドレスにする

Caddy から kgd への転送先は `127.0.0.1:8081` ではなく、aoi の LAN アドレス（`172.20.1.1:8081`）にする。

kgd のガード 2 は、送信元が `allowed_cidrs` に含まれるときだけ応答する。
既定値は LAN のプライベート帯で loopback を含まないため、`127.0.0.1` 宛に転送すると拒否される。
loopback を `allowed_cidrs` に足すと、aoi 上の任意のプロセスが Host を偽って認証無しでビューアを読めてしまう。

自ホストの LAN アドレス宛に接続すると、サーバーが見る送信元はそのアドレス自身になる（yomogi で実測した）。
`172.20.1.1` は既定の `172.16.0.0/12` に含まれるため、`allowed_cidrs` を変えずに済む。
aoi 自身が LAN アドレス経由で kgd に届くのは今日すでに可能であり、新たに広がる露出は無い。

LAN アドレスが変わると転送が壊れるため、DHCP の予約で固定する。
aoi 上の `ip -4 addr` で、`eth0` が `172.20.1.1/16` であることを確かめた（2026-10-12）。

## home-manager モジュールの設計

### ファイル構成

- `dot_config/home-manager/modules/aoi-gateway.nix`：Caddy と cloudflared のユーザーサービス、公開の確認スクリプトを定義する。オプションは `services.aoi-gateway`
- `dot_config/home-manager/hosts/aoi.nix`（新規）：aoi の値を書き、`modules/aoi-gateway.nix` を import する
- `dot_config/home-manager/flake.nix`：aoi の modules に `./hosts/aoi.nix` を足す
- `README.md`：ホスト表の aoi の行と、展開手順を更新する

door-lock の中継は mube 専用のため mube のリポジトリにモジュールがある。
gateway は aoi 全体の入口でどのアプリにも属さないため、モジュールを dotfiles に置く。

### オプション

| オプション | 型 | 既定値 | 説明 |
| --- | --- | --- | --- |
| `enable` | bool | false | 有効にする。linger が必要 |
| `domain` | str | なし | 公開ホスト名を置くゾーン |
| `hostSuffix` | str | `-aoi` | 公開ホスト名の 1 階層目に付ける接尾辞 |
| `routes` | attrsOf str | `{}` | サービス名から転送先 URL への対応表 |
| `tunnelId` | str | なし | トンネルの UUID |
| `teamName` | str | なし | Zero Trust のチーム名 |
| `audTags` | nonEmptyListOf str | なし | Access アプリの AUD タグ |
| `proxyPort` | port | 8080 | Caddy の待ち受けポート（127.0.0.1 のみ） |
| `protocol` | nullOr str | null | cloudflared のトンネルプロトコル |
| `credentialsFile` | str | `~/.cloudflared/<tunnelId>.json` | トンネルの認証情報のパス |

公開ホスト名は `<サービス名><hostSuffix>.<domain>` としてモジュールが組み立てる。
`routes` にホスト名そのものを書かせないのは、Access アプリ `*-aoi.ekuinox.dev` の外の名前を設定できないようにするためである。
サービス名は DNS の 1 ラベルの一部になり Caddy の matcher 名にも使うため、英小文字、数字、ハイフンに限り、評価時の assertion で確かめる。

`hosts/aoi.nix` では次のように書く。

```nix
services.aoi-gateway = {
  enable = true;
  domain = "ekuinox.dev";
  tunnelId = "<UUID>";
  teamName = "<チーム名>";
  audTags = [ "<AUD タグ>" ];
  protocol = "http2";
  routes = {
    kgd = "http://172.20.1.1:8081";
  };
};
```

トンネルを作るまでは値が揃わないため、最初の PR では `enable = false` で入れる。

### 生成する Caddyfile

`routes` から次の Caddyfile を生成する（上の例の場合）。

```
{
	default_bind 127.0.0.1
	admin off
	auto_https off
	persist_config off
}

http://:8080 {
	log {
		output stderr
		format json
	}
	@kgd host kgd-aoi.ekuinox.dev
	handle @kgd {
		reverse_proxy http://172.20.1.1:8081 {
			header_up -Cf-*
			header_up -Cdn-Loop
		}
	}
	handle {
		respond "not found" 404
	}
}
```

`host` マッチャは完全一致（大文字小文字は区別しない）のため、`x.kgd-aoi.ekuinox.dev` は `handle @kgd` に入らない。
Caddy は既定で元の Host を転送先へ渡すため、kgd には `Host: kgd-aoi.ekuinox.dev` が届く。

### 生成する cloudflared の設定

```yaml
tunnel: <UUID>
credentials-file: /home/ekuinox/.cloudflared/<UUID>.json
protocol: http2
ingress:
  - service: http://127.0.0.1:8080
    originRequest:
      access:
        required: true
        teamName: <チーム名>
        audTag:
          - <AUD タグ>
```

### ユーザーサービス

door-lock の中継と同じ形で、次の 2 つを `default.target` に結び付ける。

- `aoi-gateway-proxy`：`caddy run --config <生成した Caddyfile> --adapter caddyfile`
- `cloudflared-aoi-gateway`：`cloudflared tunnel --config <生成した設定> run`

aoi では kgd の compose の中でも cloudflared（OwnTracks 用）が動いているが、トンネルが別であり、待ち受けるポートも無いため衝突しない。

### 公開の確認スクリプト

`aoi-gateway-check` をモジュールでパッケージ化する（`git-setup-signing` と同じく `writeShellApplication`）。
`routes` から組み立てた公開ホスト名を焼き込み、未ログインで次を確かめる。

- 各公開ホスト名の `/` が 302 で `cloudflareaccess.com` へ飛ばされる
- `-aoi` で終わらない存在しない名前（`aoi-gateway-check-<乱数>.ekuinox.dev`）が 403 を返す
- 同じ名前に偽の `Cf-Access-Jwt-Assertion` を付けても 4xx か 5xx を返す

ログイン後の確認（Caddy の完全一致など）はブラウザで行う。

## 展開手順

1. Access アプリ `*-aoi.ekuinox.dev` のチーム名と AUD タグを控える。チーム名はログイン画面の URL（`<チーム名>.cloudflareaccess.com`）、AUD タグはアプリの設定画面の Application Audience (AUD) Tag で分かる
2. `cert.pem` のあるマシンで `cloudflared tunnel create --credentials-file <書き出し先> aoi-gateway` を実行し、出力された UUID を控える。書き出した認証情報を aoi の `~/.cloudflared/<UUID>.json` に置く。`--credentials-file` を省くと、そのマシンの `config.yml` の `credentials-file`（yomogi では door-lock の認証情報）に書き出そうとし、既存のファイルがあるため書き出しに失敗する（トンネルだけが作られる）
3. aoi で `loginctl enable-linger` が有効かを確かめ、無効なら有効にする。`ip -4 addr` で LAN アドレスを確かめ、DHCP の予約を取る。`ss -ltn` で 8080 番が空いていることも確かめる（塞がっていれば `proxyPort` を変える）
4. `hosts/aoi.nix` に `tunnelId`、`teamName`、`audTags` を書き、`enable = true` にしてマージする。aoi で `hms` を実行し、`systemctl --user status aoi-gateway-proxy cloudflared-aoi-gateway` で 2 つが動いていることを確かめる
5. kgd の `config.toml` の `[location.viewer] allowed_hosts` に `kgd-aoi.ekuinox.dev` を足し、kgd を起動し直す。本番の `allowed_cidrs` に aoi の LAN アドレスが含まれることも確かめる
6. ダッシュボードで `ekuinox.dev` の DNS に、Name `*`、Target `<UUID>.cfargotunnel.com` のプロキシ付き CNAME を作る。`cloudflared tunnel route dns <UUID> '*.ekuinox.dev'` でも作れるはずだが未検証である。コマンドで作るときは必ず UUID で指定し、出力の `tunnelID` が控えた UUID と一致することを確かめる
7. 下の確認項目をすべて満たすことを確かめる

DNS を最後に作るのは、すべての層が揃うまで外からのリクエストを届かせないためである。
Protect with Access があるため、順序を誤っても公開にはならず 403 になる。

## 確認項目

| 確かめること | 期待する結果 | 分かること |
| --- | --- | --- |
| 未ログインで `https://kgd-aoi.ekuinox.dev/viewer/` | 302 で `cloudflareaccess.com` へ | 公開ホスト名に Access が効いている |
| 未ログインで `https://nope.ekuinox.dev/` | 403 | Access の外の名前を cloudflared が止める |
| ログイン後に `https://kgd-aoi.ekuinox.dev/viewer/2026/10/12` のような深いパス | ビューアが表示される | kgd の改修無しで動く |
| ログイン後に `https://zzz-aoi.ekuinox.dev/` | 404 | Caddy が Host の完全一致で振り分けている |
| `https://x.kgd-aoi.ekuinox.dev/` | TLS のエラーか 403 | 2 階層目の名前が kgd に届かない |
| kgd の `just check-exposure https://private-owntracks.ekuinox.dev` | すべて ok | OwnTracks のトンネルが変わっていない |
| LAN から `http://aoi.local:8081/viewer/` | 表示される | LAN からの経路が変わっていない |
| `www.ekuinox.dev` など既存のサブドメイン | これまでどおり開ける | 他の用途に影響が無い |

上から 2 行は `aoi-gateway-check` で自動化する。

## サーバーを追加する手順

1. サーバーを aoi の LAN アドレスで待ち受けさせる
2. `hosts/aoi.nix` の `routes` に `<サービス名> = "http://172.20.1.1:<ポート>";` を足し、aoi で `hms` を実行する
3. アプリが Host の許可リストを持つなら、公開ホスト名を足す
4. `aoi-gateway-check` を実行する

Cloudflare 側の作業は無い。

## 受け入れる制約

- ワイルドカード DNS により、明示したレコードの無い `ekuinox.dev` のサブドメインはすべて名前解決でき、証明書も付き、403 を返す。MX や TXT の問い合わせにも CNAME が返るため、レコードの無い名前でメールを受けたり DNS-01 で証明書を取ったりするには、その名前に明示したレコードを作る
- Protect with Access が確かめるのは「このアプリを通ったか」であり、「誰を通すか」の正しさではない。Allow ポリシーを誤って広げた場合は止められない
- Access アプリを作り直すと AUD タグが変わる。`audTags` を更新するまで、すべてのリクエストが 403 になる
- gateway の Caddy か cloudflared が止まると、外からの経路だけが止まる。LAN からの経路と OwnTracks のトンネルは影響を受けない
- aoi の LAN アドレスが変わると転送が壊れる

## 公開リポジトリに置く値

dotfiles は public であり、秘密情報は置かない。

置くもの：公開ホスト名、トンネルの UUID、チーム名、AUD タグ、aoi の LAN アドレス。
いずれも秘密ではない。
トンネルの UUID は単独ではトンネルを使えず（他のアカウントの DNS からは使えないと公式ドキュメントにある）、door-lock の UUID もすでに `hosts/yomogi.nix` にある。
AUD タグはログインした利用者の JWT に毎回含まれ、チーム名はログイン画面の URL に現れる。

置かないもの：`cert.pem` と `<UUID>.json`。

## kgd 側の変更

kgd のリポジトリで別の PR として行う。
コードの変更は無く、文書だけである。

- 新しい ADR（0015）で、ビューアを aoi の gateway 経由でも公開することを決める。gateway の経路は、LAN アドレスへの転送と Cf-* ヘッダの削除によって、ガード 2 と 3 を迂回する。信頼の境界は Access、cloudflared の JWT 検証、Caddy の loopback での待ち受けに移る。ADR-0013 の「公開するときはオリジン側での Access の JWT 検証と合わせて設定を変える」は、cloudflared での検証に置き換える。ガード 1 と 4 は引き続き効き、公開ホスト名を `allowed_hosts` に書く必要がある。ADR-0013 のステータスに、一部を 0015 で置き換えたことを書く
- README の「Cloudflare Access は使わない」は OwnTracks のトンネルについての記述であることを明確にし、ビューアを外から開く方法として gateway を参照する
- README の `cloudflared tunnel route dns kgd-owntracks <ホスト名>` を UUID で指定する形に直し、理由を書く

## 未確定事項

- 本番の kgd の `allowed_cidrs` に aoi の LAN アドレスが含まれるか

2026-10-12 に aoi で次を確かめた。

- LAN アドレスは `172.20.1.1`
- linger は有効
- 8080 番は別のプロセス（python3）が使っているため、`hosts/aoi.nix` では `proxyPort = 8090` にした

同日、トンネル `aoi-gateway`（`f8c8da83-f4d2-4b84-8c85-9f0c51feca13`）を作成した。
チーム名は、既存の Access アプリのログイン画面の URL から `white-fog-5e56` と分かった。
`cloudflared tunnel route dns <UUID> '*.ekuinox.dev'` でワイルドカードの CNAME を作れた。
AUD タグは、`kgd-aoi.ekuinox.dev` を未ログインで開いたときのリダイレクト先の URL の `kid` から読み取れた。
