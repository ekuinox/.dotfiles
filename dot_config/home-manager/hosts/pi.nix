# Raspberry Pi (aarch64) 共通のホスト設定。yomogi / sumomo / aoi が読む。
# 現状 pi 固有の差分は無い。pi 系で共通化したい設定をここに追記すると、
# flake.nix で各 Pi ホストの modules に本ファイルを含めているため全機に反映される。
# paseo はここには置かない。ビルドが重いため pi 系では yomogi だけが個別に取り込む。
{ ... }:
{
}
