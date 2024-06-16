# Nextcloud

...and other services.

[[_TOC_]]

## Debian

Install `docker.io`, `docker-compose` from `stable`. Optinally, add user to group `docker` for ease-of-use.

### TrueNAS

VNC resolution 800x600.

After installing, go back into recovery mode in the ISO, and install GRUB on the "removable" ESP.

### Tailscale

No extra configuration required.

## Docker

See `.env` and change the paths as necessary.

### Caddy

Caddy takes care of getting Let's Encrypt certificates using `tailscaled` over its socket.

Caddy needs to proxy the `.well-known` parameters, see the Caddyfile.

#### Caddyfile

To format the Caddyfile inside its container: `docker exec -it caddy /bin/sh -c "caddy fmt --overwrite /etc/caddy/Caddyfile"`.

To reload Caddy after any changes inside its container: `docker exec -it caddy /bin/sh -c "caddy reload --config /etc/caddy/Caddyfile"`.

### Nextcloud

Use `production` which is usually a release behind `latest`.

#### Background Tasks

Use `cron.php` located in `/var/www/html` for background tasks.

When deployed using a single-instance Docker container, setup a second container which only calls `cron.php`. The one-liner would look like: `docker run --interactive --tty --detach --name cron --restart unless-stopped --entrypoint="/var/www/html/cron.php" --volume $HOME/volumes/nextcloud/var/www/html:/var/www/html nextcloud:production`.

#### Backup

Since we're on TrueNAS, we'll rely on ZFS snapshots to facilitate backups. See also MinIO, below.

[Documentation](https://docs.nextcloud.com/server/stable/admin_manual/maintenance/backup.html).

#### OCC

Invoke OCC with the `www-data` user. For Docker: `docker exec --interactive --tty --user www-data nextcloud /bin/bash`. This will drop you in `/var/www/html` inside the container, from which you can invoke `php occ $COMMAND`.

[Documentation](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/occ_command.html).

### MariaDB

10.11 is tagged as LTS, and is supported until February 2028.

#### MariaDB >10.5

Add `--innodb-read-only-compressed=OFF` to the `command` directive in Docker. See [here](https://help.nextcloud.com/t/new-setup-docker-compose-not-working/115673/12) for the discussion.

### Synapse

todo document homeserver.yaml

#### Postgres 12

todo document creating synapse user and table

#### Users

todo document user management

### YoutubeDL-Material

Basic install. See [here](https://github.com/ytdl-org/youtube-dl-material) for more information.

### Ollama

Basic docker install, no CUDA.

### LocalAI

TODO.

## MinIO

Self-hosted S3 clone. Using S3 primary storage separates the data from the VM running Nextcloud. Allows ZFS to snapshot and clone data separately from the VM.

By default, the TrueNAS plugin of MinIO exposes port 9001 for its API, and 9002 for the web console. Inside the jail, the ports are upstream's default: 9000 for the API, and 9001 for the web console.

### Tailscale

When building the jail, make sure to check `allow_tun`. Install `tailscale` using `pkg`.

While inside the jail, the API port is 9000 and the web console port is 9001.

### Security

#### Policies
When setting policies, the declaration must also specify any children as well. For example, `arn:aws:s3:::nextcloud` only grants the policies to the bucket `nextcloud`, but not its children. In order to grant access to its children as well, the policy must apply to `arn:aws:s3:::nextcloud/*`. `nextcloud*` also works, but also grants access to buckets that start with `nextcloud[...]`.
