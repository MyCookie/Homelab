#!/usr/bin/env bash
#
# Homebrew formulae & casks. No pre/post hooks — there's nothing to shut
# down or restart around a package-manager invocation itself. Individual
# LaunchAgent-backed formulae (llama-server, whisper-server, mcp-proxy)
# own their own restart hooks in their respective service files.

brew::description() {
  echo "Homebrew formulae & casks (brew update && brew upgrade)"
}

brew::upgrade() {
  run brew update && run brew upgrade
}

register_service "brew"
