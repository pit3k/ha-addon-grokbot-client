#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname -- "$0")/.." && pwd)"
cd "$root"

if ! command -v shellcheck >/dev/null 2>&1; then
  printf '%s\n' "shellcheck is required" >&2
  exit 1
fi

shellcheck -s bash -S warning \
  grokbot_client/rootfs/usr/lib/grokbot/run.sh \
  grokbot_client/rootfs/etc/s6-overlay/s6-rc.d/init-grokbot/run \
  grokbot_client/rootfs/etc/s6-overlay/s6-rc.d/grokbot/run \
  grokbot_client/rootfs/etc/s6-overlay/s6-rc.d/grokbot/finish \
  grokbot_client/rootfs/etc/s6-overlay/s6-rc.d/panel/run \
  grokbot_client/rootfs/etc/s6-overlay/s6-rc.d/panel/finish \
  grokbot_client/rootfs/opt/panel/cgi-bin/status \
  tests/test-update.sh \
  tests/test-run.sh \
  tests/test-panel.sh \
  tests/smoke.sh \
  tests/run-all.sh \
  tests/fixtures/fake-grokbot-tunnel

tests/test-update.sh
tests/test-run.sh
tests/test-panel.sh

printf '%s\n' "all host tests passed"
