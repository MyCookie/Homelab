# Nextcloud

...and other services.

## Debian

This project assumes you're running Debian Stable. As of writing current Stable is [12.11](https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.11.0-amd64-netinst.iso).

Perform a standard install, without a desktop environment, with a SSH server.

>NOTE: `apt` will install packages for a GUI by default. When running headless, add `--no-install-recommends` to avoid installing any desktop envrionment packages, or `xorg`.

## ZFS

Enable the `contrib` repository. Install from backports:

```bash
apt install -t stable-backports zfsutils-linux linux-headers-amd64
```

### Snapshots

Two options:

1. [`zrepl`](https://zrepl.github.io/installation/apt-repos.html). A simple `/etc/zrepl/zrepl.yml`:

```yaml
jobs:
# this job takes care of snapshot creation + pruning
- name: snapjob
  type: snap
  filesystems: {
      "system<": true,
  }
  # create snapshots with prefix `zrepl_` every 15 minutes
  snapshotting:
    type: periodic
    interval: 15m
    prefix: zrepl_
  pruning:
    keep:
    # fade-out scheme for snapshots starting with `zrepl_`
    # - keep all created in the last hour
    # - then destroy snapshots such that we keep 24 each 1 hour apart
    # - then destroy snapshots such that we keep 14 each 1 day apart
    # - then destroy all older snapshots
    - type: grid
      grid: 1x1h(keep=all) | 24x1h | 14x1d
      regex: "^zrepl_.*"
    # keep all snapshots that don't have the `zrepl_` prefix
    - type: regex
      negate: true
      regex: "^zrepl_.*"
```

2. `zfs-auto-snapshot`. Clone the [git repository](https://github.com/zfsonlinux/zfs-auto-snapshot). Perform the `make install` and enable the scripts you need in `/etc/cron.*`.

### NFS

```bash
apt install nfs-kernel-server
```

### Deleting datasets

>**WARNING**: *EXTREMELY DANGEROUS*. This is permenent. Only do this if you completely understand what you're doing.

```bash
zfs list -t snapshot -o name | grep $SNAPSHOT_PREFIX | xargs -n1 zfs destroy
```

## Cockpit

```bash
apt install --no-install-recommends cockpit cockpit-packagekit cockpit-pcp
```

## Nvidia

Enable the `contrib`, `non-free` and `non-free-firmware` repositories. For a headless install:

```bash
apt install --no-install-recommends nvidia-driver firmware-misc-nonfree nvidia-smi
```

## Docker

[Install Docker](https://docs.docker.com/engine/install/debian/). Optionally, add your user to the group `docker` for ease-of-use.

`docker.io` from the Debian repository will technically work, but does not have the current compose plugin. You will need to refactor the compose YAML files and possibly the `.env` files as well.

### Watchtower

```bash
docker run --interactive --tty --detach --name watchtower --restart always --env WATCHTOWER_CLEANUP --env WATCHTOWER_CLEANUP_VOLUMES --volume /var/run/docker.sock:/var/run/docker.sock containrrr/watchtower
```

### Nvidia

[Install the container toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

### Podman

Podman may also work, but will require siginificant re-tooling into whatever the current accepted orchestration system is. You will also have to change some compose directives; for example exposing the Nvidia GPU is easier in Podman:

```yaml
services:
  app:
    ...
    devices:
      - nvidia.com/gpu=all
    ...
```

The catch is you may need to run `nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml` on every boot.

## Virtual Machines

Install libvirt and the cockpit VM webui:

```bash
apt install --no-install-recommends qemu-system libvirt-daemon-system libvirt-clients qmeu-utils ovmf virtinst cockpit-machines
```

We are not supposed to run an instance of `dnsmasq` outside the control of `libvirt`. If you do, networking will fail to create the interfaces it needs. If you see the something similar to:

```bash
Could not start virtual network 'default': internal error
Child process (/usr/sbin/dnsmasq --strict-order --bind-interfaces
--pid-file=/var/run/libvirt/network/default.pid --conf-file=
--except-interface lo --listen-address 192.168.122.1
--dhcp-range 192.168.122.2,192.168.122.254
--dhcp-leasefile=/var/lib/libvirt/dnsmasq/default.leases
--dhcp-lease-max=253 --dhcp-no-override) status unexpected: exit status 2
```

Then there is another instance of `dnsmasq` (or another DHCP daemon that calls it) running on the system.

Disable `dnsmasq`:

```bash
systemctl disable --now dnsmasq.service
```

[See here for more info.](https://wiki.libvirt.org/Virtual_network_default_has_not_been_started.html)

## TrueNAS

Installing Debin on the TrueNAS webui needs some tweaks.

- Set the VNC resolution to 800x600.
- After installing, go back into recovery mode in the ISO, and install GRUB on the "removable" ESP.

## Tailscale

Install Tailscale:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```
