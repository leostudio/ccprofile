# ccprofile — Developer Context

Context for Claude Code agents working on this repo. Read this before editing.

## What this project is

A bash CLI (`ccprofile`) that manages multiple Claude Code config profiles via `CLAUDE_CONFIG_DIR` + symlinks. The core value proposition is a **precise classification** of which files under `~/.claude/` can be shared across subscriptions and which must stay isolated — derived from reading Claude Code source code, not guesswork.

**Audience**: users who have two Claude subscriptions and want to run both on the same Mac without `/logout && /login` churn.

**Non-goals**: Linux/Windows support, GUI, Homebrew packaging, credential swapping. See README "Design decisions" section.

## Architecture

```
bin/ccprofile          dispatcher (sources lib/ then dispatches to cmd_*)
lib/shared-lists.sh    SINGLE SOURCE OF TRUTH — 6 arrays classifying every known file
lib/utils.sh           color output, path resolution, json_get, ensure_symlink
lib/commands/*.sh      one file per subcommand, each defines cmd_<name>()
tests/run-tests.sh     simple bash test runner (discovers test_*.sh)
tests/test_*.sh        tests use CCPROFILE_HOME_OVERRIDE + mktemp sandboxes
```

**Sourcing order** in `bin/ccprofile`: `utils.sh` → `shared-lists.sh` → `commands/*.sh`. Do not reorder.

## The classification is the product

`lib/shared-lists.sh` is the heart of the project. Seven arrays:

