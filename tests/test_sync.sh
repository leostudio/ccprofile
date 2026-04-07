# shellcheck shell=bash
# Tests for `ccprofile sync`.

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

test_sync_picks_up_newly_added_dir() {
  _setup
  # Simulate user installing a new top-level item in main profile
  mkdir "$TEST_HOME/.claude/statusline-command.sh-dir-just-to-test"
  touch "$TEST_HOME/.claude/statusline-command.sh"
  "$CCPROFILE_BIN" sync b > /dev/null
  [[ -L "$TEST_HOME/.claude-b/statusline-command.sh" ]] || {
    echo "statusline-command.sh should now be symlinked"
    _teardown; return 1
  }
  _teardown
}

test_sync_removes_dangling_symlinks() {
  _setup
  # Remove source dir, leaving dangling symlink
  rm -rf "$TEST_HOME/.claude/skills"
  "$CCPROFILE_BIN" sync b > /dev/null
  if [[ -L "$TEST_HOME/.claude-b/skills" ]]; then
    echo "dangling skills symlink should be removed"
    _teardown; return 1
  fi
  _teardown
}

test_sync_aborts_on_real_file_collision() {
  _setup
  # Replace symlink with a real file
  rm "$TEST_HOME/.claude-b/settings.json"
  echo '{"local":"version"}' > "$TEST_HOME/.claude-b/settings.json"
  if "$CCPROFILE_BIN" sync b > /dev/null 2>&1; then
    echo "sync should abort on real-file collision"
    _teardown; return 1
  fi
  # Real file should remain untouched
  grep -q "local" "$TEST_HOME/.claude-b/settings.json" || {
    echo "real file was clobbered"
    _teardown; return 1
  }
  _teardown
}

test_sync_idempotent() {
  _setup
  "$CCPROFILE_BIN" sync b > /dev/null
  "$CCPROFILE_BIN" sync b > /dev/null
  [[ -L "$TEST_HOME/.claude-b/skills" ]] || { echo "skills missing"; _teardown; return 1; }
  _teardown
}
