#!/usr/bin/env bash
#
# mayhem/build.sh — build rasn's cargo-fuzz target(s) as sanitized libFuzzer binaries.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# SANITIZER off-switch (SPEC): the Dockerfile threads $SANITIZER_FLAGS (default asan+ubsan,
# halting). rustc ignores clang flags, so we DERIVE the rustc sanitizer flag from it: if
# $SANITIZER_FLAGS mentions "address" we add -Zsanitizer=address; an EMPTY value (built with
# --build-arg SANITIZER_FLAGS=) yields a natural, un-instrumented crash build.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all}"
RUST_SAN=""
CFZ_SANITIZER="none"
case "$SANITIZER_FLAGS" in
  *address*) RUST_SAN="-Zsanitizer=address"; CFZ_SANITIZER="address" ;;
esac

: "${RUST_DEBUG_FLAGS:=-Cdebuginfo=2 -Zdwarf-version=3 -Cforce-frame-pointers -Clinker=/opt/mayhem-dwarf3-anchor/cc-wrapper.sh}"
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing ${RUST_SAN} ${RUST_DEBUG_FLAGS} -Cdebug-assertions=yes"
export CFLAGS="${CFLAGS:-} -gdwarf-3"
export CXXFLAGS="${CXXFLAGS:-} -gdwarf-3"

FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (ASan via RUSTFLAGS) ==="
echo "SANITIZER_FLAGS=$SANITIZER_FLAGS"
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions -s "$CFZ_SANITIZER" "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

echo "=== pre-building test suite (non-sanitized) ==="
test_args=(--lib)
for f in tests/*.rs; do
  [ -f "$f" ] || continue
  test_args+=(--test "$(basename "$f" .rs)")
done
env -u RUSTFLAGS cargo test --no-run -p rasn "${test_args[@]}" --quiet

echo "build.sh complete"
