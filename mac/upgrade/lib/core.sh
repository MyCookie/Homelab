#!/usr/bin/env bash
#
# Shared logging, color, and execution helpers for the mac upgrade tool.
# Sourced by update.sh — not meant to be run directly.

CORE_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPGRADE_DIR="$(cd "$CORE_SH_DIR/.." && pwd)"
LOG_DIR="$UPGRADE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/update-$(date +%Y%m%d-%H%M%S).log"
: >"$LOG_FILE"

DRY_RUN="${DRY_RUN:-0}"
VERBOSE="${VERBOSE:-0}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'
  C_RED=$'\033[31m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_GREEN=$'\033[32m'
  C_BOLD=$'\033[1m'
else
  C_RESET=""
  C_RED=""
  C_YELLOW=""
  C_BLUE=""
  C_GREEN=""
  C_BOLD=""
fi

# The log file always gets the plain, unconditional, full-detail record of
# the run; --verbose only changes what additionally reaches the console.
_log_to_file() {
  printf '%s\n' "$1" >>"$LOG_FILE"
}

log_info() {
  local msg="[INFO] $*"
  _log_to_file "$msg"
  printf '%s%s%s\n' "$C_BLUE" "$msg" "$C_RESET"
}

log_warn() {
  local msg="[WARN] $*"
  _log_to_file "$msg"
  printf '%s%s%s\n' "$C_YELLOW" "$msg" "$C_RESET" >&2
}

log_error() {
  local msg="[ERROR] $*"
  _log_to_file "$msg"
  printf '%s%s%s\n' "$C_RED" "$msg" "$C_RESET" >&2
}

log_debug() {
  local msg="[DEBUG] $*"
  _log_to_file "$msg"
  if [ "$VERBOSE" = "1" ]; then
    printf '%s\n' "$msg"
  fi
}

log_step() {
  local msg="==> $*"
  _log_to_file "$msg"
  printf '%s%s%s%s\n' "$C_BOLD" "$C_GREEN" "$msg" "$C_RESET"
}

# run CMD [ARGS...]
#
# Single chokepoint for dry-run / verbosity / logging. Service modules
# always go through this for any command with a real side effect, so they
# never need to branch on $DRY_RUN or $VERBOSE themselves.
run() {
  log_debug "+ $*"
  if [ "$DRY_RUN" = "1" ]; then
    log_info "[dry-run] $*"
    return 0
  fi
  if [ "$VERBOSE" = "1" ]; then
    "$@" 2>&1 | tee -a "$LOG_FILE"
    return "${PIPESTATUS[0]}"
  fi
  "$@" >>"$LOG_FILE" 2>&1
}
