#!/usr/bin/env bash
#
# openwebui + open-terminal run as a unit on Apple's `container` tool, on
# top of the hermes Lima VM. Ported from the original mac/update.sh, which
# always tore down and recreated both containers together (so an ABI
# change in `container` itself doesn't leave one container speaking a
# different protocol version than the other).

OPEN_WEBUI_IMAGE="ghcr.io/open-webui/open-webui:main"
OPEN_TERMINAL_IMAGE="ghcr.io/open-webui/open-terminal"
OPEN_TERMINAL_API_KEY="${OPEN_TERMINAL_API_KEY:-your-secret-key}"

openwebui::description() {
  echo "openwebui + open-terminal containers (Apple container tool)"
}

openwebui::pre_upgrade() {
  run container stop openwebui
  run container stop open-terminal
  run container network delete openwebui
}

openwebui::upgrade() {
  run container image pull "$OPEN_WEBUI_IMAGE"
  run container image pull "$OPEN_TERMINAL_IMAGE"
}

openwebui::post_upgrade() {
  run container network create openwebui
  run container create --detach --rm --interactive --tty \
    --name openwebui --network openwebui \
    --publish 127.0.0.1:8080:8080 \
    --volume "$HOME/Volumes/open-webui:/app/backend/data" \
    "$OPEN_WEBUI_IMAGE"
  run container create --detach --rm --interactive --tty \
    --name open-terminal --network openwebui \
    --env OPEN_TERMINAL_API_KEY="$OPEN_TERMINAL_API_KEY" \
    --volume "$HOME/Volumes/open-terminal:/home/user" \
    "$OPEN_TERMINAL_IMAGE"
  run container start openwebui
  run container start open-terminal
}

register_service "openwebui"
