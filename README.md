# cursor-cgc

Reproducible [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) setup for **Cursor**: pipx CLI, **Neo4j 5.21** in Docker (Bolt `127.0.0.1:7687`, Browser `http://localhost:7474`), MCP wiring in `~/.cursor/mcp.json`, optional routing rule (see **Cursor: where rules appear** below).

**Does not live inside your app repos.** Index whichever paths you want with `make cgc-index`.

## Prerequisites

- macOS or Linux with **Docker**
- **Python 3.12** (for `pipx install --python python3.12`)
- **[pipx](https://pipx.pypa.io/)** — e.g. `brew install pipx && pipx ensurepath`
- **jq**, **openssl**, **netcat** (`nc`) for scripts

## Quick start

```bash
git clone git@github.com:zemekeneng/cursor-cgc.git
cd cursor-cgc
make cgc-bootstrap ARGS='--index /path/to/your/repo'
```

Or bootstrap without indexing:

```bash
make cgc-bootstrap
make cgc-index PATHS="/path/to/repo1 /path/to/repo2"
```

Cloud / headless (no Cursor files on that machine):

```bash
bash scripts/bootstrap.sh --no-mcp --no-cursor-rule --index /path/to/repo
```

## Bootstrap flags

| Flag | Meaning |
|------|---------|
| `--no-mcp` | Do not modify `~/.cursor/mcp.json` |
| `--no-cursor-rule` | Do not install backup copy under `~/.cursor/rules/` |
| `--force-cursor-rule` | Overwrite `~/.cursor/rules/cgc-routing.mdc` even if edited |
| `--project-rule-repo DIR` | Copy rule to `DIR/.cursor/rules/` (**this path shows in Cursor Rules UI**) |
| `--index PATH` | Run `codegraphcontext index --force` on `PATH` (repeatable) |

## Cursor: where rules appear

Per [Cursor docs](https://cursor.com/docs/context/rules):

- **Project rules** live in **`<opened-repo>/.cursor/rules/`** — listed in the Rules UI.
- **User rules** live in **Cursor Settings → Rules** — global text for Agent chat.

`~/.cursor/rules/*.mdc` is **not** a documented rules location, so the UI will not list files you copy there. Use a project path or User Rules.

**Ways to activate routing:**

1. Per repo (visible in sidebar):
   ```bash
   make cgc-copy-rule REPO=/path/to/your/repo
   ```
   or `make cgc-bootstrap ARGS='--project-rule-repo /path/to/your/repo'`

2. Global: **Cursor Settings → Rules** → paste [templates/cgc-routing.mdc](templates/cgc-routing.mdc).

## Makefile targets

| Target | Purpose |
|--------|---------|
| `cgc-bootstrap` | Run `scripts/bootstrap.sh` (pass extra args via `ARGS='...'`) |
| `cgc-copy-rule` | `make cgc-copy-rule REPO=/path/to/repo` → installs project rule Cursor can see |
| `cgc-doctor` | Verify install, pins, Neo4j, MCP entry, non-empty graph |
| `cgc-up` / `cgc-down` | Start/stop Neo4j container |
| `cgc-status` | Container + `codegraphcontext list` tail |
| `cgc-logs` | `docker logs -f cgc-neo4j` |
| `cgc-index` | `make cgc-index PATHS="/a /b"` |
| `cgc-reset` | `docker compose down -v` then re-index (requires `PATHS`) |
| `cgc-browser` | Open Neo4j Browser |
| `cgc-password` | Print Neo4j password |
| `cgc-tx` / `cgc-kill-all` / `cgc-kill id=...` | Inspect / kill runaway Cypher transactions |
| `cgc-uninstall` | Remove container volumes, `~/.codegraphcontext`, pipx package |

## Per-repo `.cgcignore`

Like `.gitignore`, place `.cgcignore` at a repo root to exclude paths from indexing. Examples: [templates/cgcignore.python](templates/cgcignore.python), [templates/cgcignore.content](templates/cgcignore.content).

## Tree-sitter pins

Known-good combo (applied by bootstrap):

- `tree-sitter==0.25.2`
- `tree-sitter-language-pack==0.13.0`

## Cursor Cloud

Clone this repo in the agent environment, run `bash scripts/bootstrap.sh --no-mcp --no-cursor-rule`, then index your checkout. No changes required in consumer repos beyond optional `.cgcignore`.

## Troubleshooting

- **`cgc-doctor` fails on empty graph** — normal before first index; run `make cgc-index PATHS="..."`.
- **High CPU / “hang” on MCP queries** — often `find_all_callers` cartesian blowup. Prefer `find_callers`. Neo4j transaction timeout defaults to **30s** in [templates/docker-compose.yml](templates/docker-compose.yml).
- **List stuck queries:** `make cgc-tx`. **Kill one:** `make cgc-kill id=neo4j-transaction-N`. **Kill all user queries:** `make cgc-kill-all`.

## Uninstall

```bash
make cgc-uninstall
```

Then manually remove `CodeGraphContext` from `~/.cursor/mcp.json` and delete `~/.cursor/rules/cgc-routing.mdc` if desired.

## License

Scripts and templates in this repo: use as you like with your CGC/Neo4j setup. Upstream CodeGraphContext has its own license.
