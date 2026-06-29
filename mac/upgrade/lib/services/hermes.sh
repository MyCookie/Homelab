#!/usr/bin/env bash
#
# "hermes" is the Lima VM that the openwebui service's containers run on
# top of. There's no package to upgrade here — this service exists purely
# to stop the VM out of the way before container work and bring it back up
# afterward. Lima's own binary is covered by the brew service.

hermes::description() {
  echo "hermes Lima VM (stop/start around container work)"
}

hermes::pre_upgrade() {
  run limactl stop
}

hermes::upgrade() {
  log_info "hermes has no package of its own to upgrade; lima itself is covered by the brew service"
}

hermes::post_upgrade() {
  run limactl start
}

register_service "hermes"
