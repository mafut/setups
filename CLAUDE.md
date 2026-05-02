# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Personal provisioning scripts for Ubuntu cloud VMs (Azure / AWS / VPS) and Raspberry Pi hosts. Each top-level folder is a self-contained target invoked as `sudo ./<dir>/setup.sh` from a fresh box. Scripts are idempotent-ish (re-run to upgrade) but **not** runnable on a developer laptop — they edit `/etc/...`, install packages, and rewrite system configs.

The parent directory `/home/kotai/` also hosts the unrelated `yonabe` EC site (see `/home/kotai/CLAUDE.md`). This repo is referenced from there as the LAMP host that runs yonabe in production-like mode, but the two are not coupled — yonabe edits don't belong here.

## Targets

| Path | Purpose |
|---|---|
| [lamp/setup.sh](lamp/setup.sh) | The big one. Provisions a multi-user LAMP host with code-server, phpMyAdmin, pimp-my-log, oauth2-proxy, Mackerel agent, logrotate, logwatch. **All other directories are smaller in scope.** |
| [proxy/setup.sh](proxy/setup.sh) | Squid HTTP(S) proxy for bypassing geo-restrictions on Japanese streaming services. Two flavors: `ubuntu` (own host) and `synology` (inside a Docker container on a NAS). |
| [onedrive/setup.sh](onedrive/setup.sh), [onedrive/daemon.sh](onedrive/daemon.sh) | Install `abraunegg/onedrive` with a hardcoded `download-only` config (Notes/, Backup/), then enable per-user systemd unit. |
| [rpi-common/setup.sh](rpi-common/setup.sh) | **Base script** sourced by every other rpi-* target. Sets up swap-off, ramdisk for `/var/log` + `/tmp`, ufw, sshd (key-only), tmux/tpm, bash aliases. |
| [rpi-hackberry/setup.sh](rpi-hackberry/setup.sh) | Just sources rpi-common (the device-specific config is in `config.txt`/keymap files in this dir). |
| [rpi-nas/setup.sh](rpi-nas/setup.sh) | Sources rpi-common, then Waveshare 2-inch LCD framebuffer copy via `fbcp`. |
| [rpi-colorberry/setup.sh](rpi-colorberry/setup.sh) | Sources rpi-common, builds out-of-tree DRM + keyboard kernel modules from bundled zips for the Beepberry/Colorberry handheld, configures sharp-drm dither aliases. |
| [tv/setup.sh](tv/setup.sh) | TV recorder: PX-S1UD ISDB-T tuner firmware + recdvb + libarib25 + Mirakurun + EPGStation under pm2. NFS-mounts `/mnt/records` from a Synology box (hardcoded `192.168.86.100`). |
| [ssh-pubkey/](ssh-pubkey/) | `*.pub` keys consumed by lamp + rpi-common; merged into the user's `authorized_keys`. `client/*.pub` is gitignored — yubikey keys are checked in. |

## How `lamp/setup.sh` is configured

Three config files are sourced **in order**, each overriding the prior:

1. `${DIR_SELF}/setup.sh.conf` — user/repo config (gitignored — see `.gitignore`)
2. `/etc/setup.sh.conf` — host-specific overrides
3. `${DIR_SELF}/setup.sh.default.conf` — defaults using `${VAR:=fallback}` (so it only fills holes)

The script refuses to run unless **both** the user and host config files exist; on first run create empties with `touch ./setup.sh.conf` and `sudo touch /etc/setup.sh.conf`. This is an intentional foot-gun guard — don't bypass it.

Flags (see the `getopts` block near the top):

- `-c <path>` — use one merged file for both user + host
- `-b` — `logrotate -f` before package install (rotate logs first so backups capture pre-upgrade state)
- `-r` — `systemctl disable --now` then re-enable services (full restart cycle)
- `-u` — `apt-get update && upgrade` (implies `-b`)

After config load the script prints a config summary tree and waits for Enter — read it before pressing return.

## Architecture of the LAMP host

The trickiest part of `lamp/setup.sh` is the front-door layout. The script sets up **two web servers cooperating**:

```
:80   apache (default vhost)        → certbot + http→https redirect
:443  nginx (default + user vhost)  → terminates TLS
        ├─ /oauth2/...     → oauth2-proxy :PORT_OAUTH2PROXY
        ├─ /vscode/        → code-server :PORT_VSCODE   (gated by oauth2-proxy auth_request)
        ├─ /tools/         → apache :8888               (phpMyAdmin + pimp-my-log, gated)
        └─ /               → apache :PORT_HTTPS         (the user's PHP app)
:8888 apache (tools vhost)          → DOCPATH_TOOLS, only reachable via nginx /tools/
:PORT_HTTPS apache (user vhost)     → DOCPATH_HTTPS, only reachable via nginx /
:1080 / :1081                       → mod_status / stub_status for Mackerel
```

