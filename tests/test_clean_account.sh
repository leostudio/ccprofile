# shellcheck shell=bash
# Tests for `ccprofile clean-account`.

_setup_clean_default() {
  TEST_HOME=$(mktemp -d)
  export CCPROFILE_HOME_OVERRIDE="$TEST_HOME"
  mkdir -p "$TEST_HOME/.claude"/{projects,skills,telemetry,backups,ide,daemon}
  touch "$TEST_HOME/.claude/history.jsonl" "$TEST_HOME/.claude/settings.json"
  echo '{"queued":"event"}' > "$TEST_HOME/.claude/telemetry/event.json"
  echo '{"remote":"settings"}' > "$TEST_HOME/.claude/remote-settings.json"
  echo '{"policy":"limits"}' > "$TEST_HOME/.claude/policy-limits.json"
  echo '{"status":"old"}' > "$TEST_HOME/.claude/daemon-auth-status.json"
  echo 'cooldown' > "$TEST_HOME/.claude/daemon-auth-cooldown"
  echo 'lock' > "$TEST_HOME/.claude/daemon.lock"
  echo '{"status":"running"}' > "$TEST_HOME/.claude/daemon.status.json"
  echo '{"version":"old"}' > "$TEST_HOME/.claude/.last-update-result.json"
  echo '{"authToken":"ide-token","ideName":"vscode"}' > "$TEST_HOME/.claude/ide/vscode.lock"
  echo '{"oauthAccount":{"emailAddress":"backup@example.com"},"projects":{"/repo":{"allowedTools":["Bash"]}}}' > "$TEST_HOME/.claude/backups/.claude.json.backup.20260101"
  cat > "$TEST_HOME/.claude.json" <<'JSON'
{
  "oauthAccount": {"emailAddress": "old@example.com"},
  "userID": "old-device-id",
  "hasAvailableSubscription": false,
  "cachedStatsigGates": {"gate": true},
  "firstStartTime": "2025-10-14T02:23:33.097Z",
  "numStartups": 42,
  "installMethod": "native",
  "projects": {
    "/repo": {
      "lastCost": 1.23,
      "lastSessionId": "old-session",
      "allowedTools": ["Bash"],
      "mcpServers": {"local": {"command": "echo"}}
    }
  },
  "skillUsage": {"x": {"usageCount": 1, "lastUsedAt": 1}},
  "toolUsage": {"y": {"calls": 1}},
  "lastPlanModeUse": 1710000000000
}
JSON
  cp "$TEST_HOME/.claude.json" "$TEST_HOME/.claude-custom-oauth.json"
  cp "$TEST_HOME/.claude.json" "$TEST_HOME/.claude/.claude-staging-oauth.json"
  cp "$TEST_HOME/.claude.json" "$TEST_HOME/.claude/.config.json"
}

_setup_clean_named() {
  TEST_HOME=$(mktemp -d)
  export CCPROFILE_HOME_OVERRIDE="$TEST_HOME"
  mkdir -p "$TEST_HOME/.claude-work/telemetry"
  echo '{"queued":"event"}' > "$TEST_HOME/.claude-work/telemetry/event.json"
  cat > "$TEST_HOME/.claude-work/.claude.json" <<'JSON'
{
  "oauthAccount": {"emailAddress": "work@example.com"},
  "userID": "work-device-id",
  "hasAvailableSubscription": true,
  "numStartups": 7,
  "projects": {"/repo": {"lastCost": 1.23, "allowedTools": ["Bash"]}}
}
JSON
  cp "$TEST_HOME/.claude-work/.claude.json" "$TEST_HOME/.claude-work/.claude-local-oauth.json"
}

_teardown_clean() {
  [[ -n "${TEST_HOME:-}" ]] && rm -rf "$TEST_HOME"
}

