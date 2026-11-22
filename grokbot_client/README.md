# Home Assistant App: Grok Bot client

Runs grokbot-tunnel so a Grok Bot agent can use this Home Assistant system.

![Supports aarch64 Architecture][aarch64-shield] ![Supports amd64 Architecture][amd64-shield]

## About

This app runs [grokbot-tunnel] in Home Assistant and keeps a tunnel open to Grok Bot. On the app's Info page, click **Open Web UI** and sign in with the link or the QR code. The page is not in the sidebar. You choose in Grok Bot whether the agent runs every requested action, only actions you approve, or none. The agent can read and change the Home Assistant configuration, this app's configuration, shared files, media, and local apps. It can read other apps' configuration and backups, and it can run commands here, including `ha`.

[grokbot-tunnel]: https://github.com/exa-pub/grokbot-tunnel
[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