`ufw` explicitly **denies** `PORT_HTTPS`, `PORT_VSCODE`, `PORT_OAUTH2PROXY`, `8888`, and the Mackerel ports — they exist only on the loopback face for nginx to proxy to. Don't open them.

Why apache+nginx instead of one of them? nginx handles TLS, websockets (for code-server), and the oauth2 `auth_request` subrequest cleanly; apache stays in front of PHP because the script keeps **multiple PHP versions** installed (`PHP_VERS` array — currently `8.2 8.1 7.4 7.3 5.6`) with `mod_php` and switches the active one via `update-alternatives` + `a2enmod php${PHP_VER}`. Yonabe's CodeIgniter 3 codebase pins old PHP, hence the 5.6 still in the list.

OAuth2 gating is wired by the `nginx_oauth2proxy` heredoc that's interpolated into each protected `location {}`. If `OAUTH2_CLIENT`/`OAUTH2_SECRET` are unset, the `oauth2-proxy` block is skipped entirely, but `/vscode/` and `/tools/` can still be exposed (then they're protected only by their own login pages — code-server's `password` and phpMyAdmin's cookie auth).

## Code-server settings

A long sequence of `jq '...' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"` lines patches `~/.config/code-server/.../settings.json`. When adding/changing a VSCode setting, follow the same one-line-per-key pattern — the final `jq --sort-keys` line re-sorts everything. Extensions come from two sources:

- `CODESERVER_EXTS` array (marketplace IDs, installed via `code-server --install-extension`)
- `lamp/vsix/*.vsix` (bundled VSIXes for extensions removed from the OpenVSX/marketplace mirror — see the `installed()` helper that skips already-installed ones)

## SSH key collection (lamp + rpi-common)

Both scripts walk `ssh-pubkey/yubikey/` and `ssh-pubkey/client/` for `*.pub` files and concatenate them into `authorized_keys`. Yubikey-resident pubs are committed; client pubs are gitignored. To grant a new client SSH access to a host, drop the `.pub` into `ssh-pubkey/client/` and re-run setup. **Don't add keys to `authorized_keys` directly** — the script overwrites it.

The user's `~/.ssh/config` gets `PKCS11Provider /usr/lib/.../libykcs11.so` so YubiKeys work for outbound SSH; aliases `sshyk`/`scpyk` are added to `.bash_aliases`.

## RPi target composition pattern

Each `rpi-*/setup.sh` is a thin wrapper:

```bash
DIR_COMMON=$(cd $(dirname $0); cd ../rpi-common/; pwd)
source ${DIR_COMMON}/setup.sh
# ... device-specific work ...
```

Because rpi-common is `source`d (not exec'd), all its variables (`USERNAME`, `DIR_SELF`, `FILE_BASHALIASES`, `FILE_TMUXCONFIG`, `FILE_LIBYKCS11`, etc.) are visible to the wrapper, which then **appends** to `.bash_aliases` or **overrides** `.tmux.conf`. `DIR_SELF` after sourcing still points at the wrapper's directory because rpi-common is sourced — keep this in mind when referencing bundled files (e.g. colorberry's `keyboard.map`, `*.zip` driver bundles) by `${DIR_SELF}`.

## Cron jobs

The lamp script writes `setup.sh.crontab.conf` from the `CRON_JOBS` array and installs it via `crontab -u ${USERNAME}`. The committed `setup.sh.crontab.conf` is the rendered output from the last run — it reflects yonabe's current sync schedule (pull `setups`, `yonabe`, force-reset `yonabe-content`, then copy banner/item/member into yonabe/img). Edits should be made to `CRON_JOBS` in `setup.sh.conf`, not to the rendered `.crontab.conf`.

## Things that look wrong but aren't

- `lamp/setup.sh` runs `usermod -g ${USERNAME} ${USERNAME}` to **reset** the primary group — this is intentional cleanup for users that were created with mismatched primary groups.
- `[ ! -e ${SSH_AUTHKEYS_TMP} ]` then `sudo -u ${USERNAME} echo -n >${SSH_AUTHKEYS_TMP}` truncates the temp file even when it exists — that's the point, the script wants a clean slate each run.
- `for vsix in ${DIR_SELF}/vsix/*.vsix` will literally iterate `*.vsix` if the dir is empty (no nullglob). The `installed()` helper covers it because `extname` from a literal glob won't match anything installed and the loop tries `code-server --install-extension '...*.vsix'` which fails benignly. Don't "fix" this without testing.
- The `-cu` / `-ch` flags in `getopts "rubc:"` aren't actually parsed (the spec only declares `-c` taking an arg); the `cu)` / `ch)` cases are dead code. Help text mentions them — leave them or fix both spec and help, but don't half-fix.
