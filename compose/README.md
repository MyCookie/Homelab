# Docker

The Compose directives use a named network. This stack isn't running in a swarm, so the network directive isn't strictly necessary, only a nice-to-have.

See `services/env/nextcloud.env` and change the paths as necessary.

## Watchtower

Start Watchtower if you haven't already.

```bash
docker run --interactive --tty --detach --name watchtower --restart always --env WATCHTOWER_CLEANUP --env WATCHTOWER_CLEANUP_VOLUMES --volume /var/run/docker.sock:/var/run/docker.sock containrrr/watchtower
```

## Caddy

Caddy takes care of getting Let's Encrypt certificates using `tailscaled` over its socket.

If Synapse is running on this stack, Caddy needs to proxy the `.well-known` parameters, see the Caddyfile.

### Caddyfile

To format the Caddyfile inside its container:
```bash
docker exec -it caddy caddy fmt --overwrite /etc/caddy/Caddyfile
```

To reload Caddy after any changes inside its container:
```bash
docker exec -it caddy caddy reload --config /etc/caddy/Caddyfile
```

## Nextcloud

~~Use `production` which is usually a release behind `latest`.~~

The `production` tag is no longer available, we will need to explicitly define which version of Nextcloud to run.

>NOTE: This is **not** the **A**ll-**I**n-**O**ne image.

### Background Tasks

Use `cron.php` located in `/var/www/html` for background tasks.

When deployed using a single-instance Docker container, setup a second container which only calls `cron.php`. For example:
```bash
docker run --interactive --tty --detach --name cron --restart unless-stopped --entrypoint="/var/www/html/cron.php" --volume $HOME/volumes/nextcloud/var/www/html:/var/www/html nextcloud:production
```

### Backup

Since we're on TrueNAS, we'll rely on ZFS snapshots to facilitate backups. ZFS snapshots will capture the entire ZVOL image. And by using MinIO, we can setup bucket goverence policies that keep the object even after it's modified or deleted. A good default is 30 days.

