# shellcheck shell=bash
# Tests for `ccprofile doctor`.

_setup() {
  TEST_HOME=$(mktemp -d)
  export CCPROFILE_HOME_OVERRIDE="$TEST_HOME"
  mkdir -p "$TEST_HOME/.claude"/{skills,plugins,commands}
  touch "$TEST_HOME/.claude"/{CLAUDE.md,settings.json}
  # .claude.json lives at $HOME/.claude.json (sibling of .claude/), not inside
  cat > "$TEST_HOME/.claude.json" <<'JSON'
{"oauthAccount":{"emailAddress":"a@test.com"}}
JSON
  "$CCPROFILE_BIN" init b > /dev/null
}

_teardown() {
  [[ -n "${TEST_HOME:-}" ]] && rm -rf "$TEST_HOME"
}

test_doctor_healthy_profile() {
  _setup
  if ! "$CCPROFILE_BIN" doctor b > /tmp/doctor.log 2>&1; then
    cat /tmp/doctor.log
    echo "doctor should report healthy"
    _teardown; return 1
  fi
  _teardown
}

test_doctor_detects_symlinked_claude_json() {
  _setup
  # Corrupt the profile by symlinking .claude.json to main's
  ln -sf "$TEST_HOME/.claude.json" "$TEST_HOME/.claude-b/.claude.json"
  if "$CCPROFILE_BIN" doctor b > /tmp/doctor.log 2>&1; then
    cat /tmp/doctor.log
    echo "doctor should fail when .claude.json is a symlink"
    _teardown; return 1
  fi
  grep -q ".claude.json is a symlink" /tmp/doctor.log || {
    cat /tmp/doctor.log
    echo "doctor should mention .claude.json symlink"
    _teardown; return 1
  }
  _teardown
}

test_doctor_detects_symlinked_statsig() {
  _setup
  mkdir "$TEST_HOME/.claude/statsig"
  ln -sf "$TEST_HOME/.claude/statsig" "$TEST_HOME/.claude-b/statsig"
  if "$CCPROFILE_BIN" doctor b > /tmp/doctor.log 2>&1; then
    cat /tmp/doctor.log
    echo "doctor should fail when statsig is symlinked"
    _teardown; return 1
  fi
  _teardown
}

test_doctor_warns_on_unknown_main_item() {
  _setup
  # Add an unknown top-level dir in main
  mkdir "$TEST_HOME/.claude/brand-new-feature-dir"
  "$CCPROFILE_BIN" doctor b > /tmp/doctor.log 2>&1 || true
  grep -q "brand-new-feature-dir" /tmp/doctor.log || {
    cat /tmp/doctor.log
    echo "doctor should mention unknown item"
    _teardown; return 1
  }
  _teardown
}
