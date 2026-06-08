#!/bin/bash

set -eo pipefail

# stop hermes
limactl stop

# stop openwebui
container stop openwebui
container stop open-terminal

# delete the openwebui network (incase of any abi changes in container)
container network delete openwebui

# update brew
brew update && brew upgrade

# start hermes
limactl start

# pull new images
container image pull ghcr.io/open-webui/open-webui:main
container image pull ghcr.io/open-webui/open-terminal

# recreate the networks, if lost
container network create openwebui

# recreate the containers
container create --detach --rm --interactive --tty --name openwebui --network openwebui --publish 127.0.0.1:8080:8080 --volume $HOME/Volumes/open-webui:/app/backend/data ghcr.io/open-webui/open-webui:main
container create --detach --rm --interactive --tty --name open-terminal --network openwebui --env OPEN_TERMINAL_API_KEY=your-secret-key --volume $HOME/Volumes/open-terminal:/home/user ghcr.io/open-webui/open-terminal

# start the containers
container start openwebui
container start open-terminal

