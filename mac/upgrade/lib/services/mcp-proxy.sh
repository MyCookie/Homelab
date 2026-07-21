#!/usr/bin/env bash
#
# mcp-proxy is run via `uvx`, which ships with the `uv` Homebrew formula,
# and kept running by the sh.astral.uvx LaunchAgent. Same shape as
# llama-server.sh: unload/reload the agent around the upgrade, but only
# if it was actually running.

MCP_PROXY_LABEL="sh.astral.uvx"
MCP_PROXY_PLIST="$HOME/Library/LaunchAgents/${MCP_PROXY_LABEL}.plist"
_MCP_PROXY_WAS_LOADED=0

mcp-proxy::description() {
  echo "mcp-proxy / uvx (uv via Homebrew + LaunchAgent)"
}

mcp-proxy::upgrade() {
  run brew upgrade uv
}

mcp-proxy::pre_upgrade() {
  if launchagent_loaded "$MCP_PROXY_LABEL"; then
    _MCP_PROXY_WAS_LOADED=1
    run launchctl unload "$MCP_PROXY_PLIST"
  else
    log_info "mcp-proxy agent isn't running; skipping unload, will still upgrade the formula"
  fi
}

mcp-proxy::post_upgrade() {
  if [ "$_MCP_PROXY_WAS_LOADED" = "1" ]; then
    run launchctl load "$MCP_PROXY_PLIST"
  else
    log_info "mcp-proxy agent wasn't running before the upgrade; leaving it stopped"
  fi
}

register_service "mcp-proxy"
