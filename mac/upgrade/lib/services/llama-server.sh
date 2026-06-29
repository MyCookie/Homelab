#!/usr/bin/env bash
#
# llama-server is installed via the `llama.cpp` Homebrew formula and kept
# running by the org.ggml.llama-server LaunchAgent. `brew upgrade` alone
# replaces the binary on disk but doesn't restart the running process, so
# this service unloads the agent before upgrading and reloads it after —
# but only if it was actually running to begin with.

LLAMA_SERVER_LABEL="org.ggml.llama-server"
LLAMA_SERVER_PLIST="$HOME/Library/LaunchAgents/${LLAMA_SERVER_LABEL}.plist"
_LLAMA_SERVER_WAS_LOADED=0

llama-server::description() {
  echo "llama-server (llama.cpp via Homebrew + LaunchAgent)"
}

llama-server::upgrade() {
  run brew upgrade llama.cpp
}

llama-server::pre_upgrade() {
  if launchagent_loaded "$LLAMA_SERVER_LABEL"; then
    _LLAMA_SERVER_WAS_LOADED=1
    run launchctl unload "$LLAMA_SERVER_PLIST"
  else
    log_info "llama-server agent isn't running; skipping unload, will still upgrade the formula"
  fi
}

llama-server::post_upgrade() {
  if [ "$_LLAMA_SERVER_WAS_LOADED" = "1" ]; then
    run launchctl load "$LLAMA_SERVER_PLIST"
  else
    log_info "llama-server agent wasn't running before the upgrade; leaving it stopped"
  fi
}

register_service "llama-server"
