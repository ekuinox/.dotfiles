#!/usr/bin/env python3
"""Minimal stdio MCP server that lets a local LLM search GitHub through the gh CLI.

Only read-only gh subcommands are exposed; arguments are passed as argv (no shell).
"""
import base64
import json
import subprocess
import sys

GH = "gh"  # nix パッケージ化の際に絶対パスへ置き換える
MAX_CHARS = 12000
TIMEOUT = 60

TOOLS = [
    {
        "name": "search_repos",
        "description": "Search GitHub repositories. Supports GitHub search qualifiers in query (e.g. 'llm language:rust stars:>100').",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search keywords and qualifiers"},
                "sort": {"type": "string", "enum": ["best-match", "stars", "forks", "updated"], "description": "Sort order (default best-match)"},
                "limit": {"type": "integer", "description": "Max results, 1-20 (default 10)"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "search_code",
        "description": "Search code on GitHub. Returns matching file paths with snippets. Use 'repo:owner/name' or 'language:python' in query to narrow.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search keywords and qualifiers"},
                "limit": {"type": "integer", "description": "Max results, 1-20 (default 10)"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "search_issues",
        "description": "Search GitHub issues and pull requests. Use 'repo:owner/name', 'is:pr', 'is:open' etc. in query.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search keywords and qualifiers"},
                "limit": {"type": "integer", "description": "Max results, 1-20 (default 10)"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "view_repo",
        "description": "Show a repository's description, stats and README.",
        "inputSchema": {
            "type": "object",
            "properties": {"repo": {"type": "string", "description": "owner/name"}},
            "required": ["repo"],
        },
    },
    {
        "name": "read_file",
        "description": "Read a file (or list a directory) from a GitHub repository.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "repo": {"type": "string", "description": "owner/name"},
                "path": {"type": "string", "description": "Path in the repo; empty for root directory"},
                "ref": {"type": "string", "description": "Branch, tag or commit (default: default branch)"},
            },
            "required": ["repo"],
        },
    },
]


def run_gh(args):
    p = subprocess.run([GH, *args], capture_output=True, text=True, timeout=TIMEOUT)
    if p.returncode != 0:
        raise RuntimeError((p.stderr or p.stdout).strip() or f"gh exited with {p.returncode}")
    return p.stdout


def clamp_limit(v):
    try:
        return str(max(1, min(20, int(v or 10))))
    except (TypeError, ValueError):
        return "10"


def check_repo(repo):
    if not isinstance(repo, str) or repo.count("/") != 1 or repo.startswith("-"):
        raise ValueError("repo must be 'owner/name'")
    return repo


def query_args(q):
    # "--" stops gh from treating a query beginning with "-" as a flag
    return ["--", str(q)]


def call_tool(name, a):
    if name == "search_repos":
        args = ["search", "repos", "--limit", clamp_limit(a.get("limit")),
                "--json", "fullName,description,stargazersCount,language,updatedAt,url"]
        if a.get("sort") in ("stars", "forks", "updated"):
            args += ["--sort", a["sort"]]
        return run_gh(args + query_args(a["query"]))
    if name == "search_code":
        out = json.loads(run_gh(["search", "code", "--limit", clamp_limit(a.get("limit")),
                                 "--json", "path,repository,url,textMatches"] + query_args(a["query"])))
        slim = [{"repo": r["repository"]["nameWithOwner"], "path": r["path"], "url": r["url"],
                 "snippets": [m.get("fragment", "") for m in r.get("textMatches", [])][:2]} for r in out]
        return json.dumps(slim, ensure_ascii=False)
    if name == "search_issues":
        return run_gh(["search", "issues", "--include-prs", "--limit", clamp_limit(a.get("limit")),
                       "--json", "repository,number,title,state,isPullRequest,updatedAt,url"]
                      + query_args(a["query"]))
    if name == "view_repo":
        return run_gh(["repo", "view", check_repo(a["repo"])])
    if name == "read_file":
        path = str(a.get("path") or "").strip("/")
        if ".." in path.split("/"):
            raise ValueError("invalid path")
        endpoint = f"repos/{check_repo(a['repo'])}/contents/{path}"
        if a.get("ref"):
            endpoint += "?ref=" + str(a["ref"])
        data = json.loads(run_gh(["api", "-X", "GET", endpoint]))
        if isinstance(data, list):
            return "\n".join(f"{e['type']}\t{e['path']}" for e in data)
        if data.get("encoding") == "base64":
            return base64.b64decode(data["content"]).decode("utf-8", errors="replace")
        return json.dumps(data, ensure_ascii=False)
    raise ValueError(f"unknown tool: {name}")


def reply(msg_id, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": msg_id}
    if error is not None:
        msg["error"] = error
    else:
        msg["result"] = result
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            continue
        method, msg_id = req.get("method"), req.get("id")
        if msg_id is None:  # notification
            continue
        if method == "initialize":
            reply(msg_id, {
                "protocolVersion": req.get("params", {}).get("protocolVersion", "2025-06-18"),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "gh-search", "version": "0.1.0"},
            })
        elif method == "tools/list":
            reply(msg_id, {"tools": TOOLS})
        elif method == "tools/call":
            p = req.get("params", {})
            try:
                text = call_tool(p.get("name"), p.get("arguments") or {})
                if len(text) > MAX_CHARS:
                    text = text[:MAX_CHARS] + f"\n...[truncated, {len(text)} chars total]"
                reply(msg_id, {"content": [{"type": "text", "text": text}], "isError": False})
            except Exception as e:
                reply(msg_id, {"content": [{"type": "text", "text": f"Error: {e}"}], "isError": True})
        elif method == "ping":
            reply(msg_id, {})
        else:
            reply(msg_id, error={"code": -32601, "message": f"method not found: {method}"})


if __name__ == "__main__":
    main()