test_clean_account_dry_run_does_not_modify_default() {
  _setup_clean_default
  local output
  output=$("$CCPROFILE_BIN" clean-account 2>&1)
  printf '%s\n' "$output" | grep -q "Dry run only" || {
    printf '%s\n' "$output"
    echo "dry run should be explicit"
    _teardown_clean; return 1
  }
  printf '%s\n' "$output" | grep -q "Would delete Keychain item" || {
    printf '%s\n' "$output"
    echo "dry run should mention default keychain cleanup"
    _teardown_clean; return 1
  }
  grep -q '"userID"' "$TEST_HOME/.claude.json" || {
    echo "dry run should not modify .claude.json"
    _teardown_clean; return 1
  }
  [[ -d "$TEST_HOME/.claude/telemetry" ]] || {
    echo "dry run should not move telemetry"
    _teardown_clean; return 1
  }
  _teardown_clean
}

test_clean_account_help_mentions_no_keychain() {
  local output
  output=$("$CCPROFILE_BIN" clean-account --help 2>&1)
  printf '%s\n' "$output" | grep -q -- "--no-keychain" || {
    printf '%s\n' "$output"
    echo "help should document --no-keychain"
    return 1
  }
}

test_clean_account_apply_preserves_personal_content_default() {
  _setup_clean_default
  "$CCPROFILE_BIN" clean-account --apply --force --no-keychain --backup-dir "$TEST_HOME/backup" > /tmp/clean-account.log

  if grep -q '"userID"' "$TEST_HOME/.claude.json"; then
    cat /tmp/clean-account.log
    echo "userID should be removed"
    _teardown_clean; return 1
  fi
  if grep -q '"oauthAccount"' "$TEST_HOME/.claude.json"; then
    echo "oauthAccount should be removed"
    _teardown_clean; return 1
  fi
  grep -q '"numStartups": 0' "$TEST_HOME/.claude.json" || {
    echo "numStartups should be reset"
    _teardown_clean; return 1
  }
  grep -q '"projects"' "$TEST_HOME/.claude.json" || {
    echo "projects should be preserved in .claude.json"
    _teardown_clean; return 1
  }
  if grep -q '"lastCost"' "$TEST_HOME/.claude.json"; then
    echo "project lastCost should be removed from .claude.json"
    _teardown_clean; return 1
  fi
  if grep -q '"lastSessionId"' "$TEST_HOME/.claude.json"; then
    echo "project lastSessionId should be removed from .claude.json"
    _teardown_clean; return 1
  fi
  grep -q '"allowedTools"' "$TEST_HOME/.claude.json" || {
    echo "project allowedTools should be preserved in .claude.json"
    _teardown_clean; return 1
  }
  grep -q '"skillUsage"' "$TEST_HOME/.claude.json" && {
    echo "skillUsage should be removed from .claude.json"
    _teardown_clean; return 1
  }
  grep -q '"toolUsage"' "$TEST_HOME/.claude.json" && {
    echo "toolUsage should be removed from .claude.json"
    _teardown_clean; return 1
  }
  grep -q '"lastPlanModeUse"' "$TEST_HOME/.claude.json" && {
    echo "lastPlanModeUse should be removed from .claude.json"
    _teardown_clean; return 1
  }
  if grep -q '"userID"' "$TEST_HOME/.claude-custom-oauth.json"; then
    echo "custom OAuth config should be cleaned"
    _teardown_clean; return 1
  fi
  if grep -q '"userID"' "$TEST_HOME/.claude/.claude-staging-oauth.json"; then
    echo "config-dir OAuth config should be cleaned"
    _teardown_clean; return 1
  fi
  if grep -q '"userID"' "$TEST_HOME/.claude/.config.json"; then
    echo "legacy .config.json should be cleaned"
    _teardown_clean; return 1
  fi
  [[ -d "$TEST_HOME/.claude/projects" ]] || { echo "projects dir should remain"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/.claude/history.jsonl" ]] || { echo "history should remain"; _teardown_clean; return 1; }
  [[ -d "$TEST_HOME/.claude/skills" ]] || { echo "skills should remain"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/telemetry" ]] || { echo "telemetry should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/remote-settings.json" ]] || { echo "remote settings cache should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/policy-limits.json" ]] || { echo "policy limits cache should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/daemon-auth-status.json" ]] || { echo "daemon auth status should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/daemon.lock" ]] || { echo "daemon lock should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/ide/vscode.lock" ]] || { echo "IDE lock should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/backups/.claude.json.backup.20260101" ]] || { echo "config backup should be moved"; _teardown_clean; return 1; }
  [[ -d "$TEST_HOME/backup/claude/telemetry" ]] || { echo "telemetry backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/claude/remote-settings.json" ]] || { echo "remote settings backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/claude/policy-limits.json" ]] || { echo "policy limits backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/claude/ide/vscode.lock" ]] || { echo "IDE lock backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/claude/backups/.claude.json.backup.20260101" ]] || { echo "config backup quarantine missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/json-originals/home-.claude.json" ]] || { echo "json backup missing"; _teardown_clean; return 1; }
  _teardown_clean
}

