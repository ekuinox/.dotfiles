# hizake: GPU（RTX 3070）を持つ WSL 機の個体名。wsl.nix を継承し、ローカル LLM を足す。
# 同じ WSL の ume は GPU を持たないため、ローカル LLM は wsl.nix ではなくここで取り込む。
{ ... }:
{
  imports = [ ../modules/local-llm.nix ];
}