| Array | Meaning |
|---|---|
| `SHARED_TOOLCHAIN` | Always share (skills, plugins, commands, CLAUDE.md, settings.json, …) |
| `SHARED_CACHES` | Generic caches with no account state |
| `SHARED_PERSONAL` | Default share, opt-out via `--no-share-*` flags |
| `ISOLATED_IDENTITY` | Account identity (`.claude.json`, `.credentials.json`, `config.json`) |
| `ISOLATED_AUTH_ADJACENT` | Per-account caches (statsig, usage-data, stats-cache, …) |
| `ISOLATED_CONCURRENT` | Runtime state (sessions, tasks, debug, log) |
| `IGNORED_EXTERNAL` | Not Claude Code at all (e.g. Claude Desktop's `downloads/`). Neither symlinked nor enforced — only listed so `doctor` stops warning. |

**When Claude Code adds a new top-level file/dir to `~/.claude/`:**
1. Read its source code to classify it into one of the 6 Claude-Code-managed buckets
2. Add to the corresponding array in `lib/shared-lists.sh`
3. `doctor` will automatically include it in health checks
4. `init` and `sync` will pick it up on next run
5. Update README's "File classification" section if it's noteworthy

**When you find an item Claude Code source does NOT reference:**
- Verify with `grep` against the local Claude Code checkout (see "Source code references" below)
- If genuinely not Claude Code's, add to `IGNORED_EXTERNAL` with a comment naming the suspected origin
- Do NOT speculatively classify it into a managed bucket — if you're wrong, you'll either leak account state (false-share) or break a real tool (false-isolate)

**`doctor`'s unknown-item detection** walks the main profile and reports any top-level entry not in any array, so failing to update `shared-lists.sh` won't silently break things — it'll show up as a warning.

## Conventions

### Output helpers (from `lib/utils.sh`)

Use these instead of raw `echo` / `printf`:
- `info "text"` — normal output to stdout
- `ok   "text"` — green ✓ prefix
- `warn "text"` — yellow ⚠ prefix, to stderr
- `err  "text"` — red ✗ prefix, to stderr
- `die  "text"` — `err` then `exit 1`
- `hint "text"` — dimmed text (tips)
- `bold "text"` — bold inline

Color auto-disables when stdout is not a TTY or `NO_COLOR=1` is set.

### Path helpers (always use these, never hardcode `$HOME`)

- `ccp_home` — respects `CCPROFILE_HOME_OVERRIDE` for tests
- `main_claude_dir` — `$(ccp_home)/.claude`
- `profile_dir <name>` — `$(ccp_home)/.claude-<name>`

### Profile name validation

Any command that takes a profile name must call `validate_profile_name "$name"`. It enforces `[a-zA-Z0-9_-]+` and rejects the reserved name `claude`.

### Login check

Use `is_logged_in "$dir"` (returns 0/1). Reads `oauthAccount.emailAddress` from the dir's `.claude.json` via `json_get`.

### Symlink creation

Use `ensure_symlink "$target" "$link"` — idempotent, returns 1 if a real file blocks. Do NOT call `ln -s` directly outside of this helper.

### JSON reading without jq

`json_get <file> <dotted.path>` uses inline `python3` (no jq dep). Returns empty string on any error. Extend carefully: it only handles simple `obj.key.key` paths, no arrays.

## Testing

### Running tests

```bash
./tests/run-tests.sh                              # all tests
./tests/run-tests.sh 2>&1 | grep '✗'              # just failures
```

### Writing new tests

- One file per command: `tests/test_<command>.sh`
- Each test is a function named `test_<what_it_checks>`
- Every test must set up its own sandbox and tear it down:
  ```bash
  _setup() {
    TEST_HOME=$(mktemp -d)
    export CCPROFILE_HOME_OVERRIDE="$TEST_HOME"
    # ... populate fake ~/.claude/ structure ...
  }
  _teardown() {
    [[ -n "${TEST_HOME:-}" ]] && rm -rf "$TEST_HOME"
  }
  ```
- **Critical**: tests must NEVER touch the real `~/.claude/` — rely exclusively on `CCPROFILE_HOME_OVERRIDE`.
- Use `"$CCPROFILE_BIN"` (exported by `run-tests.sh`) not a hardcoded path.
- Return 1 from the test function to indicate failure; 0 for success. Always `_teardown` before returning.

### Test runner quirks

- The runner sources each `test_*.sh` file then discovers functions starting with `test_`. It runs each in a subshell for state isolation.
- After each file, all `test_*` functions are unset so the next file starts fresh.
- Test stdout/stderr is captured to `/tmp/ccprofile-test.log` and printed only on failure.

## When adding a new subcommand

1. Create `lib/commands/<name>.sh` defining `cmd_<name>()`
2. Follow the existing pattern: parse flags with `while/case`, support `-h|--help`
3. Add `source "$LIB_DIR/commands/<name>.sh"` to `bin/ccprofile`
4. Add the dispatch case to `main()` in `bin/ccprofile`
5. Update `print_help` in `bin/ccprofile` and the Commands section of `README.md`
6. Add `tests/test_<name>.sh` with at least 3 tests (happy path + 2 error cases)

## Common pitfalls

- **Do not mutate `~/.claude/`**: every write must go under `profile_dir <name>` or be a symlink whose target is under `main_claude_dir`. The main profile is read-only from this tool's perspective.
- **Do not copy files**: we only create symlinks. Copying would silently drift out of sync with the main profile.
- **Do not touch Keychain**: OAuth token cleanup must be done via `claude /logout`. The tool prints a reminder in `rm` but never runs `security delete-generic-password`.
- **Do not modify shell configs**: `install.sh` and `init` both only *print* alias suggestions. The user adds them manually.
- **Do not assume `jq` exists**: use `json_get` (which uses `python3`).
- **macOS only for now**: `install.sh` and all logic assume macOS. Linux/Windows ports should live in separate branches, not conditionals mixed into the main code.

## Source code references (Claude Code internals)

These are cited in `shared-lists.sh` comments and `README.md`. If you update the classification, keep these references accurate:

| File | What it tells us |
|---|---|
| `src/utils/env.ts:14` | `getGlobalClaudeFile()` — `.claude.json` path, legacy `.config.json` fallback |
| `src/utils/envUtils.ts` | `getClaudeConfigHomeDir()` — `CLAUDE_CONFIG_DIR` resolution |
| `src/utils/secureStorage/macOsKeychainHelpers.ts:29` | Keychain service name hashes `CLAUDE_CONFIG_DIR` — the reason isolation works |
| `src/utils/secureStorage/plainTextStorage.ts:15` | `.credentials.json` path constant |
| `src/utils/secureStorage/index.ts:9` | Platform selection (Keychain vs plaintext) |
| `src/utils/secureStorage/fallbackStorage.ts` | Keychain → plaintext fallback logic |
| `src/utils/config.ts:797` | `saveGlobalConfig()` write semantics |
| `src/services/mcp/client.ts:262` | `mcp-needs-auth-cache.json` path |

## Version bumping

`CCPROFILE_VERSION` in `bin/ccprofile` is the single source of truth. Bump it when:
- Adding/removing items in `shared-lists.sh` → patch bump
- Adding new subcommand or flag → minor bump
- Breaking changes to alias format or command interface → major bump
