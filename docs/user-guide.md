# Connectible — User Guide

How to pair your devices and use every sync feature Connectible has:
clipboard (text and images), file transfer, remote input, and
notification mirroring. If you're looking to build or hack on
Connectible instead, see [developer-guide.md](developer-guide.md).

This guide describes the desktop app (Tauri, Linux) and the mobile app
(Flutter, Android) as they behave today. A rendered, browsable version
of this same content is published at [the project's GitHub Pages
guide](guide/).

## Contents

- [First-time pairing](#first-time-pairing)
- [Clipboard sync](#clipboard-sync)
- [Sending and receiving files](#sending-and-receiving-files)
- [Remote input](#remote-input)
- [Notification mirroring](#notification-mirroring)
- [Troubleshooting (System Doctor)](#troubleshooting-system-doctor)

## First-time pairing

Pairing establishes a TLS 1.3 connection between exactly two devices
and has each side remember (pin) the other's certificate, so future
connections need no PIN. Either device can start the process — desktop
and mobile are symmetric peers, not a client/server pair — and there
are three ways to get there depending on your network.

### The default path: discover and tap

Both apps advertise themselves and browse for each other over mDNS
(`_connectible._tcp`) as soon as they're running. No setup is needed
for this to work on a typical home Wi-Fi network.

1. Open Connectible on both devices. Each one appears in the other's
   device list within a few seconds ("Nearby" on desktop; the Home
   screen on mobile).
2. Tap the device you want to pair with.
3. Whichever device you tapped from is the requester; the other side
   shows a random 6-digit PIN, valid for 30 seconds.
4. Type the PIN into the requester's prompt. Three wrong attempts
   invalidate it early — either way, a failed/expired PIN just means
   starting over from step 2, not retrying the same code.
5. Once confirmed, both sides save the pairing (and each other's
   certificate fingerprint) and won't ask for a PIN again for this
   pair. Losing the pairing (uninstall, "Forget device") means
   repeating the ceremony.

### QR code (fastest for a new phone)

Scanning skips typing the PIN by hand entirely:

1. On desktop: **Settings → Pair a phone → Show code**. A QR code
   appears alongside the same PIN as text (in case you'd rather type
   it, or the camera can't focus). It's valid for 30 seconds; a
   **regenerate** control appears once it expires.
2. On mobile: from the Home screen's pairing entry point, tap **Pair
   Desktop**, then scan the code shown on the computer's screen.
3. The two devices pair immediately once the scan succeeds — no PIN
   typing involved.

Today this direction only goes one way: desktop shows the code, mobile
scans it. For the reverse (phone shows something for desktop to read),
use discovery-and-tap or manual connect instead.

### Manual connect by address (no mDNS)

Some networks block multicast traffic (guest Wi-Fi, separate VLANs,
some routers by default), so mDNS discovery never finds the other
device even though both are reachable. Either device can fall back to
typing an address directly:

1. On the device you're connecting *from*, open **Connect by
   address** (next to the device list on both platforms).
2. Enter the *other* device's LAN IP address and port (default
   `58231`) — both apps show their own address on this same screen, so
   read it off there rather than guessing.
3. Submit. This behaves exactly like tapping a discovered device: a
   PIN appears on the responder, you enter it on the requester, and
   pairing completes the same way.

## Clipboard sync

Once two devices are paired and **Clipboard sync** is on (a toggle in
Settings on both platforms), copying on one device makes the same
content available to paste on the other, automatically — no separate
"send" step needed for the common case.

- **Text** works exactly like a shared clipboard: copy on either side,
  paste on the other, no size limit worth mentioning.
- **Images** (`image/png`) sync the same way — copy a screenshot or an
  image on one device, paste it on the other. There's a **10 MB cap**
  per item; anything larger is never sent, and the clipboard history
  shows *"Too large to sync"* with the actual size instead of silently
  doing nothing, so you know why it didn't arrive.
- Whatever synced (text or image) appears in the **clipboard
  history** on both platforms — the last 20 entries, newest first —
  with a **Copy** action per entry to put that specific item back on
  the OS clipboard.
- A device never re-sends content it just *received* back to its
  sender — copying, receiving, and the OS reporting that same content
  back on the next poll doesn't create a loop.

Mobile has two independent toggles under **Settings → Clipboard sync**
worth knowing about if sync seems one-directional:

| Toggle | Off means |
|---|---|
| **Auto-send copies from this phone** | Things you copy on the phone stop reaching the paired desktop, but incoming content from the desktop still arrives and applies here. |
| **Auto-apply incoming to clipboard** | Incoming content still shows up in history, but is not written to the phone's OS clipboard — so pasting on the phone won't pick it up until you use its history's Copy action manually. |

Desktop has a single **Clipboard sync** toggle covering both
directions at once; there's no separate send/apply split there.

## Sending and receiving files

There is exactly one transfer mechanism, and it resumes: a dedicated
upload stream (not the general sync channel) that verifies the whole
file's SHA-256 hash before keeping it, and picks up from the last byte
the receiver already has if a transfer is interrupted (Wi-Fi drop,
app backgrounded, etc.) rather than starting over.

**Sending:** open **Transfers** (desktop) or the transfers tab
(mobile), tap **Send file**, and pick a file from the picker. Progress
shows live; a transfer can be canceled mid-flight (a distinct
"Canceled" state, not treated as a failure).

**Receiving:**

- **Desktop** saves incoming files straight to your OS Downloads
  folder by default. **Settings → Received files** lets you point it
  at a different folder instead, and **Open** jumps straight to the
  save location.
- **Mobile** saves incoming files into the app's own private storage
  first (Android restricts where apps can write directly), then offers
  a **Save to...** action per file that copies it anywhere you pick via
  the system file picker — so a received file isn't stuck inside the
  app unless you leave it there.
- Mobile also has a **Discoverable** toggle (Home screen) that must be
  on for other devices to find and pair with it in the first place, and
  keeps the phone reachable for incoming files/sync in the background
  via a foreground service (you'll see a persistent notification while
  it's on — that's Android's requirement for a background service to
  keep running, not a bug).

**History:** every transfer, both directions, is kept after the fact —
desktop persists up to 500 records across restarts, mobile up to 200 —
so you can see what was sent/received even after closing the app.

## Remote input

One device can drive another's mouse and keyboard over the same
encrypted connection — practical for controlling a desktop from across
the room using just the phone.

On mobile, open **Remote control** (paired to a desktop first). It
behaves like a touchpad:

- **Drag** to move the pointer.
- **Tap** to click; **double-tap** for a double-click.
- **Two fingers** to scroll.
- A row of buttons below covers **Left**/**Right** click and a small
  virtual keyboard (arrow keys, Enter, Backspace, Tab, Shift, Ctrl,
  Alt) for the keys a touchpad gesture can't express.

On the desktop side, this is entirely receive-only: **Settings →
Remote input** has an **Accept remote input** toggle. Turning it off
makes the desktop ignore incoming input events without disconnecting
anything else — clipboard and file transfer keep working.

**Whether this works at all depends on what's running the desktop
session**, not on anything you configure in the app:

- **Native Wayland compositors that implement the wlroots input
  protocols** (Hyprland, Sway, and similar) — works out of the box, no
  extra setup.
- **X11, or Wayland via XWayland** — needs `ydotool`/`ydotoold`
  installed and running (see the main [README](../README.md#remote-input-and-clipboard-x11-vs-wayland)
  for the one-time udev rule this needs to run without root).
- **A compositor that supports neither** (most non-wlroots Wayland
  compositors, e.g. GNOME/Mutter, without XWayland) — remote input
  simply isn't offered as a capability; the paired phone's Remote
  control screen shows "no device available" rather than a broken
  touchpad. Run **System Doctor**'s "Remote-input injection" check
  (see below) to see exactly what was detected on this machine.

## Notification mirroring

Once granted, phone notifications appear on the desktop the moment
they land, and the reverse holds for dismissal: **dismissing a
notification on either device clears it on both** — you won't keep
seeing a phone notification mirrored on the desktop after you've
already cleared it on the phone (or vice versa).

Setup is one-time, on the phone:

1. **Settings → Notification mirroring → Grant access.** Android will
   ask you to enable Connectible under its system Notification Access
   settings.
2. Once granted, notifications the phone receives show up under the
   desktop's **Notifications** panel automatically, no further
   configuration needed.
3. **Manage** (same settings row) jumps back to Android's notification
   access settings if you ever want to revoke it.

This is mirroring, not remote control of notifications beyond
dismissal — you can't reply to a message or trigger a notification
action from the desktop.

## Troubleshooting (System Doctor)

Both apps include a built-in **System Doctor** (**Settings → System
Doctor**) that runs a battery of local checks and explains, in plain
language, what's wrong and what to do about it — the same underlying
checks whether you open it from the desktop or the phone side of a
pair. **Copy report** puts a full text summary on your clipboard,
useful when asking for help.

The checks are grouped into four categories:

### Environment & storage

| Check | What it verifies | If it warns/errors |
|---|---|---|
| Daemon version | Which build is running | Informational only |
| Data / TLS / Transfers directory writable | The daemon's own storage locations exist and are writable | Fix the directory's ownership/permissions, or check the parent path exists |
| Download directory writable | Where received files are about to be saved | Same as above, for whichever folder Settings currently points at |
| Free disk space for incoming files | Free space at the download location (warns under 512 MB) | Free up space there, or point the download directory at a volume with more room |
| Database encryption key source | Where the key that encrypts paired-device certificate fingerprints came from (OS keyring, an explicit override file, or a local fallback file) | A fallback file is expected on a headless setup with no session bus; on a normal desktop session, check that a keyring service (GNOME Keyring, KWallet, ...) is actually running if you expected one |

### Network & transport

| Check | What it verifies | If it warns/errors |
|---|---|---|
| LAN address | This device has a real (non-loopback) network address | Connect to the same Wi-Fi/LAN as the devices you want to pair with |
| Daemon port | The daemon's gRPC port is actually reachable on localhost | Start the daemon, or check a firewall isn't blocking it |
| TLS certificate | The certificate/key pair the daemon needs exist on disk | Start the daemon once — it generates a self-signed cert/key automatically on first run |

### Pairing & devices

| Check | What it verifies | If it warns/errors |
|---|---|---|
| Paired devices | The paired-device database is readable, and how many peers have a pinned certificate fingerprint yet | An unreadable database usually means corruption — re-pairing rebuilds it; devices paired before certificate pinning existed pin automatically on their next connect, which is expected, not an error |

### Feature backends

| Check | What it verifies | If it warns/errors |
|---|---|---|
| Clipboard/input display server | Whether a graphical session (`X11`/`WAYLAND_DISPLAY`) was detected at all | Clipboard and remote input both need a real graphical session — run the daemon inside one |
| Received-files opener | Whether any app is available to open a received file (`xdg-open`, `gio`, or a file manager) | Install `xdg-utils` so "Open" works from the transfers list |
| Remote-input injection | Which input-injection backend is available: native on X11, `ydotool` on Wayland | Install `ydotool` and make sure `ydotoold` is running for remote input on Wayland |
| Incomplete transfers | Leftover `.part` files from interrupted transfers sitting in the transfers directory | Not an error — these are what makes resuming a dropped transfer possible; delete them yourself if you don't intend to resume and want the space back |

If a check doesn't explain your specific problem, the two things worth
checking manually before anything else are the same two the
[README's firewall section](../README.md#firewall--network-requirements)
calls out: TCP port `58231` (or whatever `CONNECTIBLE_PORT` is set to)
and UDP `5353` (mDNS) both need to be allowed through any local
firewall.
