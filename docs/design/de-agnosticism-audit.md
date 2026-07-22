# Desktop-environment-agnosticism audit (T-804)

Repo-wide grep sweep across `daemon/src`, `desktop/src`,
`desktop/core/src`, `desktop/src-tauri/src`, `mobile/lib` for anything
that would silently assume KDE/Plasma or GNOME/Mutter specifically, or
couple to a DE-specific dbus/notification-daemon service name.

## Checked and clean

- **KDE/Plasma**: no code references (the only hits were "KDE Connect"
  in doc comments describing the project's inspiration, and an
  unrelated substring match in generated protobuf code).
- **GNOME/Mutter**: zero hits.
- **dbus / `org.freedesktop.Notifications` / `StatusNotifierItem` /
  `notify-send`**: zero hits. Notification mirroring (phone ->
  desktop) is implemented as an in-app React panel
  (`NotificationsPanel.tsx`), not native OS toast notifications, so
  there is no coupling to any DE's notification stack either way.
- **Tray backend**: `libayatana-appindicator3-dev` (declared in
  `desktop/src-tauri/Cargo.toml` via Tauri's `tray-icon` feature, and
  installed in `ci.yml`/`release.yml`) is the standard cross-desktop
  StatusNotifierItem/appindicator implementation used across
  GNOME-extension-based trays, KDE, and wlroots bars with a tray module
  (waybar, swaync) alike -- not a KDE-specific library.
- **`$XDG_CURRENT_DESKTOP`/`$DESKTOP_SESSION`**: never read anywhere
  in daemon or desktop code, so there is no DE-branching logic that
  could special-case or silently favor one desktop over another.
- **Wayland session detection**: both `daemon/src/clipboard/backend.rs`
  and `daemon/src/input/backend.rs`'s `is_wayland_session()` check
  `$XDG_SESSION_TYPE`/`$WAYLAND_DISPLAY` generically, not any
  compositor-specific env var.

## Known, intentional exceptions (not gaps)

- `daemon/src/clipboard/wayland_backend.rs` and
  `daemon/src/input/wayland_backend.rs` use `wlr-data-control`/
  `wlr-virtual-pointer`/`virtual-keyboard` -- wlroots-family protocols
  (Hyprland, Sway, etc). A compositor that implements neither these
  nor XWayland (e.g. GNOME/Mutter, which supports neither the wlr
  protocols nor -- unlike Hyprland -- disables neither by default, so
  XWayland-via-ydotool still works there) falls back gracefully to a
  missing-capability flag rather than a crash, per `detect_backend()`
  in both files. This is a real, documented feature gap (no
  Mutter-native protocol support exists for these operations at all,
  nothing this project can route around), not a DE-specific
  assumption bug.

## Conclusion

No remaining KDE/GNOME-specific assumption found. The project's stated
goal ("not KDE-dependent, equally stable on Hyprland") holds across
the codebase as of this audit (2026-07-14).
