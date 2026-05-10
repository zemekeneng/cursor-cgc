#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

NO_MCP=0
NO_CURSOR_RULE=0
FORCE_CURSOR_RULE=0
INDEX_PATHS=()

usage() {
  echo "Usage: $0 [--no-mcp] [--no-cursor-rule] [--force-cursor-rule] [--index PATH] ..."
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-mcp) NO_MCP=1; shift ;;
    --no-cursor-rule) NO_CURSOR_RULE=1; shift ;;
    --force-cursor-rule) FORCE_CURSOR_RULE=1; shift ;;
    --index)
      if [[ $# -lt 2 ]]; then usage; fi
      INDEX_PATHS+=("$2")
      shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command '$1'"
}

echo "==> preflight"
require_cmd docker
require_cmd jq
require_cmd openssl
require_cmd shasum
if ! command -v pipx >/dev/null 2>&1; then
  die "pipx not found. Install: brew install pipx && pipx ensurepath  (then restart shell)"
fi
python3.12 -c "import sys" 2>/dev/null || die "python3.12 not found (required for tree-sitter pins)"

NEO4J_DIR="${HOME}/.codegraphcontext/neo4j"
CGC_ENV="${HOME}/.codegraphcontext/.env"
MCP_JSON="${HOME}/.cursor/mcp.json"
CURSOR_RULE_DIR="${HOME}/.cursor/rules"
CURSOR_RULE="${CURSOR_RULE_DIR}/cgc-routing.mdc"
RULE_CHECKSUM="${CURSOR_RULE_DIR}/.cgc-routing.checksum"
TEMPLATE_RULE="${CURSOR_CGC_ROOT}/templates/cgc-routing.mdc"
TEMPLATE_COMPOSE="${CURSOR_CGC_ROOT}/templates/docker-compose.yml"

echo "==> pipx: codegraphcontext + tree-sitter pins"
if pipx list 2>/dev/null | grep -q 'package codegraphcontext'; then
  echo "    codegraphcontext already installed; re-applying pins"
else
  pipx install --python python3.12 codegraphcontext
fi
pipx inject codegraphcontext --force "tree-sitter==0.25.2" "tree-sitter-language-pack==0.13.0"

CGC_BIN="$(command -v codegraphcontext)"
[[ -n "$CGC_BIN" ]] || die "codegraphcontext not on PATH after pipx install"

echo "==> Neo4j directory ${NEO4J_DIR}"
mkdir -p "$NEO4J_DIR"
PASS_FILE="${NEO4J_DIR}/.password"
if [[ ! -f "$PASS_FILE" ]]; then
  openssl rand -base64 24 | tr -d '/+=' | cut -c1-24 > "$PASS_FILE"
fi
chmod 600 "$PASS_FILE" 2>/dev/null || true
NEO4J_PASSWORD="$(cat "$PASS_FILE")"
printf 'NEO4J_PASSWORD=%s\n' "$NEO4J_PASSWORD" > "${NEO4J_DIR}/.env"
chmod 600 "${NEO4J_DIR}/.env"
cp -f "$TEMPLATE_COMPOSE" "${NEO4J_DIR}/docker-compose.yml"

if [[ -f "$CGC_ENV" ]]; then
  cp "$CGC_ENV" "${CGC_ENV}.bak.$(date +%s)"
fi
cat > "$CGC_ENV" << EOF
DEFAULT_DATABASE=neo4j
NEO4J_URI=neo4j://127.0.0.1:7687
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=${NEO4J_PASSWORD}
EOF
chmod 600 "$CGC_ENV"

if [[ "$NO_MCP" -eq 0 ]]; then
  echo "==> merge CodeGraphContext into ${MCP_JSON}"
  mkdir -p "$(dirname "$MCP_JSON")"
  if [[ ! -f "$MCP_JSON" ]]; then
    echo '{"mcpServers":{}}' > "$MCP_JSON"
  fi
  tmp="$(mktemp)"
  jq --arg cmd "$CGC_BIN" \
    '.mcpServers.CodeGraphContext = {"command": $cmd, "args": ["mcp", "start"]}' \
    "$MCP_JSON" > "$tmp" && mv "$tmp" "$MCP_JSON"
else
  echo "==> skip MCP (--no-mcp)"
fi

if [[ "$NO_CURSOR_RULE" -eq 0 ]]; then
  echo "==> Cursor rule ${CURSOR_RULE}"
  mkdir -p "$CURSOR_RULE_DIR"
  do_install_rule=0
  if [[ "$FORCE_CURSOR_RULE" -eq 1 ]]; then
    do_install_rule=1
  elif [[ ! -f "$CURSOR_RULE" ]]; then
    do_install_rule=1
  elif [[ ! -f "$RULE_CHECKSUM" ]]; then
    do_install_rule=1
  else
    stored="$(cat "$RULE_CHECKSUM")"
    current="$(cgc_sha256 "$CURSOR_RULE")"
    if [[ "$current" == "$stored" ]]; then
      do_install_rule=1
    else
      echo "    skip: ${CURSOR_RULE} was edited (use --force-cursor-rule)"
    fi
  fi
  if [[ "$do_install_rule" -eq 1 ]]; then
    cp -f "$TEMPLATE_RULE" "$CURSOR_RULE"
    cgc_sha256 "$CURSOR_RULE" > "$RULE_CHECKSUM"
  fi
else
  echo "==> skip Cursor rule (--no-cursor-rule)"
fi

echo "==> Neo4j up"
make -C "$CURSOR_CGC_ROOT" cgc-up

for p in "${INDEX_PATHS[@]}"; do
  [[ -d "$p" ]] || die "index path is not a directory: $p"
  echo "==> index $p"
  "$CGC_BIN" index --force "$p"
done

echo ""
echo "Done."
echo "  Neo4j browser: http://localhost:7474"
echo "  Password file: ${PASS_FILE}"
echo "  CLI: ${CGC_BIN}"
echo "  Health check: make -C ${CURSOR_CGC_ROOT} cgc-doctor"
echo "  Index more repos: make -C ${CURSOR_CGC_ROOT} cgc-index PATHS=\"/path/to/repo\""
