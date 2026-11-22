# Home Assistant App: Grok Bot client

Runs grokbot-tunnel so a Grok Bot agent can use this Home Assistant system.

![Supports aarch64 Architecture][aarch64-shield] ![Supports amd64 Architecture][amd64-shield]

## About

This app runs [grokbot-tunnel] in Home Assistant and keeps a tunnel open to Grok Bot, so your Grok Bot agent can work on this Home Assistant system as one of its computers.

Through the tunnel, the agent can read and change your Home Assistant configuration, such as automations, scripts, dashboards and YAML files. It can also install, start, stop and update apps, restart Home Assistant, and use backups and the `ha` command. You decide in Grok Bot whether it may do this on its own or must ask you first.

[grokbot-tunnel]: https://github.com/exa-pub/grokbot-tunnel
[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
