# shellcheck shell=bash
# Tests for `ccprofile init`.

_setup() {
  TEST_HOME=$(mktemp -d)
  export CCPROFILE_HOME_OVERRIDE="$TEST_HOME"
  mkdir -p "$TEST_HOME/.claude"/{skills,plugins,commands,projects}
  touch "$TEST_HOME/.claude"/{CLAUDE.md,settings.json,history.jsonl}
  # .claude.json lives at $HOME/.claude.json (sibling of .claude/), not inside
  cat > "$TEST_HOME/.claude.json" <<'JSON'
{"oauthAccount":{"emailAddress":"a@test.com","subscriptionType":"pro"}}
JSON
}

_teardown() {
  [[ -n "${TEST_HOME:-}" ]] && rm -rf "$TEST_HOME"
}

_run() {
  "$CCPROFILE_BIN" "$@"
}

test_init_creates_symlinks_for_toolchain() {
  _setup
  _run init b > /dev/null

  [[ -L "$TEST_HOME/.claude-b/skills" ]] || { echo "skills not symlinked"; _teardown; return 1; }
  [[ -L "$TEST_HOME/.claude-b/plugins" ]] || { echo "plugins not symlinked"; _teardown; return 1; }
  [[ -L "$TEST_HOME/.claude-b/commands" ]] || { echo "commands not symlinked"; _teardown; return 1; }
  [[ -L "$TEST_HOME/.claude-b/CLAUDE.md" ]] || { echo "CLAUDE.md not symlinked"; _teardown; return 1; }
  [[ -L "$TEST_HOME/.claude-b/settings.json" ]] || { echo "settings.json not symlinked"; _teardown; return 1; }
  _teardown
}

test_init_does_not_symlink_claude_json() {
  _setup
  _run init b > /dev/null
  # .claude.json must be independent (not a symlink, not copied from main)
  if [[ -e "$TEST_HOME/.claude-b/.claude.json" ]]; then
    echo ".claude.json should not exist in new profile"
    _teardown; return 1
  fi
  _teardown
}

test_init_shares_projects_by_default() {
  _setup
  _run init b > /dev/null
  [[ -L "$TEST_HOME/.claude-b/projects" ]] || { echo "projects should be symlinked by default"; _teardown; return 1; }
  _teardown
}

test_init_no_share_projects() {
  _setup
  _run init b --no-share-projects > /dev/null
  if [[ -e "$TEST_HOME/.claude-b/projects" ]]; then
    echo "projects should not be linked with --no-share-projects"
    _teardown; return 1
  fi
  _teardown
}

test_init_no_share_history() {
  _setup
  _run init b --no-share-history > /dev/null
  if [[ -e "$TEST_HOME/.claude-b/history.jsonl" ]]; then
    echo "history.jsonl should not be linked with --no-share-history"
    _teardown; return 1
  fi
  # But skills should still be linked
  [[ -L "$TEST_HOME/.claude-b/skills" ]] || { echo "skills should still be linked"; _teardown; return 1; }
  _teardown
}

test_init_rejects_existing_profile() {
  _setup
  _run init b > /dev/null
  if _run init b > /dev/null 2>&1; then
    echo "second init should have failed"
    _teardown; return 1
  fi
  _teardown
}

test_init_rejects_reserved_name() {
  _setup
  if _run init claude > /dev/null 2>&1; then
    echo "'claude' should be rejected"
    _teardown; return 1
  fi
  _teardown
}

test_init_rejects_when_main_not_logged_in() {
  _setup
  # Remove the oauthAccount to simulate not logged in
  echo '{}' > "$TEST_HOME/.claude.json"
  if _run init b > /dev/null 2>&1; then
    echo "init should fail when main not logged in"
    _teardown; return 1
  fi
  _teardown
}

test_init_rejects_when_main_missing() {
  _setup
  rm -rf "$TEST_HOME/.claude"
  if _run init b > /dev/null 2>&1; then
    echo "init should fail when main dir missing"
    _teardown; return 1
  fi
  _teardown
}

