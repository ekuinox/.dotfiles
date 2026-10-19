# ibuki: 自宅の x86_64 実機サーバー（Ubuntu、ヘッドレス）の個体名。
# WSL ではないため wsl.nix（herdr）は読まず、paseo だけを個別に取り込む。
# x86_64 の paseo は公式コンテナイメージ由来なのでソースビルドは走らない。
# ヘッドレス運用のため、paseo デーモンの常駐には `loginctl enable-linger` が必要。
{ ... }:
{
  imports = [ ../modules/paseo.nix ];
}
