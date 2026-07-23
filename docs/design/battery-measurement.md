# Real-device battery measurement protocol (Phase N, T-N1)

**Status: protocol only -- no measurement has been run yet.** This
file describes *how* to run T-N1 once a real Android phone is
available; it deliberately does not claim a result before one exists
(see `docs/design/perf-measurements.md` for the sibling file that
records actual results, once T-N1 produces one).

## Why this needs a real device

Everything else in the roadmap is verifiable in CI or a dev sandbox.
Battery drain from a background service (mDNS advertise, the
`ReceivingForegroundService`, periodic clipboard polling) is not --
emulators don't model real radio/CPU power draw, and there's no
substitute for letting an actual phone sit for a few hours. That's why
this phase stayed parked until explicitly requested (see this file's
own `## Why kept separate` note in `docs/TASKS.md`).

## What's being compared

Two runs, same phone, same duration, same starting battery level as
close as practical (both starting reasonably charged, e.g. 80-100%,
so neither run is skewed by non-linear drain near empty):

- **`baseline`** -- Connectible installed, but not paired to anything
  and **Discoverable** (Home screen toggle) turned **off**. This
  approximates "app installed, doing nothing" -- the foreground
  service (T-X36) should not even be running in this state.
- **`active`** -- Connectible paired to a desktop, **Discoverable**
  on (so the foreground service + mDNS advertise are running the
  whole time), with clipboard sync's auto-monitor left on so the
  2-second poll (`_defaultPollInterval` in `clipboard_model.dart`) is
  actually ticking. A few clipboard copies and at least one
  notification during the window are worth doing partway through, so
  the run reflects real usage rather than a session that's paired but
  silent the whole time.

Both runs need the phone **off USB** for the actual multi-hour
window -- being tethered changes charging behavior and makes the
battery-percentage delta meaningless. Use wireless `adb` for this:

```sh
# once, with the phone still on USB:
adb tcpip 5555
adb connect <phone-ip>:5555
# confirm it shows up, then unplug the USB cable:
adb devices
```

(Android 11+ also supports pairing over Wi-Fi without ever plugging
in via `adb pair`, if the phone's Developer Options exposes it --
either way works, the `battery_measure.sh` script below only needs
`adb devices` to show exactly one attached device by the time you run
it.)

## Running it

`mobile/tool/battery_measure.sh` wraps the two `adb`/`dumpsys` calls
that matter. It's two-phase, not a timed sleep -- the actual wait
(hours) happens in real life between `start` and `stop`, not inside
the script:

```sh
cd mobile
./tool/battery_measure.sh start baseline
# ...let the phone sit screen-off, untouched, for the agreed duration...
./tool/battery_measure.sh stop baseline

# set up the paired/Discoverable/active-sync state described above, then:
./tool/battery_measure.sh start active
# ...same duration, same otherwise-idle conditions...
./tool/battery_measure.sh stop active
```

Each `stop` prints a summary (`battery_drop_pct`) and writes two
files under `mobile/battery-results/` (gitignored -- this is
measurement scratch, not something to commit):

- `<label>.txt` -- start/end timestamps and battery percentage.
- `<label>-batterystats-raw.txt` -- the full `dumpsys batterystats
  io.connectible.mobile` dump for that window: per-app CPU time,
  wakelock hold time, wakeup-alarm count, and network (Wi-Fi) usage
  attributed specifically to Connectible. `baseline`'s file should be
  nearly empty (no wakelocks, negligible CPU); `active`'s is where to
  check the foreground service isn't holding a wakelock far longer
  than the sync work actually needs, or waking the CPU far more often
  than the 2-second poll interval would predict.

## Reading the result (T-N1's acceptance)

T-N1 asks for "a written measurement... showing the drain is within a
reasonable margin of the baseline, or a concrete follow-up task opened
if it isn't" -- not a hard pass/fail number, since there's no prior
baseline in this repo to compare against. As a starting reference
point: if `active`'s `battery_drop_pct` is more than roughly **2x**
`baseline`'s over the same window, that's worth treating as a signal
to open a follow-up investigation (most likely candidates: the
foreground service's wakelock duration, or the clipboard poll interval
being too aggressive) rather than shipping it as "fine." Under that,
record the numbers and close T-N1 -- background sync inherently costs
more than pure idle, and the goal is "not egregious," not "zero
measurable difference."

## Recording the result

Once both runs are done, append the numbers (both `battery_drop_pct`
values, the duration used, and the phone model/Android version) to
T-N1's entry in `docs/TASKS.md`, and attach or summarize anything
notable from the `-batterystats-raw.txt` files. If the result is a
pass, mark T-N1 `[x]`. If it's a fail, open a concrete new task for
the fix rather than leaving T-N1 open-ended.
