#!/usr/bin/env bash
#
# mayhem/test.sh — RUN rasn's own unit/integration tests and emit CTRF.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

echo "=== running cargo test -p rasn (lib + tests/ only; skip benches) ==="
log="$(mktemp)"
test_args=(--lib)
for f in tests/*.rs; do
  [ -f "$f" ] || continue
  test_args+=(--test "$(basename "$f" .rs)")
done
set +e
env -u RUSTFLAGS cargo test -p rasn "${test_args[@]}" -- --test-threads="$MAYHEM_JOBS" 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
set -e

passed="$( { grep -E '^test result: ok\. [0-9]+ passed' "$log" || true; } | awk '{s+=$4} END {print s+0}')"
failed="$( { grep -E '^test result: FAILED\.' "$log" || true; } | awk '{s+=$6} END {print s+0}')"
skipped="$( { grep -E '^test result:' "$log" || true; } | awk '{for(i=1;i<=NF;i++) if($i=="skipped") s+=$(i-1)} END {print s+0}')"
[ -z "$passed" ] && passed=0
[ -z "$failed" ] && failed=0
[ -z "$skipped" ] && skipped=0

if [ "$rc" -ne 0 ] && [ "$failed" = 0 ]; then
  failed=1
fi

emit_ctrf "cargo-test" "$passed" "$failed" "$skipped" || exit 1
