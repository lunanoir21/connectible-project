# Daemon persistent-service design (T-208)

Goal: `connectibled` should be able to run as a user-level background
service that survives logout/reboot/crash, without requiring root and
without depending on any specific desktop environment's session
manager (must work identically under GNOME, KDE, and a bare
Hyprland/wlroots session with no DE session manager at all).

## Mechanism: systemd user unit

A systemd **user** unit (not system-wide) is the right fit: no root
required, starts/stops with the user's login session (or lingers past
it via `loginctl enable-linger` if the user wants it running even when
logged out), and is available on effectively every mainstream Linux
distribution -- including Arch/CachyOS (this dev machine), which is
systemd-based despite Hyprland having no systemd dependency itself.

Unit file location (implementation target for T-1201):
`daemon/packaging/connectibled.service`, installed to
`~/.config/systemd/user/connectibled.service`.

Draft contents:

```ini
[Unit]
Description=Connectible device-sync daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/bin/connectibled
Restart=on-failure
RestartSec=2
# Reasonable resource ceiling given RULES.md's <30MB idle-RSS target;
# generous headroom for active transfers.
MemoryMax=512M

[Install]
WantedBy=default.target
```

Notes:
- `ExecStart` uses `%h` (systemd specifier for the user's home
  directory) so the unit is portable across machines without templating.
  Installation places (or symlinks) the release binary at
  `~/.local/bin/connectibled`.
- `Restart=on-failure` covers crash recovery; it deliberately does not
  use `Restart=always`, since a daemon that fails immediately on every
  start (e.g. port already in use) should not busy-loop-restart forever
  -- `RestartSec=2` plus systemd's built-in start-rate limiting
  (`StartLimitIntervalSec`/`StartLimitBurst`, left at systemd defaults)
  already prevents that.
- Logs go to the user's systemd journal by default (`journalctl --user
  -u connectibled`); no separate log-file configuration needed, and
  this works identically regardless of desktop environment.
- No `WantedBy=graphical-session.target` dependency -- the daemon does
  not need a graphical session at all (only the desktop UI does), so it
  should be startable in a headless/SSH context too.

## Enable/disable flow (for T-1001 docs + T-1201 implementation)

```sh
mkdir -p ~/.config/systemd/user
cp daemon/packaging/connectibled.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now connectibled
# Optional: keep running after the user logs out entirely.
loginctl enable-linger "$USER"
```

## Non-goals for this design

- No system-wide (root) unit -- per-user only, consistent with the
  daemon's per-user config/data directories (XDG data dir).
- No Windows/macOS service equivalent in this design pass; out of
  scope for the current Linux-only MVP per PLAN.md's non-goals.
