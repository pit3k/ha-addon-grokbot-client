# Grok Bot client

This app runs [grokbot-tunnel](https://github.com/exa-pub/grokbot-tunnel) so a Grok Bot agent can work on this Home Assistant system: configuration files, app configuration, backups, and the `ha` command. It stays running and uses little besides that client.

The client is an independent project. It is not affiliated with or endorsed by xAI.

## Install

1. Add this repository to Home Assistant. Use the badge in the repository README, or go to **Settings → Apps → Add-on store → ⋮ → Repositories** and paste:

   `https://github.com/pit3k/ha-addon-grokbot-client`

2. Install **Grok Bot client** and start it. Start on boot is on.

3. Open **Grok Bot** in the sidebar. Only administrators see that panel.

4. When the page says **Waiting for sign-in**, use **Click to sign in**, copy the link, or scan the QR code. Approve the request in the browser. You can use a phone.

5. The page changes to **Connected as ha** (or the computer name you set). The same computer shows up in Grok Bot.

A notification with the same link appears until sign-in finishes. If the panel is not open yet, the link is also written once to the app log.

Home Assistant OS from 2026.7 or later is required. The folder map uses the current names (`homeassistant_config`, `all_app_configs`).

Boot is automatic and the app does not use the host network. Those are the Home Assistant defaults, so `config.yaml` does not repeat them. The panel listens on port 8099, also the default. The image health check requests `http://127.0.0.1:8099/api/status`. The sidebar entry is limited to administrators, which is the default for an ingress panel.

## Sign out

While the page is waiting, it shows the status, the QR code, and the sign-in link. The client prepares that link on its own. While connected, the page shows the status, the account, and **Sign out**. Sign out removes the saved login and a new link is shown. The client binary stays installed.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| Permission | `always` | `always` runs every action the agent requests. `ask` runs only actions approved in Grok Bot. |
| Computer name | `ha` | Name of this system in Grok Bot, at most 100 characters. |
| Update the client automatically | on | On startup, download a newer grokbot-tunnel release. A failed download keeps the last client that ran. |
| Log level | `info` | `debug` runs the client with `--debug` and forwards every line it prints, including each raw request. `info` forwards the normal client log, which already names each request. `warning` and `error` do not forward that log. Tokens are left out at every level. |

`ask` has no terminal in this app. An action that Grok Bot does not approve is refused. It does not wait for a keypress. With `always`, the agent runs commands without asking.

Changing options restarts the app.

## What the agent can reach

Inside the container:

| Path | Access | Contents |
| --- | --- | --- |
| `/homeassistant` | read-write | Home Assistant configuration |
| `/app_configs` | read-write | Public configuration of every app |
| `/share` | read-write | Shared files |
| `/backup` | read-write | Backups |
| `/ssl` | read-only | Certificates |
| `/data` | read-write | This app's data, including the login |

`ha` talks to the Supervisor. The app's role is **manager**, so it can install, start, stop, and update apps, and restart Home Assistant Core. The Home Assistant API is enabled as well, through `http://supervisor/core/api`.

Commands run as root in this container. File tools are allowed anywhere under `/`. A shell command is not limited to one directory: it can read anything the container can read, including the login files under `/data/.grok/bot-tunnel`.

The same notes are in `/usr/share/grokbot/LAYOUT.txt` for the agent.

## Security

- The app is not privileged, has no Docker socket, and does not use the host network. It is not full hardware access.
- Manager can restart and update Home Assistant and its apps. It does not get the host controls of the admin role.
- The login is stored unencrypted in `/data/.grok/bot-tunnel`, mode `0700`, and **is included in backups** of this app. Treat those backups as secrets. This is deliberate so a restore comes back signed in.
- The app log never includes access tokens or refresh tokens. It does include the sign-in link, once, so you can open it without the panel.
- The sign-in link lets whoever opens it finish that sign-in. The panel is limited to Home Assistant administrators, and the notification is visible to users who can see notifications.
- Only one client runs at a time. Signing out stops it and starts a new sign-in.

## Updates

The app image is versioned with `config.yaml`. The grokbot-tunnel binary inside `/data` updates on its own when **Update the client automatically** is on, at the next start of the client. Turn the option off to keep the installed binary. The first start still downloads it if it is missing.

Checksums are checked when the release publishes `checksums.txt`. If the download or the checksum fails, the previous working binary is left in place.