[Documentation](https://docs.nextcloud.com/server/stable/admin_manual/maintenance/backup.html).

### OCC

Calling `docker exec` with the `www-data` user will drop you in the `/var/www/html` folder:
```bash
docker exec --interactive --tty --user www-data nextcloud php occ $COMMAND
```

`php occ maintenance:mode --on` will prevent any scripts and tasks from running in the container.

[Documentation](https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/occ_command.html).

## MariaDB

10.11 is tagged as LTS, and is supported until February 2028.

### MariaDB >10.5

Add `--innodb-read-only-compressed=OFF` to the `command` directive in Docker. See [here](https://help.nextcloud.com/t/new-setup-docker-compose-not-working/115673/12) for the discussion.

### Troubleshooting

#### Errors in management tables

An example of the error:
```bash
2025-10-29  4:51:40 3 [ERROR] Incorrect definition of table mysql.column_stats: expected column 'hist_type' at position 9 to have type enum('SINGLE_PREC_HB','DOUBLE_PREC_HB','JSON_HB'), found type enum('SINGLE_PREC_HB','DOUBLE_PREC_HB').
2025-10-29  4:51:40 3 [ERROR] Incorrect definition of table mysql.column_stats: expected column 'histogram' at position 10 to have type longblob, found type varbinary(255).
```

May be caused by partial upgrades of the database. To fix, you will need to stop all processes using the database and run:

```
# mariadb-upgrade -u root -p -h nextcloud-mariadb
```

Another (lazy) possible way-since we're using Docker-is to add the environment flag `MARIADB_AUTO_UPGRADE=1` and rebuild the container.

[Nextcloud Talk discussion.](https://help.nextcloud.com/t/incorrect-definition-of-table-mysql-column-stats-expected-column-histogram-at-position-10-to-have-type-longblob-found-type-varbinary-255/145513)

## Synapse

Before starting Synapse, generate the `homeserver.yaml` first:

```bash
docker run --interactive --tty --rm --mount type=volume,src=$VOLUMES_PATH/data,dst=/data --env SYNAPSE_SERVER_NAME=$DOMAIN_URL --env SYNAPSE_REPORT_STATS={yes/no} matrixdotorg/synapse generate
```

>NOTE: To avoid any unexpected errors from unintended feature availability, we're using the oldest version of Postgres Synapse will allow.

### Delegation
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

### Postgres

By default the Postgres Docker image makes a `postgres` admin user. To work with the database:
```bash
docker exec --interactive --tty --user postgres postgres $COMMAND
```

To setup and convert Synapse from SQLite to Postgres:

1. Create the `synapse` user:
    ```bash
    docker exec -it -u postgres postgres createuser --pwprompt synapse
    ```
   Enter the password when prompted.
2. Create the `synapse` database:
    ```bash
    docker exec -it -u postgres postgres createdb --encoding=UTF8 --locale=C --template=template0 --owner=synapse synapse
    ```
3. Copy the existing `homeserver.yaml` to `homeserver.postgres.yaml` and edit its database section:
   ```yaml
   database:
      name: psycopg2
      args:
        user: synapse
        password: $SYNAPSE_USER_PASS
        dbname: synapse
        host: postgres
        cp_min: 5
        cp_max: 10
   ```
4. Migrate the entries using
    ```bash
    docker exec -it synapse synapse_port_db --sqlite-database /data/homeserver.db --postgres-config homeserver.postgres.yaml
    ```
5. Replace the SQLite `homeserver.yaml` with `homeserver.postgres.yaml`, optionally keeping the original.

Sometimes, depending on the version of Synapse you started with, you may need to fix some keys. The SQL required will be posted in the error logs when Synapse fails to start.

### Upgrading Postgres

Use the docker image `pgautoupgrade/pgautoupgrade:$PG_VERSION-alpine`.

```bash
docker run --name pgautoupgrade -it --mount type=bind,source=/data/volumes/postgres/data,target=/var/lib/postgresql/data -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD -e PGAUTO_ONESHOT=yes pgautoupgrade/pgautoupgrade:14-alpine
```

[The Github repo has more information for involved upgrades.](https://github.com/pgautoupgrade/docker-pgautoupgrade)

### Users

To add a new user from the console:
```bash
docker exec -it synapse register_new_matrix_user http://localhost:8008 -c /data/homeserver.yaml
```

TODO: enable user registration.

## YoutubeDL-Material

Basic install. See [here](https://github.com/ytdl-org/youtube-dl-material) for more information.

## Ollama

Basic docker install. To use an Nvidia GPU for CUDA acceleration, add this:

```yaml
services:
  [...]
  ollama:
    [...]
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1 # alternatively, use `count: all` for all GPUs
              capabilities: [gpu]
  [...]
```

## LocalAI

TODO. Migrate from OpenWebUI to LocalAI?

## MinIO

Self-hosted S3 clone. Using S3 primary storage separates the data from the VM running Nextcloud. Allows ZFS to snapshot and clone data separately from the VM.

By default, the TrueNAS plugin of MinIO exposes port 9001 for its API, and 9002 for the web console. Inside the jail, the ports are upstream's default: 9000 for the API, and 9001 for the web console.

### Tailscale

When building the jail, make sure to check `allow_tun`. Install `tailscale` using `pkg`.

While inside the jail, the API port is 9000 and the web console port is 9001.

### Security

#### Policies
When setting policies, the declaration must also specify any children as well. For example, `arn:aws:s3:::nextcloud` only grants the policies to the bucket `nextcloud`, but not its children. In order to grant access to its children as well, the policy must apply to `arn:aws:s3:::nextcloud/*`. `nextcloud*` also works, but also grants access to buckets that start with `nextcloud[...]`.

## Jellyfin

### Nvidia

To enable transcoding, install the container toolkit, as well as the required packages for NVENC/NVDEC.

```bash
apt install --no-install-recommends libnvidia-encode1
```

### Intel QuickSync

Add the `render` group ID to the docker container:

```console
$ getent group render | cut -d: -f3
```

```yaml
services:
  jellyfin:
    [...]
    group_add:
      - '${GROUP_ID}'
    [...]
    devices:
      - /dev/dri/renderD128:/dev/dri/renderD128 # change this to the render device you wish to use
    [...]
```

Check if this works:

```console
# docker exec -it jellyfin /usr/lib/jellyfin-ffmpeg/vainfo
# docker exec -it jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg -v verbose -init_hw_device vaapi=va -init_hw_device opencl@va
```

The full documentation is [here](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/intel).

## Tailscale

### Caddy with sidecar container

Running a sidecar Tailscale container makes it difficult for Caddy to access the socket to obtain certificates. The Nextcloud AIO discussions page has a [breakdown](https://github.com/nextcloud/all-in-one/discussions/5439) of how to access the sidecar socket.

A simple implementation of the concept:

```yaml
services:
  caddy:
    image: caddy
    restart: unless-stopped
    container_name: nextcloud-caddy
    hostname: nextcloud-caddy
    # we won't create any config files since our need is very simple
    entrypoint: ["caddy", "reverse-proxy", "--from", "nextcloud.TAIL_NET.ts.net", "--to", "nextcloud"]
    depends_on:
      - nextcloud
      - tailscale
    ports:
      - "443:443"
    volumes:
      - type: volume
        source: tailscale_sock
        target: /var/run/tailscale/ # Mount the volume for /var/run/tailscale/tailscale.sock
        read_only: true

  tailscale:
    image: tailscale/tailscale
    container_name: tailscale
    restart: unless-stopped
    hostname: tailscale
    environment:
      - TS_AUTHKEY=TS_CLIENT_SECRET
      - TS_EXTRA_ARGS=--advertise-tags=tag:container
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_USERSPACE=false
    volumes:
      - $VOLUMES_PATH/nextcloud_caddy_tailscale/state:/var/lib/tailscale
    devices:
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - net_admin
```

## Gitlab

To get the root password in the first 24 hours of image creation:
```bash
docker exec --interactive --tty gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

See the [documentation](https://docs.gitlab.com/ee/install/docker.html).

## Pruning

Most of this functionality is now part of Watchtower when running with the `WATCHTOWER_CLEANUP` and `WATCHTOWER_CLEANUP_VOLUMES` environment variables passed. The units are left in this document for reference.

`docker-system-prune.service`:

```systemd
[Unit]
Description=Clean the system of any unused Docker images, containers, networks, etc.

# TODO: if BindsTo is defined, do we need to define Requires?
Requires=docker.service
BindsTo=docker.service
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/docker system prune -f

[Install]
WantedBy=multi-user.target
```

`docker-system-prune.timer`:

```systemd
[Unit]
Description=Once a day clean the system of any unused Docker images, containers, networks, etc.

# TODO: if BindsTo is defined, do we need to define Requires?
Requires=docker.service
BindsTo=docker.service
After=docker.service

[Timer]
Unit=docker-system-prune.service
OnCalendar=daily
AccuracySec=1h
Persistent=true

[Install]
WantedBy=multi-user.target
```
