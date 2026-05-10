#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fail=0
ok() { echo "ok: $*"; }
bad() { echo "fail: $*" >&2; fail=1; }

NEO4J_DIR="${HOME}/.codegraphcontext/neo4j"
PASS_FILE="${NEO4J_DIR}/.password"
CGC_ENV="${HOME}/.codegraphcontext/.env"
MCP_JSON="${HOME}/.cursor/mcp.json"

if command -v codegraphcontext >/dev/null 2>&1; then
  ok "codegraphcontext on PATH ($(command -v codegraphcontext))"
else
  bad "codegraphcontext not on PATH"
fi

if pipx list 2>/dev/null | grep -q 'package codegraphcontext'; then
  ok "pipx package codegraphcontext installed"
else
  bad "pipx package codegraphcontext missing"
fi

if pipx runpip codegraphcontext show tree-sitter 2>/dev/null | grep -q 'Version: 0.25.2'; then
  ok "tree-sitter pin 0.25.2"
else
  bad "tree-sitter not at 0.25.2 (run bootstrap.sh)"
fi

if pipx runpip codegraphcontext show tree-sitter-language-pack 2>/dev/null | grep -q 'Version: 0.13.0'; then
  ok "tree-sitter-language-pack pin 0.13.0"
else
  bad "tree-sitter-language-pack not at 0.13.0 (run bootstrap.sh)"
fi

if docker ps --filter name=cgc-neo4j --filter status=running --format '{{.Names}}' | grep -q '^cgc-neo4j$'; then
  ok "container cgc-neo4j running"
else
  bad "container cgc-neo4j not running (make cgc-up)"
fi

if command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 7687 2>/dev/null; then
  ok "127.0.0.1:7687 open"
else
  bad "127.0.0.1:7687 not reachable (or nc missing)"
fi

if [[ -f "$CGC_ENV" ]] && grep -q '^DEFAULT_DATABASE=neo4j' "$CGC_ENV"; then
  ok "~/.codegraphcontext/.env has DEFAULT_DATABASE=neo4j"
else
  bad "missing or wrong ~/.codegraphcontext/.env"
fi

if [[ -f "$MCP_JSON" ]]; then
  if jq -e '.mcpServers.CodeGraphContext.command' "$MCP_JSON" >/dev/null 2>&1; then
    ok "~/.cursor/mcp.json has CodeGraphContext server"
  else
    bad "~/.cursor/mcp.json missing CodeGraphContext (run bootstrap without --no-mcp)"
  fi
else
  bad "~/.cursor/mcp.json missing"
fi

if [[ -f "$PASS_FILE" ]]; then
  PW="$(cat "$PASS_FILE")"
  cnt=$(docker exec cgc-neo4j cypher-shell -u neo4j -p "$PW" --format plain 'MATCH (n) RETURN count(n) AS c' 2>/dev/null | tail -1 | tr -d ' ')
  if [[ "${cnt:-0}" =~ ^[0-9]+$ ]] && [[ "${cnt:-0}" -gt 0 ]]; then
    ok "graph has ${cnt} nodes"
  else
    bad "graph empty or query failed (run: make cgc-index PATHS=\"/your/repo\")"
  fi
else
  bad "missing ${PASS_FILE}"
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "all checks passed"
