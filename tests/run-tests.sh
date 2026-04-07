#!/usr/bin/env bash
#
# Simple bash test runner for ccprofile.
# Discovers test_*.sh files, runs each in a subshell, reports results.
set -uo pipefail

SCRIPT_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd -P "$SCRIPT_DIR/.." && pwd)

export CCPROFILE_BIN="$PROJECT_DIR/bin/ccprofile"
export CCPROFILE_LIB_DIR="$PROJECT_DIR/lib"

passed=0
failed=0
failed_names=()

for test_file in "$SCRIPT_DIR"/test_*.sh; do
  [[ -f "$test_file" ]] || continue
  test_name=$(basename "$test_file" .sh)

  printf '▶ %s\n' "$test_name"

  # Run each test function in the file
  # shellcheck disable=SC1090
  source "$test_file"

  # Discover functions starting with "test_"
  for fn in $(declare -F | awk '{print $3}' | grep '^test_'); do
    # Run in subshell to isolate state
    if ( "$fn" ) >/tmp/ccprofile-test.log 2>&1; then
      printf '  ✓ %s\n' "$fn"
      passed=$((passed + 1))
    else
      printf '  ✗ %s\n' "$fn"
      sed 's/^/      /' /tmp/ccprofile-test.log
      failed=$((failed + 1))
      failed_names+=("$test_name::$fn")
    fi
  done

  # Clear the test_ functions so the next file starts fresh
  for fn in $(declare -F | awk '{print $3}' | grep '^test_'); do
    unset -f "$fn"
  done
done

printf '\n'
if [[ $failed -eq 0 ]]; then
  printf '✓ All %d tests passed\n' "$passed"
  exit 0
else
  printf '✗ %d passed, %d failed\n' "$passed" "$failed"
  printf 'Failed tests:\n'
  for name in "${failed_names[@]}"; do
    printf '  - %s\n' "$name"
  done
  exit 1
fi
