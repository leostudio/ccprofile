# shellcheck shell=bash
# Tests for `ccprofile clean-account`.

_setup_clean_default() {
  TEST_HOME=$(mktemp -d)
  export CCPROFILE_HOME_OVERRIDE="$TEST_HOME"
  mkdir -p "$TEST_HOME/.claude"/{projects,skills,telemetry,backups,ide,daemon}
  mkdir -p "$TEST_HOME/.claude"/{sessions,tasks,debug,log,jobs,worktrees,checkpoints,mailbox,routines,teams}
  touch "$TEST_HOME/.claude/history.jsonl" "$TEST_HOME/.claude/settings.json"
  echo '{"queued":"event"}' > "$TEST_HOME/.claude/telemetry/event.json"
  echo '{"hidden":"settings"}' > "$TEST_HOME/.claude/hsettings.json"
  echo '{"remote":"settings"}' > "$TEST_HOME/.claude/remote-settings.json"
  echo '{"policy":"limits"}' > "$TEST_HOME/.claude/policy-limits.json"
  echo '{"status":"old"}' > "$TEST_HOME/.claude/daemon-auth-status.json"
  echo 'cooldown' > "$TEST_HOME/.claude/daemon-auth-cooldown"
  echo 'lock' > "$TEST_HOME/.claude/daemon.lock"
  echo '{"status":"running"}' > "$TEST_HOME/.claude/daemon.status.json"
  echo 'daemon log' > "$TEST_HOME/.claude/daemon.log"
  echo '[{"prompt":"old"}]' > "$TEST_HOME/.claude/scheduled_tasks.json"
  echo '{"pid":123}' > "$TEST_HOME/.claude/scheduled_tasks.lock"
  echo '{"agents":[]}' > "$TEST_HOME/.claude/agent-registry.json"
  echo '{"state":"old"}' > "$TEST_HOME/.claude/assistant-daemon-state.json"
  echo 'seen' > "$TEST_HOME/.claude/first-run"
  echo '{"session":"old"}' > "$TEST_HOME/.claude/sessions/old.json"
  echo '{"task":"old"}' > "$TEST_HOME/.claude/tasks/old.json"
  echo 'job' > "$TEST_HOME/.claude/jobs/old"
  echo 'mail' > "$TEST_HOME/.claude/mailbox/message"
  echo 'checkpoint' > "$TEST_HOME/.claude/checkpoints/old"
  echo 'worktree' > "$TEST_HOME/.claude/worktrees/old"
  echo 'routine' > "$TEST_HOME/.claude/routines/state"
  echo 'team' > "$TEST_HOME/.claude/teams/old"
  mkdir -p "$TEST_HOME/Library/Application Support/Claude"
  mkdir -p "$TEST_HOME/Library/Caches/com.anthropic.claude"
  mkdir -p "$TEST_HOME/Library/Caches/Claude"
  mkdir -p "$TEST_HOME/Library/Saved Application State/com.anthropic.claude.savedState"
  mkdir -p "$TEST_HOME/Library/Preferences"
  mkdir -p "$TEST_HOME/Library/Logs/Claude"
  echo '{"desktop":"state"}' > "$TEST_HOME/Library/Application Support/Claude/state.json"
  echo 'desktop cache' > "$TEST_HOME/Library/Caches/com.anthropic.claude/cache"
  echo 'desktop cache' > "$TEST_HOME/Library/Caches/Claude/cache"
  echo 'saved state' > "$TEST_HOME/Library/Saved Application State/com.anthropic.claude.savedState/window"
  echo 'plist' > "$TEST_HOME/Library/Preferences/com.anthropic.claude.plist"
  echo 'desktop log' > "$TEST_HOME/Library/Logs/Claude/app.log"
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
  [[ ! -e "$TEST_HOME/.claude/hsettings.json" ]] || { echo "hsettings should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/remote-settings.json" ]] || { echo "remote settings cache should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/policy-limits.json" ]] || { echo "policy limits cache should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/daemon-auth-status.json" ]] || { echo "daemon auth status should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/sessions" ]] || { echo "sessions should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/tasks" ]] || { echo "tasks should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/jobs" ]] || { echo "jobs should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/daemon.log" ]] || { echo "daemon log should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/scheduled_tasks.json" ]] || { echo "scheduled tasks should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/worktrees" ]] || { echo "worktrees should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/checkpoints" ]] || { echo "checkpoints should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/mailbox" ]] || { echo "mailbox should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/agent-registry.json" ]] || { echo "agent registry should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/assistant-daemon-state.json" ]] || { echo "assistant daemon state should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/first-run" ]] || { echo "first-run should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/routines" ]] || { echo "routines should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/teams" ]] || { echo "teams should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/Library/Application Support/Claude" ]] || { echo "desktop app support should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/Library/Caches/com.anthropic.claude" ]] || { echo "desktop bundle cache should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/Library/Caches/Claude" ]] || { echo "desktop cache should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/Library/Saved Application State/com.anthropic.claude.savedState" ]] || { echo "desktop saved state should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/Library/Preferences/com.anthropic.claude.plist" ]] || { echo "desktop preferences should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/Library/Logs/Claude" ]] || { echo "desktop logs should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/daemon.lock" ]] || { echo "daemon lock should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/ide/vscode.lock" ]] || { echo "IDE lock should be moved"; _teardown_clean; return 1; }
  [[ ! -e "$TEST_HOME/.claude/backups/.claude.json.backup.20260101" ]] || { echo "config backup should be moved"; _teardown_clean; return 1; }
  [[ -d "$TEST_HOME/backup/claude/telemetry" ]] || { echo "telemetry backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/claude/hsettings.json" ]] || { echo "hsettings backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/claude/remote-settings.json" ]] || { echo "remote settings backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/claude/policy-limits.json" ]] || { echo "policy limits backup missing"; _teardown_clean; return 1; }
  [[ -d "$TEST_HOME/backup/claude/sessions" ]] || { echo "sessions backup missing"; _teardown_clean; return 1; }
  [[ -d "$TEST_HOME/backup/claude/tasks" ]] || { echo "tasks backup missing"; _teardown_clean; return 1; }
  [[ -d "$TEST_HOME/backup/claude/jobs" ]] || { echo "jobs backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/claude/daemon.log" ]] || { echo "daemon log backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/claude/scheduled_tasks.json" ]] || { echo "scheduled tasks backup missing"; _teardown_clean; return 1; }
  [[ -d "$TEST_HOME/backup/claude/worktrees" ]] || { echo "worktrees backup missing"; _teardown_clean; return 1; }
  [[ -d "$TEST_HOME/backup/claude/checkpoints" ]] || { echo "checkpoints backup missing"; _teardown_clean; return 1; }
  [[ -d "$TEST_HOME/backup/claude/mailbox" ]] || { echo "mailbox backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/claude/agent-registry.json" ]] || { echo "agent registry backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/claude/assistant-daemon-state.json" ]] || { echo "assistant daemon state backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/claude/first-run" ]] || { echo "first-run backup missing"; _teardown_clean; return 1; }
  [[ -d "$TEST_HOME/backup/claude/routines" ]] || { echo "routines backup missing"; _teardown_clean; return 1; }
  [[ -d "$TEST_HOME/backup/claude/teams" ]] || { echo "teams backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/desktop/Library/Application Support/Claude/state.json" ]] || { echo "desktop app support backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/desktop/Library/Caches/com.anthropic.claude/cache" ]] || { echo "desktop bundle cache backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/desktop/Library/Caches/Claude/cache" ]] || { echo "desktop cache backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/desktop/Library/Saved Application State/com.anthropic.claude.savedState/window" ]] || { echo "desktop saved state backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/desktop/Library/Preferences/com.anthropic.claude.plist" ]] || { echo "desktop preferences backup missing"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/backup/desktop/Library/Logs/Claude/app.log" ]] || { echo "desktop logs backup missing"; _teardown_clean; return 1; }
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
  [[ -f "$TEST_HOME/Library/Application Support/Claude/state.json" ]] || { echo "desktop app support should be restored"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/Library/Caches/com.anthropic.claude/cache" ]] || { echo "desktop bundle cache should be restored"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/Library/Caches/Claude/cache" ]] || { echo "desktop cache should be restored"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/Library/Saved Application State/com.anthropic.claude.savedState/window" ]] || { echo "desktop saved state should be restored"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/Library/Preferences/com.anthropic.claude.plist" ]] || { echo "desktop preferences should be restored"; _teardown_clean; return 1; }
  [[ -f "$TEST_HOME/Library/Logs/Claude/app.log" ]] || { echo "desktop logs should be restored"; _teardown_clean; return 1; }
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
