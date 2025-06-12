# Nextcloud

...and other services.

## Debian

[12.11](https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.11.0-amd64-netinst.iso).

Perform a standard install, without a desktop environment, with a SSH server.

>NOTE: `apt` will install packages for a GUI by default. When running headless, add `--no-install-recommends` to avoid installing any desktop envrionment packages, or `xorg`.

### ZFS

Enable the `contrib` repository. Install from backports:

```bash
apt install -t stable-backports zfsutils-linux linux-headers-amd64
```

#### Snapshots

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

#### NFS

```bash
apt install nfs-kernel-server
```

#### Deleting datasets

>**WARNING**: *EXTREMELY DANGEROUS*. This is permenent. Only do this if you completely understand what you're doing.

```bash
zfs list -t snapshot -o name | grep $SNAPSHOT_PREFIX | xargs -n1 zfs destroy
```

### Cockpit

```bash
apt install --no-install-recommends cockpit cockpit-packagekit cockpit-pcp
```

### Nvidia

Enable the `contrib`, `non-free` and `non-free-firmware` repositories. For a headless install:

```bash
apt install --no-install-recommends nvidia-driver firmware-misc-nonfree nvidia-smi
```

### Docker

[Install Docker](https://docs.docker.com/engine/install/debian/). Optinally, add user to group `docker` for ease-of-use.

#### Watchtower

```bash
docker run --interactive --tty --detach --name watchtower --restart always --env WATCHTOWER_CLEANUP --env WATCHTOWER_CLEANUP_VOLUMES --volume /var/run/docker.sock:/var/run/docker.sock containrrr/watchtower
```

#### Nvidia

[Install the container toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

### Virtual Machines

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

### TrueNAS

VNC resolution 800x600.

After installing, go back into recovery mode in the ISO, and install GRUB on the "removable" ESP.

### Tailscale

Install Tailscale:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

## Docker

The Compose directives use a named network. This stack isn't running in a swarm, so the network directive isn't strictly necessary, only a nice-to-have.

See `.env` and change the paths as necessary.

### Caddy

Caddy takes care of getting Let's Encrypt certificates using `tailscaled` over its socket.

Caddy needs to proxy the `.well-known` parameters, see the Caddyfile.

#### Caddyfile

To format the Caddyfile inside its container:
```bash
docker exec -it caddy caddy fmt --overwrite /etc/caddy/Caddyfile
```

To reload Caddy after any changes inside its container:
```bash
docker exec -it caddy caddy reload --config /etc/caddy/Caddyfile
```

### Nextcloud

Use `production` which is usually a release behind `latest`.

#### Background Tasks

Use `cron.php` located in `/var/www/html` for background tasks.

When deployed using a single-instance Docker container, setup a second container which only calls `cron.php`. For example:
```bash
docker run --interactive --tty --detach --name cron --restart unless-stopped --entrypoint="/var/www/html/cron.php" --volume $HOME/volumes/nextcloud/var/www/html:/var/www/html nextcloud:production
```

#### Backup

Since we're on TrueNAS, we'll rely on ZFS snapshots to facilitate backups. ZFS snapshots will capture the entire ZVOL image. And by using MinIO, we can setup bucket goverence policies that keep the object even after it's modified or deleted. A good default is 30 days.

[Documentation](https://docs.nextcloud.com/server/stable/admin_manual/maintenance/backup.html).

#### OCC

Calling `docker exec` with the `www-data` user will drop you in the `/var/www/html` folder:
```bash
docker exec --interactive --tty --user www-data nextcloud php occ $COMMAND
```

`php occ maintenance:mode --on` will prevent any scripts and tasks from running in the container.

[Documentation](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/occ_command.html).

### MariaDB

10.11 is tagged as LTS, and is supported until February 2028.

#### MariaDB >10.5

Add `--innodb-read-only-compressed=OFF` to the `command` directive in Docker. See [here](https://help.nextcloud.com/t/new-setup-docker-compose-not-working/115673/12) for the discussion.

### Synapse

Before starting Synapse, generate the `homeserver.yaml` first:

```bash
docker run --interactive --tty --rm --mount type=volume,src=$VOLUMES_PATH/data,dst=/data --env SYNAPSE_SERVER_NAME=$DOMAIN_URL --env SYNAPSE_REPORT_STATS={yes/no} matrixdotorg/synapse generate
```

#### Delegation
There are two reasons to use delegation:
1. While serving Synapse on a subdomain, show a user as `@user:domain.tld` instead of `@user:matrix.domain.tld` inside clients:
    - `/.well-known/matrix/client` should return HTTP code 200 and
        ```yaml
        {"m.homeserver": {"base_url": "https://matrix.$DOMAIN_URL"}}
        ```
2. By default, servers communicate over port `8448`, by using delegation, we can force servers to send their REST calls to another port, say `443`:
    - `/.well-known/matrix/server` should return HTTP code 200 and
        ```yaml
        {"m.server": "matrix.$DOMAIN_URL:443"}
        ```

The Caddyfile contains these directives.

#### Postgres 12

By default the Postgres Docker image makes a `postgres` admin user. To work with the database:
```bash
docker exec --interactive --tty --user postgres synapsedb $COMMAND
```

To setup and convert Synapse from SQLite to Postgres:

1. Create the `synapse` user:
    ```bash
    docker exec -it -u postgres synapsedb createuser --pwprompt synapse
    ```
   Enter the password when prompted.
2. Create the `synapse` database:
    ```bash
    docker exec -it -u postgres synapsedb createdb --encoding=UTF8 --locale=C --template=template0 --owner=synapse synapse
    ```
3. Copy the existing `homeserver.yaml` to `homeserver.postgres.yaml` and edit its database section:
   ```yaml
   database:
      name: psycopg2
      args:
        user: synapse
        password: $SYNAPSE_USER_PASS
        dbname: synapse
        host: synapsedb
        cp_min: 5
        cp_max: 10
   ```
4. Migrate the entries using
    ```bash
    docker exec -it synapse synapse_port_db --sqlite-database /data/homeserver.db --postgres-config homeserver.postgres.yaml
    ```
5. Replace the SQLite `homeserver.yaml` with `homeserver.postgres.yaml`, optionally keeping the original.

Sometimes, depending on the version of Synapse you started with, you may need to fix some keys. The SQL required will be posted in the error logs when Synapse fails to start.

#### Upgrading Postgres

Use the docker image `pgautoupgrade/pgautoupgrade:$PG_VERSION-alpine`.

```bash
docker run --name pgautoupgrade -it --mount type=bind,source=/data/volumes/postgres/data,target=/var/lib/postgresql/data -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD -e PGAUTO_ONESHOT=yes pgautoupgrade/pgautoupgrade:13-alpine
```

TODO: fill in more detail.

#### Users

To add a new user from the console:
```bash
docker exec -it synapse register_new_matrix_user http://localhost:8008 -c /data/homeserver.yaml
```

TODO: enable user registration.

### YoutubeDL-Material

Basic install. See [here](https://github.com/ytdl-org/youtube-dl-material) for more information.

### Ollama

Basic docker install, no CUDA. Does not provide an OpenAI/ChatGPT-compatible API for Nextcloud.

```bash
docker run --interactive --tty --detach --restart unless-stopped --name ollama --hostname ollama --volume $VOLUMES_PATH/ollama/root/.ollama:/root/.ollama ollama/ollama
```

### LocalAI

TODO. Very heavy, very black-box. Possibly replace with LightLLM, combined with Ollama.

### Gitlab

To get the root password in the first 24 hours of image creation:
```bash
docker exec --interactive --tty gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

See the [documentation](https://docs.gitlab.com/ee/install/docker.html).

## MinIO

Self-hosted S3 clone. Using S3 primary storage separates the data from the VM running Nextcloud. Allows ZFS to snapshot and clone data separately from the VM.

By default, the TrueNAS plugin of MinIO exposes port 9001 for its API, and 9002 for the web console. Inside the jail, the ports are upstream's default: 9000 for the API, and 9001 for the web console.

### Tailscale

When building the jail, make sure to check `allow_tun`. Install `tailscale` using `pkg`.

While inside the jail, the API port is 9000 and the web console port is 9001.

### Security

#### Policies
When setting policies, the declaration must also specify any children as well. For example, `arn:aws:s3:::nextcloud` only grants the policies to the bucket `nextcloud`, but not its children. In order to grant access to its children as well, the policy must apply to `arn:aws:s3:::nextcloud/*`. `nextcloud*` also works, but also grants access to buckets that start with `nextcloud[...]`.

## Reverse Proxy

Add an additonal reverse proxy in front of Caddy running in the container. This abstracts away the internal tailnet for traffic coming from the wider internet.

### Caddy

Bog-standard Caddy install. Prefer to use the binary from the distribution's repository. Since this instance will handle TLS termination for internet-wide traffic, no special install or setup is necessary.

### TLS

We can use Caddy's internal Let's Encrypt toolchain to automatically get a certificate. For Cloudflare, grab the Origin CA associated with the account, and put it somewhere Caddy can read. For example: `/etc/ssl/$DOMAIN_URL/$DOMAIN_URL.${cert|key}.pem`.

### TLS Host Header

When reverse proxying to a server using HTTPS with a differnt domain, if we do not change the headers, the browser will refuse to connect, as will any other proxies. When running a site served over HTTPS on a tailnet, this is the case. In order to solve this, we will need to manage the Host header when passing traffic through the proxy. An example is provided below.

```Caddyfile
matrix.$DOMAIN_URL {
	tls /etc/ssl/$DOMAIN_URL/$DOMAIN_URL.cert.pem /etc/ssl/$DOMAIN_URL/$DOMAIN_URL.key.pem

	reverse_proxy /_matrix/* https://matrix.$TAILNET.ts.net:8008 {
        # https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#https
		# when proxying to https on a different domain, switch the header for SNI
		header_up Host matrix.$TAILNET.ts.net
		header_down Host matrix.$DOMAIN_URL
    }
	reverse_proxy /_synapse/client/* https://matrix.$TAILNET.ts.net:8008 {
        # https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#https
		# when proxying to https on a different domain, switch the header for SNI
		header_up Host matrix.$TAILNET.ts.net
		header_down Host matrix.$DOMAIN_URL
    }

	log {
		output file /var/log/caddy/$DOMAIN_URL/matrix/caddy.log
	}
}
```

See https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#https for more details.

### Logging

Add the `log` directive to each proxied site. The location is arbitrary, as long as Caddy can write to it.

```Caddyfile
log {
	output file /var/log/caddy/$DOMAIN_URL/caddy.log
}
```

Add the subdomain after the parent domain in the above example to separate the logs by site.

### Matrix

For domain delegation, see #Delegation. An example is provided below:

```Caddyfile
header /.well-known/matrix/* Content-Type application/json
header /.well-known/matrix/* Access-Control-Allow-Origin *
respond /.well-known/matrix/server `{"m.server": "matrix.$DOMAIN_URL:443"}`
respond /.well-known/matrix/client `{"m.homeserver":{"base_url":"https://matrix.$DOMAIN_URL"}}`
```

### Troubleshooting

#### Tailscale DNS issues

There are multiple services fighting over `/etc/resolve.conf` in a Linux machine. Until all services adopt a single DNS resolver, this mess will continue.

This issue will appear as an inability to access sites even if the proxy is connected to Tailscale.

You have this issue when:

- You CAN:
  - See a successful `tailscale status`.
  - Successfully `tailscale ping` a node.
  - Successfully `ping $TAILNET_NODE_IP` a node.
  - Successfully get a `NOERROR` on `dig ts.net` or resolve an IP with `nslookup ts.net`.
- You CAN NOT:
  - Successfully `curl $TAILNET_NODE_HOSTNAME`.
  - Successfully get a `NOERROR` on `dig $TAILNET_NODE_HOSTNAME.$TAILNET.ts.net`

For machines with `systemd-resolved`, use `resolvectl` to see the available networks and their attached DNS servers. A failed config will return:

```bash
user@host$ resolvectl
Link 3 (tailscale0)
    Current Scopes: none
         Protocols: -DefaultRoute -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
```

To attempt to resolve this issue with `resolvectl`, run:

```bash
# resolvectl dns tailscale0 100.100.100.100
# resolvectl domain tailscale0 ts.net
# systemctl restart systemd-resolved
```