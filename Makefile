# cursor-cgc — CodeGraphContext + Neo4j for Cursor MCP
# https://github.com/zemekeneng/cursor-cgc

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
export PATH := $(HOME)/.local/bin:$(PATH)
CGC_BIN := $(shell command -v codegraphcontext 2>/dev/null)
CGC_NEO4J_DIR := $(HOME)/.codegraphcontext/neo4j
CGC_COMPOSE := docker compose -f $(CGC_NEO4J_DIR)/docker-compose.yml

.PHONY: help cgc-bootstrap cgc-doctor cgc-copy-rule cgc-up cgc-down cgc-status cgc-logs \
	cgc-index cgc-reset cgc-browser cgc-password cgc-tx cgc-kill cgc-kill-all cgc-uninstall

help:
	@echo "cursor-cgc targets:"
	@echo "  make cgc-bootstrap [ARGS='--no-mcp --index /path']  — full install + Neo4j up"
	@echo "  make cgc-copy-rule REPO=/path  — install MCP routing rule where Cursor UI lists it"
	@echo "  make cgc-doctor    — verify stack"
	@echo "  make cgc-up / cgc-down / cgc-status / cgc-logs"
	@echo "  make cgc-index PATHS=\"/repo1 /repo2\"  — re-index (requires paths)"
	@echo "  make cgc-reset PATHS=\"...\"  — wipe Neo4j data + re-index"
	@echo "  make cgc-browser / cgc-password / cgc-tx / cgc-kill-all"
	@echo "  make cgc-kill id=neo4j-transaction-N"
	@echo "  make cgc-uninstall — remove stack (prompts)"

cgc-bootstrap:
	@bash "$(MAKEFILE_DIR)scripts/bootstrap.sh" $(ARGS)

cgc-copy-rule:
	@test -n "$(REPO)" || (echo 'usage: make cgc-copy-rule REPO=/path/to/git/repo'; exit 1)
	@mkdir -p "$(REPO)/.cursor/rules"
	@cp -f "$(MAKEFILE_DIR)templates/cgc-routing.mdc" "$(REPO)/.cursor/rules/cgc-routing.mdc"
	@echo "installed $(REPO)/.cursor/rules/cgc-routing.mdc (reload Cursor / reopen project to refresh Rules list)"

cgc-doctor:
	@bash "$(MAKEFILE_DIR)scripts/doctor.sh"

cgc-up:
	@test -f "$(CGC_NEO4J_DIR)/docker-compose.yml" || (echo "run: make cgc-bootstrap"; exit 1)
	@$(CGC_COMPOSE) up -d
	@printf 'Waiting for Neo4j'; \
	for i in $$(seq 1 45); do \
	  if docker exec cgc-neo4j cypher-shell -u neo4j -p "$$(cat $(CGC_NEO4J_DIR)/.password)" 'RETURN 1' >/dev/null 2>&1; then \
	    echo ' — ready'; exit 0; \
	  fi; printf '.'; sleep 2; \
	done; echo ' — TIMEOUT (make cgc-logs)'; exit 1

cgc-down:
	@$(CGC_COMPOSE) down

cgc-status:
	@docker ps --filter name=cgc-neo4j --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || true
	@echo ""
	@$(CGC_BIN) list 2>/dev/null | tail -10 || echo "(codegraphcontext list failed — Neo4j up? PATH has pipx apps?)"

cgc-logs:
	@docker logs -f cgc-neo4j

cgc-index: cgc-up
	@test -n "$(PATHS)" || (echo 'usage: make cgc-index PATHS="/path/to/repo1 /path/to/repo2"'; exit 1)
	@test -n "$(CGC_BIN)" || (echo 'codegraphcontext not on PATH (pipx ensurepath?)'; exit 1)
	@for p in $(PATHS); do \
	  echo "indexing $$p"; \
	  "$(CGC_BIN)" index --force "$$p" || exit 1; \
	done

cgc-reset:
	@test -n "$(PATHS)" || (echo 'usage: make cgc-reset PATHS="/path1 /path2"'; exit 1)
	@echo "Wiping Neo4j volumes…"
	@$(CGC_COMPOSE) down -v
	@$(MAKE) cgc-index PATHS="$(PATHS)"

cgc-browser:
	@command -v open >/dev/null 2>&1 && open http://localhost:7474 || \
	 (command -v xdg-open >/dev/null 2>&1 && xdg-open http://localhost:7474) || \
	 echo "Open http://localhost:7474"

cgc-password:
	@cat $(CGC_NEO4J_DIR)/.password; echo

cgc-tx:
	@docker exec cgc-neo4j cypher-shell -u neo4j -p "$$(cat $(CGC_NEO4J_DIR)/.password)" \
	  'SHOW TRANSACTIONS YIELD transactionId, status, elapsedTime, currentQuery \
	   RETURN transactionId, status, toString(elapsedTime) AS elapsed, left(currentQuery, 200) AS q \
	   ORDER BY elapsedTime DESC LIMIT 10'

cgc-kill:
	@if [ -z "$(id)" ]; then echo "usage: make cgc-kill id=neo4j-transaction-NNN"; exit 1; fi
	@docker exec cgc-neo4j cypher-shell -u neo4j -p "$$(cat $(CGC_NEO4J_DIR)/.password)" \
	  'TERMINATE TRANSACTIONS "$(id)"'

cgc-kill-all:
	@PW="$$(cat $(CGC_NEO4J_DIR)/.password)"; \
	ids=$$(docker exec cgc-neo4j cypher-shell -u neo4j -p "$$PW" --format plain \
	  'SHOW TRANSACTIONS YIELD transactionId, currentQuery WHERE NOT currentQuery STARTS WITH "SHOW TRANSACTIONS" RETURN transactionId' \
	  | tail -n +2 | tr -d '"'); \
	if [ -z "$$ids" ]; then echo "no non-system transactions"; exit 0; fi; \
	for id in $$ids; do \
	  echo "terminating $$id"; \
	  docker exec cgc-neo4j cypher-shell -u neo4j -p "$$PW" "TERMINATE TRANSACTIONS \"$$id\""; \
	done

cgc-uninstall:
	@echo "Removes: Neo4j cgc volumes, ~/.codegraphcontext, pipx codegraphcontext."
	@echo "Does NOT remove ~/.cursor/mcp.json or rules (edit manually if needed)."
	@read -p "Type YES to continue: " _cgc_u; test "$$_cgc_u" = "YES"
	@$(CGC_COMPOSE) down -v 2>/dev/null || true
	-pipx uninstall codegraphcontext
	@rm -rf "$(HOME)/.codegraphcontext"
	@echo "Uninstall done."
