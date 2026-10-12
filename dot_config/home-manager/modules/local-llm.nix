# ローカル LLM（llama.cpp の llama-server + Qwythos-9B-v2）を動かすホスト用のモジュール。
# GPU（CUDA）を持つ個体だけが imports で取り込む（現状 hizake のみ。ume は GPU が無い）。
# llama-server は Web UI（http://localhost:8080）と OpenAI 互換 API を提供し、
# gh CLI を叩く自前の MCP サーバー（packages/gh-search-mcp.nix）を github_* ツールとして持つ。
{ pkgs, lib, ... }:
let
  # CUDA 版 llama-cpp は unfree な cudaPackages に依存し、公式キャッシュに無いため手元でビルドする。
  # unfree 許可と対象 GPU の限定はこの import にだけ効かせ、ホスト全体の nixpkgs には波及させない。
  # cudaSupport を config で立てると依存全体が CUDA 版に切り替わりキャッシュが外れるため、
  # llama-cpp の override でだけ有効にする。cudaCapabilities は RTX 3070 (Ampere, sm_86) に
  # 絞り、ビルド時間を短縮する。
  cudaPkgs = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config = {
      allowUnfree = true;
      cudaCapabilities = [ "8.6" ];
    };
  };

  # nix の CUDA バイナリは libcuda を /run/opengl-driver/lib から探すが、Ubuntu の WSL には
  # 無い。WSL では Windows 側ドライバが /usr/lib/wsl/lib に libcuda を公開しているので、
  # 全コマンドをラップしてそこを参照させる。これが無いと黙って CPU 実行にフォールバックする。
  llama-cpp = pkgs.symlinkJoin {
    name = "llama-cpp-wsl-cuda";
    paths = [ (cudaPkgs.llama-cpp.override { cudaSupport = true; }) ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for f in $out/bin/*; do
        wrapProgram "$f" --suffix LD_LIBRARY_PATH : /usr/lib/wsl/lib
      done
    '';
  };

  # モデル本体（約 5.7GB）。リポジトリのリビジョンとハッシュ（上流の SHA256SUMS）で固定する。
  # ExecStart から参照するため世代の closure に入り、GC で消えない。
  model = pkgs.fetchurl {
    url = "https://huggingface.co/empero-ai/Qwythos-9B-v2-GGUF/resolve/97c11b03687f194b300efbdb4760d9bc4021b759/Qwythos-9B-v2-Q4_K_M.gguf";
    sha256 = "c0a588704f422b713eca29b2c1f192ae6f69aea3f9e7cb64f9ecdb76ff7a85f4";
  };

  gh-search-mcp = pkgs.callPackage ../packages/gh-search-mcp.nix { };

  # llama-server に渡す MCP サーバー定義（Cursor 互換形式）。ツールは <server>_<tool> の名前で
  # 公開されるため、サーバー名 github により github_search_repos 等になる。
  mcpConfig = pkgs.writeText "llama-mcp-servers.json" (builtins.toJSON {
    mcpServers.github = {
      command = lib.getExe gh-search-mcp;
      args = [ ];
      timeout_ms = 60000;
    };
  });
in
{
  home.packages = [ llama-cpp ];

  # 常駐はさせない（WantedBy を付けない）。起動中は VRAM を数 GB 占有するため、
  # 使うときだけ `systemctl --user start llama-server` で起動し、`stop` で止める。
  # VRAM 8GB に全層は載らないため --fit で載る分だけ GPU に置き、残りは CPU で動かす。
  # 待ち受けは 127.0.0.1 のみ。WSL の mirrored networking により Windows 側の
  # ブラウザからも http://localhost:8080 で開ける。
  systemd.user.services.llama-server = {
    Unit.Description = "llama-server (Qwythos-9B-v2, GitHub search MCP)";
    Service = {
      ExecStart = lib.concatStringsSep " " [
        "${llama-cpp}/bin/llama-server"
        "-m ${model}"
        "--alias qwythos-9b-v2"
        "-c 32768 --fit on"
        "--temp 0.6 --top-p 0.95 --top-k 20"
        "--mcp-servers-config ${mcpConfig}"
        "--host 127.0.0.1 --port 8080"
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