test_restore_account_apply_default() {
  _setup_clean_default
  "$CCPROFILE_BIN" clean-account --apply --force --no-keychain --backup-dir "$TEST_HOME/backup" > /tmp/clean-account.log

  "$CCPROFILE_BIN" restore-account --apply --force --backup-dir "$TEST_HOME/backup" > /tmp/restore-account.log

  grep -q '"userID"' "$TEST_HOME/.claude.json" || {
    cat /tmp/restore-account.log
    echo "userID should be restored"
    _teardown_clean; return 1
  }
  grep -q '"lastCost"' "$TEST_HOME/.claude.json" || {
    echo "project metrics should be restored"
    _teardown_clean; return 1
  }
  grep -q '"skillUsage"' "$TEST_HOME/.claude.json" || {
    echo "skillUsage should be restored"
    _teardown_clean; return 1
  }
  grep -q '"toolUsage"' "$TEST_HOME/.claude.json" || {
    echo "toolUsage should be restored"
    _teardown_clean; return 1
  }
  grep -q '"lastPlanModeUse"' "$TEST_HOME/.claude.json" || {
    echo "lastPlanModeUse should be restored"
    _teardown_clean; return 1
  }
  [[ -d "$TEST_HOME/.claude/telemetry" ]] || { echo "telemetry should be restored"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/.claude/remote-settings.json" ]] || { echo "remote settings should be restored"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/.claude/policy-limits.json" ]] || { echo "policy limits should be restored"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/.claude/daemon-auth-status.json" ]] || { echo "daemon auth status should be restored"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/.claude/ide/vscode.lock" ]] || { echo "IDE lock should be restored"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/.claude/backups/.claude.json.backup.20260101" ]] || { echo "config backup should be restored"; _teardown_clean; return 1; }
  find "$TEST_HOME/backup" -maxdepth 1 -type d -name 'restore-overwritten-*' | grep -q . || {
    echo "overwritten backup dir should be created"
    _teardown_clean; return 1
  }
  _teardown_clean
}

test_clean_account_apply_named_profile() {
  _setup_clean_named
  "$CCPROFILE_BIN" clean-account work --apply --force --no-keychain --backup-dir "$TEST_HOME/backup" > /tmp/clean-account.log

  if grep -q '"userID"' "$TEST_HOME/.claude-work/.claude.json"; then
    cat /tmp/clean-account.log
    echo "named profile userID should be removed"
    _teardown_clean; return 1
  fi
  grep -q '"projects"' "$TEST_HOME/.claude-work/.claude.json" || {
    echo "named profile projects should be preserved"
    _teardown_clean; return 1
  }
  if grep -q '"lastCost"' "$TEST_HOME/.claude-work/.claude.json"; then
    echo "named profile project metrics should be removed"
    _teardown_clean; return 1
  fi
  grep -q '"allowedTools"' "$TEST_HOME/.claude-work/.claude.json" || {
    echo "named profile project settings should be preserved"
    _teardown_clean; return 1
  }
  if grep -q '"userID"' "$TEST_HOME/.claude-work/.claude-local-oauth.json"; then
    echo "named OAuth suffix config should be cleaned"
    _teardown_clean; return 1
  fi
  [[ ! -e "$TEST_HOME/.claude-work/telemetry" ]] || {
    echo "named profile telemetry should be moved"
    _teardown_clean; return 1
  }
  [[ -d "$TEST_HOME/backup/claude/telemetry" ]] || {
    echo "named telemetry backup missing"
    _teardown_clean; return 1
  }
  [[ -f "$TEST_HOME/backup/json-originals/profile-.claude.json" ]] || {
    echo "named json backup missing"
    _teardown_clean; return 1
  }
  _teardown_clean
}
