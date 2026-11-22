# Grok Bot client for Home Assistant

Always-on [grokbot-tunnel](https://github.com/exa-pub/grokbot-tunnel) for Home Assistant OS. After you sign in from the sidebar, a Grok Bot agent can edit configuration, app configs, and backups, and use the `ha` command. The app is not privileged and has no Docker socket.

[![Open your Home Assistant instance and show the add repository dialog with this repository filled in.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fpit3k%2Fha-addon-grokbot-client)

## Install on your system

1. Merge this repository to `main` and wait until the **CI** workflow has published the images. The tags match `version` in `grokbot_client/config.yaml` (`0.1.0` for this release):
   - `ghcr.io/pit3k/amd64-addon-grokbot-client:0.1.0`
   - `ghcr.io/pit3k/aarch64-addon-grokbot-client:0.1.0`
2. Make both GitHub Container Registry packages **public** (GitHub → Packages → the package → Package settings → Change visibility). Home Assistant cannot pull a private package. The workflow tries this once; if it cannot, the package stays private until you change it.
3. In Home Assistant, open the badge above, or go to **Settings → Apps → Add-on store → ⋮ → Repositories** and add:

   `https://github.com/pit3k/ha-addon-grokbot-client`

4. Install **Grok Bot client**, then start it.
5. Open **Grok Bot** in the sidebar (administrators only).
6. Use **Click to sign in**, copy the link, or scan the QR code, and approve the page in a browser. The panel switches to **Connected as homeassistant**.

A notification carries the same link until sign-in completes. The link is also printed once in the app log.

Full options, permission behavior, and security notes are in [grokbot_client/DOCS.md](grokbot_client/DOCS.md).

## What it runs

`grokbot-tunnel connect --permission <permission> --label <label> --root /`

When log level is `debug`, `--debug` is added. That is grokbot-tunnel's own switch for the raw request log.

`permission` is `always` (default) or `ask`. `label` defaults to `homeassistant`. The binary is installed in `/data/.local/bin`, with `HOME=/data`, so the login is stored in `/data/.grok/bot-tunnel` and is part of this app's backups.

On startup the app downloads the latest grokbot-tunnel release, verifies `checksums.txt` when that file is published, and keeps the previous binary if the download fails.

## Security, short version

The Supervisor role is **manager**. The agent can restart and update apps and Home Assistant Core, and it can call the Core API. Mapped folders are `/homeassistant`, `/config`, `/share`, `/media`, and `/local_apps` (read-write) and `/app_configs` and `/backup` (read-only). Commands run as root inside the app container, not as a privileged process on the host.

## Develop

```sh
tests/run-all.sh
tests/smoke.sh
```

`tests/smoke.sh` builds the app image and checks that the panel answers and that a missing login becomes **Waiting for sign-in** with a link. GitHub Actions lints the app config, runs ShellCheck, builds `amd64` and `aarch64`, and runs that smoke test.

Publishing an image is tied to `version` in `grokbot_client/config.yaml`. Bump that version and `CHANGELOG.md` together. CI pushes the new tag once and does not overwrite it.
