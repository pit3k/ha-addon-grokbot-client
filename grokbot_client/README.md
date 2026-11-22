# Home Assistant App: Grok Bot client

Runs grokbot-tunnel so a Grok Bot agent can use this Home Assistant system.

![Supports aarch64 Architecture][aarch64-shield] ![Supports amd64 Architecture][amd64-shield]

## About

This app runs [grokbot-tunnel] in Home Assistant and keeps a tunnel open to Grok Bot. Sign in from the panel with the link or the QR code. The permission option decides whether the agent runs every requested action or only actions you approve in Grok Bot. The agent can read and change the Home Assistant configuration, other apps' configuration, shared files, and backups, and it can run commands here, including `ha`.

[grokbot-tunnel]: https://github.com/exa-pub/grokbot-tunnel
[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
