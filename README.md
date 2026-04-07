# ccprofile

Claude Code multi-subscription profile manager for macOS.

Run two (or more) Claude Code subscriptions side-by-side on the same Mac — sharing all your toolchain config (skills, plugins, commands, `CLAUDE.md`, projects, history) while keeping account identity and auth-adjacent caches strictly isolated.

**No logout/login juggling. No credential swapping. Run both subscriptions concurrently.**

## Why another switcher?

Several open-source tools already tackle this problem. They fall into two camps, both with gaps:

| Approach | Example | Gap |
|---|---|---|
| `CLAUDE_CONFIG_DIR` + symlinks | [ukogan/claude-account-switcher](https://github.com/ukogan/claude-account-switcher) | Only symlinks `settings` / `commands` / `MCP` / `hooks`. Misses `skills/`, `plugins/`, `projects/`, `history.jsonl`, and **completely ignores auth-adjacent caches** like `statsig/`, `usage-data/`, `stats-cache.json`, `settings-cache.json`, `policyLimits-cache.json`, `mcp-needs-auth-cache.json`. Leaving these shared causes subtle feature-flag leakage and usage-tracking confusion. |
| Credential file swap | [realiti4/claude-swap](https://github.com/realiti4/claude-swap), [ming86/cc-account-switcher](https://github.com/ming86/cc-account-switcher) | Can't run two accounts concurrently. Swap has a risk window. Mutable "active account" state. |

**ccprofile's contribution**: a file classification derived from reading Claude Code source code, not guesswork. Every shared/isolated decision points back to a specific file in the Claude Code repo as evidence.

## How it works

1. Your default profile stays at `~/.claude/` (subscription A).
2. `ccprofile init work` creates `~/.claude-work/` with symlinks back to `~/.claude/` for all shareable content.
3. You add a shell alias: `alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work command claude'`.
4. Run `claude-work` once to login with subscription B.
5. Both subscriptions now work independently — including concurrently in two terminals.

### Keychain isolation (automatic)

Claude Code's macOS Keychain code ([`src/utils/secureStorage/macOsKeychainHelpers.ts:29`](https://github.com/anthropics/claude-code) — `getMacOsKeychainStorageServiceName`) hashes `CLAUDE_CONFIG_DIR` into the keychain service name:

```typescript
const dirHash = isDefaultDir
  ? ''
  : `-${createHash('sha256').update(configDir).digest('hex').substring(0, 8)}`
return `Claude Code${...}${serviceSuffix}${dirHash}`
```

So `~/.claude/` and `~/.claude-work/` automatically get different keychain entries — OAuth tokens are isolated without any extra work.

## Install

```bash
git clone https://github.com/leostudio/ccprofile.git
cd ccprofile
./install.sh
```

This symlinks `bin/ccprofile` into `~/.local/bin/`. No shell config changes, no package manager.

### Updating

```bash
cd <path-to>/ccprofile
git pull
```

No need to re-run `./install.sh`: `~/.local/bin/ccprofile` is a symlink into the repo, so `git pull` takes effect immediately.

## Usage

```bash
# First, make sure you're logged into subscription A in the default profile:
claude                    # login if needed

# Create a second profile:
ccprofile init work

# Add the suggested alias to ~/.zshrc, reload, then:
claude-work               # triggers login flow for subscription B

# Both work now — switch freely:
claude          # subscription A
claude-work     # subscription B
```

> **Note**: if your `claude` is wrapped by a shell function (e.g. to inject a proxy, mTLS certs, or custom env vars), the suggested `alias claude-work='... command claude'` **will not inherit that wrapper** — `command` skips functions and runs the binary directly. See [Troubleshooting](#troubleshooting) for how to use a function instead.

### Commands

```
ccprofile init <name> [flags]   Create a new profile
  --no-share-projects             Keep projects/ independent
  --no-share-history              Keep history.jsonl independent
  --no-share-file-history         Keep file-history/ independent
  --dry-run                       Print actions without changes

ccprofile list                  List all profiles (name, email, status)
ccprofile sync <name>           Re-sync symlinks (after installing new skills in main)
ccprofile doctor <name>         Verify profile health
ccprofile shared-list           Show full classification with source evidence
ccprofile rm <name>             Delete a profile (keychain tokens must be cleared manually)
```

## File classification

Run `ccprofile shared-list` for the live version. Here's the summary:

### ✓ Shared (symlinked)

**Toolchain config** — the primary reason to run multiple profiles:
- `settings.json`, `CLAUDE.md`, `commands/`, `skills/`, `plugins/`, `statusline-command.sh`, `.gitignore`

**Generic caches** — no per-account state:
- `cache/`, `chrome/`, `ide/`

**Personal work content** — default shared, opt-out via `--no-share-*`:
- `projects/`, `history.jsonl`, `file-history/`, `paste-cache/`, `plans/`, `todos/`, `shell-snapshots/`, `session-env/`, `backups/`

### ✗ Isolated (independent real files)

**Account identity** — never symlink:

| File | Source evidence |
|---|---|
| `.claude.json` | `src/utils/env.ts:14` `getGlobalClaudeFile()` |
| `.credentials.json` | `src/utils/secureStorage/plainTextStorage.ts:15` |
| `config.json` | legacy fallback in `getGlobalClaudeFile()` |

**Auth-adjacent caches** — *the key finding other tools miss*:

| File | Why it must be isolated |
|---|---|
| `stats-cache.json` | per-account usage cache |
| `statsig/` | feature-flag bucketing by accountID |
| `usage-data/` | local usage tracking |
| `settings-cache.json` | `remoteManagedSettings` cache (per org) |
| `policyLimits-cache.json` | policy limits (per subscription) |
| `mcp-needs-auth-cache.json` | `src/services/mcp/client.ts:262` |

**Concurrent-run state** — avoid lock/PID collisions when both profiles run simultaneously:
- `sessions/`, `tasks/`, `debug/`, `log/`

## Verifying isolation

After `init work` and login:

```bash
# Verify keychain has two distinct entries:
security dump-keychain login.keychain 2>/dev/null | grep "Claude Code-credentials"
# Expected:
#   "Claude Code-credentials"                  (subscription A)
#   "Claude Code-credentials-<8hex>"           (subscription B)

# Verify different accounts:
claude auth status
CLAUDE_CONFIG_DIR=~/.claude-work claude auth status
# Should show different emails / orgs

# Verify health:
ccprofile doctor work
```

## Troubleshooting

### OAuth login hangs or times out (15s) on a new profile

Symptoms: browser authorization succeeds, but back in the terminal you see
`OAuth error: timeout of 15000ms exceeded`. The default profile works fine.

Root cause: your `claude` is a shell **function** (not the raw binary), typically
used to inject proxy / mTLS / custom env vars. ccprofile's suggested alias ends
in `command claude`, which intentionally skips functions and aliases — this
avoids NVM path issues, but also bypasses your wrapper. The new profile has
no cached token, so it hits the Claude token endpoint directly, without your
proxy, and times out.

Check if you're in this situation:

```bash
declare -f claude          # if this prints a function body, you are
```

Fix: define the new profile as a function too, reusing the same env injection:

```zsh
# ~/.zshrc — suppose your existing wrapper looks like this:
_claude_proxy_env=(
  HTTPS_PROXY=http://127.0.0.1:7897
  HTTP_PROXY=http://127.0.0.1:7897
  # ...
)
claude()      { env "${_claude_proxy_env[@]}" command claude "$@" }

# Then define each profile the same way, just add CLAUDE_CONFIG_DIR:
claude-work() { env "${_claude_proxy_env[@]}" CLAUDE_CONFIG_DIR="$HOME/.claude-work" command claude "$@" }
```

The key is: `command claude` at the end (not recursive), but wrapped in your
function so the env vars still get injected.

## Design decisions

- **Bash, not Python/Rust**: pure filesystem operations, zero runtime deps, ~500 lines total, auditable in one sitting.
- **No wrapper command**: just a shell alias. The `command claude` form in the alias avoids the NVM-upgrade trap (hardcoded paths break when `node` version changes).
- **No "active profile" state**: switching is just picking the alias. Zero mutable state means nothing can go out of sync.
- **Classification is code, not comments**: `lib/shared-lists.sh` is the single source of truth. `doctor` reads from it, `init` reads from it, `sync` reads from it.

## Testing

```bash
./tests/run-tests.sh
```

Tests run in `mktemp -d` sandboxes via `CCPROFILE_HOME_OVERRIDE` — they never touch your real `~/.claude/`.

## License

MIT
