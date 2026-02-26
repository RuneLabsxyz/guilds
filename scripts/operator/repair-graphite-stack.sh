#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
STATE_DIR="${ROOT_DIR}/.operator"
mkdir -p "${STATE_DIR}"

if ! command -v gt >/dev/null 2>&1; then
	echo "[repair-graphite-stack] Graphite CLI (gt) not found in PATH"
	exit 1
fi

echo "[repair-graphite-stack] syncing local metadata"
gt sync --restack || true

echo "[repair-graphite-stack] tracking untracked branches"
while IFS= read -r branch; do
	[[ -z "${branch}" ]] && continue
	echo "  - tracking ${branch}"
	gt track "${branch}" -f || true
done < <(gt ls -u 2>/dev/null | awk '{print $1}' || true)

echo "[repair-graphite-stack] iterative restack"
for i in 1 2 3; do
	echo "  - pass ${i}"
	if gt restack --upstack --no-interactive; then
		break
	fi
done

if gt restack --upstack --no-interactive; then
	echo "[repair-graphite-stack] stack is clean"
	exit 0
fi

echo "[repair-graphite-stack] restack still failing, attempting metadata fallback"
gt dev cache --clear || true
gt sync --restack || true

if gt restack --upstack --no-interactive; then
	echo "[repair-graphite-stack] recovered after metadata fallback"
	exit 0
fi

echo "[repair-graphite-stack] unresolved conflict remains"
echo "1) resolve conflicts manually"
echo "2) run: gt add -A && gt continue -a"
exit 2
