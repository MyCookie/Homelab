# Gitlab
[[_TOC_]]

## Debian

### TrueNAS
VNC resolution 800x600.

After installing, go back into recovery mode in the ISO, and install GRUB on the "removable" ESP.

### `/etc/hosts`
```bash
127.0.0.1	gitlab.TAILNET.ts.net gitlab
127.0.1.1	gitlab.TAILNET.ts.net	gitlab
```

### Upgrading
Check release notes at https://docs.gitlab.com/ee/update/.

If there is a hold, `apt-mark unhold gitlab-ce` to allow upgrades again. `apt-mark showhold` lists all packages pinned to a version.

See https://docs.gitlab.com/ee/update/package/index.html#upgrade-to-a-specific-version-using-the-official-repositories.

#### Downgrading
It's only possible to downgrade between minor versions. While, it's technically possible to downgrade to a major version, it's not recommended. Gitlab versioning is [major].[minor].[hotfix], for example 16.8.3 can only be downgraded to 16.x.y. For best results, don't skip minor versions, so downgrade 16.8 to 16.7 before continuing to 16.6.

1. Stop `puma` and `sidekiq` using `gitlab-ctl`
2. Uninstall Gitlab `dpkg -r gitlab-ce`
3. Identify the version you can download `apt-cache madison gitlab-ce`
4. Install the version you want `apt install gitlab-ce=16.8.3-ce.0`
5. Reconfigure with `gitlab-ctl`
6. Make sure `puma` and `sidekiq` were started.
7. (Optional) Prevent future upgrades with `apt-mark hold gitlab-ce`

If Gitlab isn't responding, restart all services with `gitlab-ctl`. Also check the logs of `gitlab-runsvdir.service`, or restart it after reconfiguring.

## Tailscale

### SSL
```bash
# this generates a Let's Encrypt cert through ZeroSSL
# valid for 30 days
# WILL NOT AUTOMATICALLY RENEW
sudo tailscale cert
```

## Config

### `/etc/gitlab/gitlab.rb`
```ruby
external_url 'https://gitlab.TAILNET.ts.net'
```

#### SSL
```ruby
nginx['redirect_http_to_https'] = true
nginx['ssl_certificate'] = "/home/administrator/gitlab.TAILNET.ts.net.crt"
nginx['ssl_certificate_key'] = "/home/administrator/gitlab.TAILNET.ts.net.key"
```
