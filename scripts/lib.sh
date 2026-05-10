#!/usr/bin/env bash
# Shared helpers for cursor-cgc scripts. Source from repo root context.

CURSOR_CGC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CURSOR_CGC_ROOT

cgc_sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}
