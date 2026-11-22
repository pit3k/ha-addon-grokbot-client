# Changelog

## 0.1.0

- First release of the Grok Bot client app.
- Runs `grokbot-tunnel connect` and shows its sign-in link in the ingress panel, with a QR code from `qrencode` and a Home Assistant notification.
- Sign in does nothing while a session exists. Only Sign out removes the login.
- While waiting, the panel shows the status, the QR code, and the sign-in link. While connected, it shows the status, the account, and Sign out.
- Downloads the latest client on startup, checks `checksums.txt` when the release publishes one, and keeps the previous binary if the download fails.
- Maps the Home Assistant configuration, every app's public config, share, and backup for writing, and SSL for reading.
- Supervisor role is manager. The Home Assistant API is enabled. The login in `/data` is included in backups.
- The image health check is the panel status page. Boot is automatic and the host network is left off, which are the Home Assistant defaults, so those keys are not repeated in `config.yaml`.
