# ローカル LLM（llama-server）に GitHub を検索させるための stdio MCP サーバー。
# gh CLI の読み取り系サブコマンドだけを argv で直接呼ぶ（シェルを通さない）。
# 認証は gh のログイン状態（~/.config/gh）をそのまま使う。
# 本体は別ファイル（../scripts/gh-search-mcp.py）に置き、gh を絶対パスに差し替える。
{ runCommand, python3, gh }:

runCommand "gh-search-mcp" { meta.mainProgram = "gh-search-mcp"; } ''
  install -Dm755 ${../scripts/gh-search-mcp.py} $out/bin/gh-search-mcp
  substituteInPlace $out/bin/gh-search-mcp \
    --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python3' \
    --replace-fail 'GH = "gh"' 'GH = "${gh}/bin/gh"'
''
