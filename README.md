# Grok Bot client for Home Assistant

Always-on [grokbot-tunnel](https://github.com/exa-pub/grokbot-tunnel) for Home Assistant. After you sign in from the sidebar, a Grok Bot agent can work on this system.

[![Open your Home Assistant instance and show the add repository dialog with this repository filled in.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fpit3k%2Fha-addon-grokbot-client)

Installation, options, and security are in [grokbot_client/DOCS.md](grokbot_client/DOCS.md).

## Develop

```sh
tests/run-all.sh
tests/smoke.sh
```

`tests/run-all.sh` runs ShellCheck and the script tests. `tests/smoke.sh` builds the image and checks that a missing login becomes **Waiting for sign-in**. GitHub Actions lints the app config, runs those script tests, builds `amd64` and `aarch64`, and runs the smoke test on amd64.
