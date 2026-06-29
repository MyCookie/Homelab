#!/usr/bin/env bash
#
# Updates and upgrades the services configured for this Mac. Each service
# is a plugin under lib/services/ that defines <name>::description,
# <name>::upgrade (required), and optional <name>::pre_upgrade /
# <name>::post_upgrade hooks. See lib/services/*.sh for examples and
# README.md for the full convention.
#
# Targets bash 3.2 (macOS's stock /bin/bash): no associative arrays, no
# `local -n`, no `mapfile`, no GNU long-option getopt. Also deliberately
# does not use `set -u`: bash versions before 4.4 (including 3.2) treat
# `"${empty_array[@]}"` as an unbound-variable error under `set -u`, and
# SERVICES/TARGET_LIST are legitimately empty in some runs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
SERVICES_DIR="$LIB_DIR/services"

# shellcheck source=lib/core.sh
source "$LIB_DIR/core.sh"

SERVICES=()
register_service() {
  SERVICES+=("$1")
}

if [ -d "$SERVICES_DIR" ]; then
  for service_file in "$SERVICES_DIR"/*.sh; do
    [ -e "$service_file" ] || continue
    # shellcheck source=/dev/null
    source "$service_file"
  done
  unset service_file
fi

print_help() {
  cat <<'EOF'
Usage: update.sh [OPTIONS]

Updates and upgrades the services configured for this Mac. Each service
runs through an optional pre_upgrade (shutdown) hook, its upgrade step,
and an optional post_upgrade (restart) hook.

Options:
  -l, --list-services    List the registered services and exit.
  -s, --service SERVICE  Only run the named service. See --list-services
                          for valid names. Default: run every registered
                          service.
  --dry-run               Print what would run without changing anything.
                          Covers pre/post hooks as well as the upgrade
                          step itself.
  --no-restart            Skip post_upgrade (restart) hooks only.
  --skip-hooks            Skip both pre_upgrade and post_upgrade hooks.
  -v, --verbose           Also stream each command's real output to the
                          console. The log file always has full detail
                          regardless of this flag.
  -h, --help              Show this help and exit.

Examples:
  update.sh                              Run every service end to end.
  update.sh -l                           List available services.
  update.sh -s brew --dry-run            Preview the brew service only.
  update.sh --service=llama-server --no-restart
                                          Upgrade the formula, leave the
                                          agent unloaded for a manual
                                          restart.
  update.sh --dry-run --skip-hooks       Preview upgrade commands only,
                                          no hook simulation.
  update.sh -v                           Run everything, also streaming
                                          full output to the console.

Note: scoping to a single service with --service only runs that service's
own lifecycle — e.g. --service=brew upgrades Homebrew formulae but will not
restart any LaunchAgent-backed binary it touches. That's each LaunchAgent
service's own responsibility (see --list-services).
EOF
}

list_services() {
  if [ "${#SERVICES[@]}" -eq 0 ]; then
    echo "No services registered."
    return 0
  fi
  local name
  for name in "${SERVICES[@]}"; do
    printf '%-16s %s\n' "$name" "$("${name}::description")"
  done
}

service_exists() {
  local target="$1" name
  for name in "${SERVICES[@]}"; do
    if [ "$name" = "$target" ]; then
      return 0
    fi
  done
  return 1
}

# run_phase PHASE SERVICE...
#
# Dispatches an optional lifecycle hook (pre_upgrade/post_upgrade) for each
# given service, skipping services that don't define it.
run_phase() {
  local phase="$1" name fn
  shift
  for name in "$@"; do
    fn="${name}::${phase}"
    if declare -f "$fn" >/dev/null 2>&1; then
      log_step "[$name] $phase"
      if ! "$fn"; then
        log_error "[$name] $phase failed"
        FAILURES+=("$name:$phase")
      fi
    fi
  done
}

ACTION="run"
TARGET_SERVICE=""
NO_RESTART=0
SKIP_HOOKS=0

while [ $# -gt 0 ]; do
  case "$1" in
    -l | --list-services)
      ACTION="list"
      shift
      ;;
    -s)
      TARGET_SERVICE="$2"
      shift 2
      ;;
    --service=*)
      TARGET_SERVICE="${1#*=}"
      shift
      ;;
    --service)
      TARGET_SERVICE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-restart)
      NO_RESTART=1
      shift
      ;;
    --skip-hooks)
      SKIP_HOOKS=1
      shift
      ;;
    -v | --verbose)
      VERBOSE=1
      shift
      ;;
    -h | --help)
      ACTION="help"
      shift
      ;;
    *)
      log_error "Unknown argument: $1"
      print_help >&2
      exit 1
      ;;
  esac
done

case "$ACTION" in
  help)
    print_help
    exit 0
    ;;
  list)
    list_services
    exit 0
    ;;
esac

if [ -n "$TARGET_SERVICE" ]; then
  if ! service_exists "$TARGET_SERVICE"; then
    log_error "Unknown service: $TARGET_SERVICE"
    echo "Valid services:" >&2
    list_services >&2
    exit 1
  fi
  TARGET_LIST=("$TARGET_SERVICE")
else
  TARGET_LIST=("${SERVICES[@]}")
fi

FAILURES=()

if [ "$SKIP_HOOKS" != "1" ]; then
  run_phase pre_upgrade "${TARGET_LIST[@]}"
fi

for name in "${TARGET_LIST[@]}"; do
  fn="${name}::upgrade"
  if ! declare -f "$fn" >/dev/null 2>&1; then
    log_error "[$name] has no ::upgrade function defined (required) — skipping"
    FAILURES+=("$name:upgrade")
    continue
  fi
  log_step "[$name] upgrade"
  if ! "$fn"; then
    log_error "[$name] upgrade failed"
    FAILURES+=("$name:upgrade")
  fi
done

if [ "$SKIP_HOOKS" != "1" ] && [ "$NO_RESTART" != "1" ]; then
  run_phase post_upgrade "${TARGET_LIST[@]}"
fi

if [ "${#FAILURES[@]}" -gt 0 ]; then
  log_error "Completed with failures: ${FAILURES[*]}"
  exit 1
fi

log_step "All done. Full log: $LOG_FILE"
exit 0
