# ZFS

## ZPool

Create the pool:

```bash
zpool create -f -m /pool/homelab -O encryption=on -O keyformat=passphrase -O keylocation=prompt Homelab \
	mirror $DISK_1_LABEL $DISK_2_LABEL \
    ...
```

# Hierarchy

- `Homelab`: The name of the pool, and the top-level dataset.
    - `Archive`: Things that need to be saved, but do not fit into any of the descriptions below.
    - `Downloads`: Anything downloaded by a download manager running inside the Homelab.
    - `Library`: The top-level dataset of any data that is managed by services running inside the Homelab.
        - `Audiobooks`: Audiobooks managed by Audiobookshelf.
        - `Games`
            - `GOG`: GOG installer files managed by `lgogdownloader`.
                - Currently, `lgogdownloader` is running on a client system.
                - TODO: Build a Docker container to automatically download and update GOG installer files.
            - `Steam`: The archived Steam Library.
        - `Music`
        - `Podcasts`: Podcasts managed by Audiobookshelf.
    - `Services`
        - `Docker`
            - `Projects`: Compose/Swarm Stacks, Helm Charts, etc.
            - `Volumes`
        - `libvirt`
            - `Domains`
            - `Images`: ISOs
            - `Pool`