test_init_suggests_alias_when_no_wrapper() {
  _setup
  # No shell config files at all — should get the plain alias suggestion
  local output
  output=$(_run init b 2>&1)
  if ! printf '%s\n' "$output" | grep -q "alias claude-b="; then
    echo "expected alias suggestion, got:"
    printf '%s\n' "$output"
    _teardown; return 1
  fi
  if printf '%s\n' "$output" | grep -q "Detected: 'claude' is a shell function"; then
    echo "should not report wrapper detection when none exists"
    _teardown; return 1
  fi
  _teardown
}

test_init_detects_claude_function_wrapper_zshrc() {
  _setup
  cat > "$TEST_HOME/.zshrc" <<'ZSH'
_claude_proxy_env=(HTTPS_PROXY=http://127.0.0.1:7897)
claude() { env "${_claude_proxy_env[@]}" command claude "$@" }
ZSH
  local output
  output=$(_run init b 2>&1)
  if ! printf '%s\n' "$output" | grep -q "Detected: 'claude' is a shell function"; then
    echo "expected wrapper detection, got:"
    printf '%s\n' "$output"
    _teardown; return 1
  fi
  if ! printf '%s\n' "$output" | grep -q "claude-b() { env"; then
    echo "expected function-form suggestion, got:"
    printf '%s\n' "$output"
    _teardown; return 1
  fi
  if printf '%s\n' "$output" | grep -q "alias claude-b="; then
    echo "should not suggest alias when function wrapper detected"
    _teardown; return 1
  fi
  _teardown
}

test_init_detects_function_keyword_wrapper() {
  _setup
  cat > "$TEST_HOME/.bashrc" <<'BASH'
function claude { command claude "$@"; }
BASH
  local output
  output=$(_run init b 2>&1)
  if ! printf '%s\n' "$output" | grep -q "Detected: 'claude' is a shell function"; then
    echo "expected 'function claude {...}' to be detected, got:"
    printf '%s\n' "$output"
    _teardown; return 1
  fi
  _teardown
}

test_init_ignores_commented_claude_function() {
  _setup
  cat > "$TEST_HOME/.zshrc" <<'ZSH'
# claude() { command claude "$@" }
# function claude { :; }
ZSH
  local output
  output=$(_run init b 2>&1)
  if printf '%s\n' "$output" | grep -q "Detected: 'claude' is a shell function"; then
    echo "should not detect wrapper inside comments, got:"
    printf '%s\n' "$output"
    _teardown; return 1
  fi
  if ! printf '%s\n' "$output" | grep -q "alias claude-b="; then
    echo "expected alias suggestion fallback"
    _teardown; return 1
  fi
  _teardown
}

test_init_skips_missing_source_items() {
  _setup
  # Main dir has no plugins/ dir at all — plugins is declared in shared list
  rm -rf "$TEST_HOME/.claude/plugins"
  _run init b > /dev/null
  # plugins symlink should not be created (source doesn't exist)
  if [[ -e "$TEST_HOME/.claude-b/plugins" ]]; then
    echo "plugins should not be created when source missing"
    _teardown; return 1
  fi
  # skills should still be linked
  [[ -L "$TEST_HOME/.claude-b/skills" ]] || { echo "skills should still be linked"; _teardown; return 1; }
  _teardown
}

test_init_does_not_link_ignored_external_items() {
  _setup
  # `downloads` is in IGNORED_EXTERNAL — must not be symlinked even if present
  mkdir "$TEST_HOME/.claude/downloads"
  touch "$TEST_HOME/.claude/downloads/file.zip"
  _run init b > /dev/null
  if [[ -e "$TEST_HOME/.claude-b/downloads" ]]; then
    echo "IGNORED_EXTERNAL items must not be linked into the new profile"
    _teardown; return 1
  fi
  _teardown
}
