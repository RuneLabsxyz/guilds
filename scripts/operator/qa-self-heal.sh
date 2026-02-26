#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
STATE_DIR="${ROOT_DIR}/.operator"
TASK_DIR="${STATE_DIR}/tasks"
mkdir -p "${TASK_DIR}"

VERIFY_CMD="${VERIFY_CMD:-bash -lc 'sozo test || scarb test'}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-5}"

run_verify() {
	local output_file
	output_file="$(mktemp)"

	set +e
	eval "${VERIFY_CMD}" >"${output_file}" 2>&1
	local status=$?
	set -e

	cat "${output_file}"

	if [[ ${status} -eq 0 ]]; then
		rm -f "${output_file}"
		return 0
	fi

	local digest
	digest="$(sha256sum "${output_file}" | awk '{print $1}')"
	local task_file="${TASK_DIR}/qa-fix-${digest}.md"

	if [[ ! -f "${task_file}" ]]; then
		{
			echo "# QA Fix Task"
			echo
			echo "- failure_hash: ${digest}"
			echo "- generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
			echo
			echo "## Failing Summary"
			grep -E "error|failed|panic|assert" "${output_file}" | head -n 40 || true
			echo
			echo "## Suggested Scope"
			echo "- inspect latest changed contract files"
			echo "- add/adjust regression tests"
			echo "- rerun verify"
		} >"${task_file}"
		echo "[qa-self-heal] created fix task: ${task_file}"
	else
		echo "[qa-self-heal] deduped existing task: ${task_file}"
	fi

	rm -f "${output_file}"
	return 1
}

for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
	echo "[qa-self-heal] verify attempt ${attempt}/${MAX_ATTEMPTS}"
	if run_verify; then
		echo "[qa-self-heal] verify is green"
		exit 0
	fi
done

echo "[qa-self-heal] exhausted retries without green verify"
exit 1
