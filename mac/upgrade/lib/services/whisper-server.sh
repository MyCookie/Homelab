#!/usr/bin/env bash
#
# whisper-server is installed via the `whisper-cpp` Homebrew formula and
# kept running by the org.ggml.whisper-server LaunchAgent. Same shape as
# llama-server.sh: unload/reload the agent around the upgrade, but only
# if it was actually running.

WHISPER_SERVER_LABEL="org.ggml.whisper-server"
WHISPER_SERVER_PLIST="$HOME/Library/LaunchAgents/${WHISPER_SERVER_LABEL}.plist"
_WHISPER_SERVER_WAS_LOADED=0

whisper-server::description() {
  echo "whisper-server (whisper-cpp via Homebrew + LaunchAgent)"
}

whisper-server::upgrade() {
  run brew upgrade whisper-cpp
}

whisper-server::pre_upgrade() {
  if launchagent_loaded "$WHISPER_SERVER_LABEL"; then
    _WHISPER_SERVER_WAS_LOADED=1
    run launchctl unload "$WHISPER_SERVER_PLIST"
  else
    log_info "whisper-server agent isn't running; skipping unload, will still upgrade the formula"
  fi
}

whisper-server::post_upgrade() {
  if [ "$_WHISPER_SERVER_WAS_LOADED" = "1" ]; then
    run launchctl load "$WHISPER_SERVER_PLIST"
  else
    log_info "whisper-server agent wasn't running before the upgrade; leaving it stopped"
  fi
}

register_service "whisper-server"
