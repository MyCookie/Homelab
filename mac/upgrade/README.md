# mac/upgrade

A small, extensible bash script for updating and upgrading the services
that run on this Mac (Homebrew packages, the Lima VM, `container`-based
workloads, and the Homebrew-installed binaries kept alive by LaunchAgents).

Targets macOS's stock `/bin/bash` (3.2) — no associative arrays, no
`local -n`, no `mapfile`, no GNU long-option `getopt`.

## Usage

```
mac/upgrade/update.sh [OPTIONS]
```

Run with no options to put every registered service through its full
lifecycle. Run `mac/upgrade/update.sh --help` for the authoritative usage
text; the summary below covers the same ground.

| Flag | Effect |
| --- | --- |
| `-l`, `--list-services` | List registered services and exit. |
| `-s SERVICE`, `--service=SERVICE` | Only run the named service. |
| `--dry-run` | Print what would run, including hooks, without changing anything. |
| `--no-restart` | Skip `post_upgrade` (restart) hooks only. |
| `--skip-hooks` | Skip both `pre_upgrade` and `post_upgrade` hooks. |
| `-v`, `--verbose` | Also stream each command's real output to the console. |
| `-h`, `--help` | Show usage and examples. |

Examples:

```sh
mac/upgrade/update.sh                                # run everything
mac/upgrade/update.sh -l                             # list services
mac/upgrade/update.sh -s brew --dry-run              # preview brew only
mac/upgrade/update.sh --service=llama-server --no-restart
mac/upgrade/update.sh --dry-run --skip-hooks
mac/upgrade/update.sh -v                             # stream full output
```

Scoping to one service with `--service` only runs that service's own
lifecycle. For example, `--service=brew` upgrades Homebrew formulae but
won't restart any LaunchAgent-backed binary it touches — that's each
LaunchAgent service's own job (see `llama-server`, `whisper-server`,
`mcp-proxy` below). Omit `--service` to get the full, correct set.

## Lifecycle

Every run goes through three batched phases, in this order, across
whichever services are in scope:

1. **`pre_upgrade`** — shutdown hooks (skipped by `--skip-hooks`)
2. **`upgrade`** — the actual update/upgrade action (always runs)
3. **`post_upgrade`** — restart hooks (skipped by `--skip-hooks` or `--no-restart`)

Phases are batched (all services' `pre_upgrade` hooks, then all
`upgrade` steps, then all `post_upgrade` hooks) rather than run
service-by-service, so one service's restart can safely depend on another
having already come back up (e.g. the `openwebui` containers depend on
the `hermes` Lima VM being started first — alphabetical service-file
ordering already puts `hermes` ahead of `openwebui` in both directions).

A failing hook or upgrade step is logged and recorded, but doesn't abort
the rest of the run — by design, so a single bad restart doesn't prevent
other services from finishing. The script exits non-zero if anything
failed, with a summary of what.

## Adding a new service

Drop a new file into `lib/services/`; it's auto-discovered (sourced in
glob/alphabetical order) on every run — no registration elsewhere needed.

Each service file defines a namespaced set of `<name>::*` functions
(hyphens and `::` are both valid in bash function names) and registers
itself once at the bottom:

```bash
# lib/services/example.sh
example::description() { echo "One-line summary for --list-services"; }
example::upgrade()     { run some-upgrade-command; }

# Optional:
example::pre_upgrade()  { run some-shutdown-command; }
example::post_upgrade() { run some-restart-command; }

register_service "example"
```

Required:
- `<name>::description` — one-liner shown by `--list-services`
- `<name>::upgrade` — the upgrade action itself

Optional (the dispatcher checks whether the function exists before
calling it, so only define what the service actually needs):
- `<name>::pre_upgrade` — shutdown hook
- `<name>::post_upgrade` — restart hook

Always route side-effecting commands through the shared `run` helper
(from `lib/core.sh`) instead of calling them directly — it's the single
chokepoint for `--dry-run`, `--verbose`, and logging, so service authors
never need to branch on those flags themselves:

```bash
run brew upgrade some-formula
```

If a hook needs to remember something between its `pre_upgrade` and
`post_upgrade` calls (e.g. "was this actually running before I touched
it?"), use a plain module-scope variable — the whole run is one shell
process, so a variable set in `pre_upgrade` is still readable later in
`post_upgrade`. See `lib/services/llama-server.sh` for the pattern.

## Currently registered services

| Service | What it does |
| --- | --- |
| `brew` | `brew update && brew upgrade`. No hooks. |
| `hermes` | Stops/starts the Lima VM around container work; no package of its own. |
| `openwebui` | Stops/recreates the `openwebui` + `open-terminal` containers and their network (Apple `container` tool). |
| `llama-server` | Upgrades the `llama.cpp` formula; unloads/reloads the `org.ggml.llama-server` LaunchAgent around it. |
| `whisper-server` | Upgrades the `whisper-cpp` formula; unloads/reloads the `org.ggml.whisper-server` LaunchAgent around it. |
| `mcp-proxy` | Upgrades the `uv` formula (which provides `uvx`); unloads/reloads the `sh.astral.uvx` LaunchAgent around it. |

### LaunchAgent skip-but-upgrade behavior

`llama-server`, `whisper-server`, and `mcp-proxy` each check
`launchagent_loaded` (in `lib/core.sh`, backed by `launchctl list`) before
touching their LaunchAgent. If the agent isn't currently loaded, the
unload/reload hooks are skipped — and logged as skipped — but the
formula is upgraded regardless. This closes a real gap in the original
`mac/update.sh`: `brew upgrade` replaces the binary on disk, but a
running process doesn't pick up the new build until something actually
restarts it, which used to only happen on the next login/reboot.

## Logging

Every run writes a date-stamped log file to `mac/upgrade/logs/` (ignored
by git) capturing the full detail of that run — every log line at every
level, plus the real stdout/stderr of every command — regardless of
`--verbose`. `--verbose` only changes what's *additionally* echoed to the
console: by default the console shows phase/service banners plus
INFO/WARN/ERROR lines; `--verbose` adds the literal commands being run
and their live output. Color is used when attached to a terminal and
suppressed when piped, redirected, or when `NO_COLOR` is set; the log
file itself is always written plain.
