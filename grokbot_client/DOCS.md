# Grok Bot client

This app runs [grokbot-tunnel](https://github.com/exa-pub/grokbot-tunnel) so a Grok Bot agent can work on this Home Assistant system: configuration files, app configuration, backups, and the `ha` command. It stays running and uses little besides that client.

The client is an independent project. It is not affiliated with or endorsed by xAI.

## Install

1. Add this repository to Home Assistant. Use the badge in the repository README, or go to **Settings → Apps → Add-on store → ⋮ → Repositories** and paste:

   `https://github.com/pit3k/ha-addon-grokbot-client`

2. Install **Grok Bot client** and start it. Start on boot is on.

3. On the app's Info page, click **Open Web UI**. The page is not in the sidebar. Only administrators can open it.

4. On that page, before you sign in, the execution policy is **Always allow**. Choose **Ask every time** or **Never allow** to change it. Then use **Click to sign in**, copy the link, or scan the QR code. Approve the request in the browser. You can use a phone. The same link is in the app log.

5. The page changes to **Connected as homeassistant** (or the computer name you set). The same computer shows up in Grok Bot.

The sign-in link is also written once to the app log.

Home Assistant OS from 2026.7 or later is required. The folder map uses the current names (`homeassistant_config`, `all_app_configs`).

Boot is automatic and the app does not use the host network. Those are the Home Assistant defaults, so `config.yaml` does not repeat them. The panel listens on port 8099, also the default, and accepts only `172.30.32.2` (Home Assistant ingress) and `127.0.0.1` (the image health check, `http://127.0.0.1:8099/cgi-bin/status`). It is not shown in the sidebar. **Open Web UI** on the Info page opens it.

## Sign out

While the client is not connected, the page shows the execution policy, including while it still says **Starting**. While it is waiting, it also shows the QR code and the sign-in link. The client prepares that link on its own. While connected, the page shows the status, the account, and **Sign out**. Sign out removes the saved login and a new link is shown. The client binary stays installed.

## Options

The app runs `grokbot-tunnel connect --label <label> --root /`. The first connect after a sign-in also passes `--permission` from the execution policy. **Always allow** is the default.

| Option | Default | Meaning |
| --- | --- | --- |
| Computer name | `homeassistant` | Name of this system in Grok Bot, at most 100 characters. |
| Update the client automatically | on | On startup, download a newer grokbot-tunnel release. A failed download keeps the last client that ran. |
| Log level | `info` | `debug` runs the client with `--debug`, so it prints each raw request. The client's output goes to the app log as it is printed. |

Changing options restarts the app.

## What the agent can reach

Inside the container:

| Path | Access | Contents |
| --- | --- | --- |
| `/homeassistant` | read-write | Home Assistant configuration |
| `/config` | read-write | This app's own public configuration folder, visible in other apps like Code Editor |
| `/app_configs` | read-only | Public configuration of every app |
| `/share` | read-write | Shared files |
| `/media` | read-write | Media files |
| `/local_apps` | read-write | Local apps folder, for developing and testing apps |
| `/backup` | read-only | Backups |
| `/data` | read-write | This app's data, including the login |

`ha` talks to the Supervisor. The app's role is **manager**, so it can install, start, stop, and update apps, and restart Home Assistant Core. The Home Assistant API is enabled as well, through `http://supervisor/core/api`.

Commands run as root in this container. File tools are allowed anywhere under `/`. A shell command is not limited to one directory: it can read anything the container can read, including the login files under `/data/.grok/bot-tunnel`.

The same notes are in `/usr/share/grokbot/LAYOUT.txt` for the agent.

## Approvals

On the page, before or during sign-in, the execution policy says what this computer may do. **Always allow** is selected. You can change it. The choice applies only to this sign-in. The first `connect` after that sign-in runs with `--permission always`, `--permission ask`, or `--permission never`. Later starts, including a restart of the app, run `connect` without `--permission`, so they keep whatever is set in Grok Bot.

Change it later in Grok Bot under **Settings → Computer**. Sign out on this page and sign in again to pick again. The page keeps the last choice in `/data/permission`.

- **Always allow**: Auto-review in Grok Bot checks each action first. You set it up under **Settings → General → Auto-review** and **Auto-review rules**. An action that Auto-review blocks never reaches Home Assistant. The agent is told why and may ask you to approve it. The approval card appears in Grok Bot, in the chat of that agent. Every other action runs without asking.
- **Ask every time**: Grok Bot shows an approval card in the agent's chat before each action. Nothing runs until you approve it.
- **Never allow**: every action is refused.

Home Assistant never asks you anything.

## Security

- The app is not privileged, has no Docker socket, and does not use the host network. It is not full hardware access.
- Manager can restart and update Home Assistant and its apps. It does not get the host controls of the admin role.
- The login is stored unencrypted in `/data/.grok/bot-tunnel`, mode `0700`, and **is included in backups** of this app. Treat those backups as secrets. This is deliberate so a restore comes back signed in.
- The app log includes the sign-in link once, so you can open it without the panel. The client's own output is written to that log as the client prints it.
- The sign-in link lets whoever opens it finish that sign-in. The page is not in the sidebar. Open it with **Open Web UI** on the app's Info page. Only administrators can open that page.
- Only one client runs at a time. Signing out stops it and starts a new sign-in.

## Updates

The app image is versioned with `config.yaml`. The grokbot-tunnel binary inside `/data` updates on its own when **Update the client automatically** is on, at the next start of the client. Turn the option off to keep the installed binary. The first start still downloads it if it is missing.

Checksums are checked when the release publishes `checksums.txt`. If the download or the checksum fails, the previous working binary is left in place.
