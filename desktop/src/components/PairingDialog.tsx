import { useEffect, useMemo, useRef, useState } from "react";
import { ipc } from "../lib/ipc";
import type { NearbyDevice, PairingPrompt } from "../lib/types";
import { errorCodeMessage } from "../lib/errors";
import { Icon } from "./Icon";
import { useT, type Translate } from "../i18n";

const PIN_TTL_SECONDS = 30;
// Below this many seconds remaining, the countdown shifts to the danger
// token as an urgency cue (T-703).
const PAIRING_URGENT_SECONDS = 10;

type Mode =
  | { role: "responder"; prompt: PairingPrompt }
  | { role: "requester"; device: NearbyDevice; pinExpiresAtMs: number };

interface PairingDialogProps {
  mode: Mode;
  onClose: () => void;
  onPaired: () => void;
}

/// Pairing dialog (T-036), both directions. A live "linking" header, a
/// smoothly draining countdown, animated per-digit PIN cells, a shake on
/// a rejected code, and a success beat before it closes.
export function PairingDialog({ mode, onClose, onPaired }: PairingDialogProps) {
  const t = useT();
  const expiryMs = mode.role === "responder" ? mode.prompt.pinExpiresAtMs : mode.pinExpiresAtMs;

  // A single high-resolution clock drives both the numeric label and the
  // continuous progress bar, so the countdown glides instead of stepping.
  const [nowMs, setNowMs] = useState(() => Date.now());
  const [paired, setPaired] = useState(false);
  useEffect(() => {
    if (paired) return;
    const timer = setInterval(() => setNowMs(Date.now()), 100);
    return () => clearInterval(timer);
  }, [paired]);

  const msLeft = Math.max(0, expiryMs - nowMs);
  const remaining = Math.ceil(msLeft / 1000);
  const fraction = Math.max(0, Math.min(1, msLeft / (PIN_TTL_SECONDS * 1000)));
  const expired = msLeft <= 0;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm animate-fade-in"
      role="dialog"
      aria-modal="true"
      aria-label={t("a11y.devicePairing")}
    >
      <div className="card w-full max-w-md overflow-hidden p-6 shadow-pop animate-scale-in">
        <LinkHeader
          title={mode.role === "responder" ? t("pairing.requestTitle") : t("pairing.enterTitle")}
          sub={mode.role === "responder" ? t("pairing.requestSub") : t("pairing.enterSub")}
          expired={expired}
          paired={paired}
        />

        {paired ? (
          <SuccessBody t={t} />
        ) : mode.role === "responder" ? (
          <ResponderBody prompt={mode.prompt} t={t} />
        ) : (
          <RequesterBody
            device={mode.device}
            expired={expired}
            onPaired={() => {
              setPaired(true);
              window.setTimeout(onPaired, 700);
            }}
            t={t}
          />
        )}

        {!paired && <Countdown remaining={remaining} fraction={fraction} expired={expired} t={t} />}

        <div className="mt-5 flex justify-end">
          {!paired && (
            <button type="button" className="btn-ghost" onClick={onClose}>
              {expired ? t("common.close") : t("common.cancel")}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

/// Header hero: two nodes -- this device and the peer -- with a tie being
/// drawn between them, echoing the home constellation. While pairing is
/// live a heartbeat travels the tie; once paired the tie locks solid and
/// the peer node resolves into a check. Expiry dims the whole glyph.
function LinkHeader({
  title,
  sub,
  expired,
  paired,
}: {
  title: string;
  sub: string;
  expired: boolean;
  paired: boolean;
}) {
  const live = !expired && !paired;
  return (
    <div className="mb-5 flex flex-col items-center text-center">
      <PairingGlyph live={live} paired={paired} expired={expired} />
      <p className="mt-3.5 text-sm font-semibold text-ink">{title}</p>
      <p className="mt-0.5 text-xs text-ink-faint">{sub}</p>
    </div>
  );
}

// The two-node linking glyph. Pure SVG so the tie, pulse, and halos scale
// and stay welded together; reuses the constellation's `cnst-*` motion.
function PairingGlyph({ live, paired, expired }: { live: boolean; paired: boolean; expired: boolean }) {
  const A = { x: 34, y: 30 }; // this device
  const B = { x: 126, y: 30 }; // the peer
  const tieBright = paired ? 0.55 : live ? 0.22 : 0.1;
  return (
    <svg
      viewBox="0 0 160 60"
      className={`h-14 w-40 transition-opacity duration-500 ${expired ? "opacity-40" : "opacity-100"}`}
      aria-hidden="true"
    >
      {/* base tie */}
      <line
        x1={A.x}
        y1={A.y}
        x2={B.x}
        y2={B.y}
        stroke={`rgba(255,255,255,${tieBright})`}
        strokeWidth={paired ? 2 : 1.5}
        strokeLinecap="round"
        className="transition-all duration-500"
      />
      {/* heartbeat, only while live */}
      {live && (
        <line
          className="cnst-pulse"
          x1={A.x}
          y1={A.y}
          x2={B.x}
          y2={B.y}
          stroke="rgb(var(--paper))"
          strokeWidth={2.5}
          strokeLinecap="round"
          pathLength={100}
          strokeDasharray="10 90"
          style={{ filter: "drop-shadow(0 0 3px rgba(255,255,255,0.7))" }}
        />
      )}

      {/* this device -- always lit */}
      {live && <circle className="cnst-halo" cx={A.x} cy={A.y} r={7} fill="none" stroke="rgb(var(--paper))" strokeWidth={1.4} />}
      <circle cx={A.x} cy={A.y} r={7} fill="rgb(var(--paper))" style={{ filter: "drop-shadow(0 0 6px rgba(255,255,255,0.5))" }} />

      {/* peer -- hollow while connecting, lit + check once paired */}
      {paired ? (
        <g style={{ animation: "check-pop 0.5s cubic-bezier(0.16,1,0.3,1)" }}>
          <circle cx={B.x} cy={B.y} r={9} fill="rgb(var(--paper))" style={{ filter: "drop-shadow(0 0 7px rgba(255,255,255,0.55))" }} />
          <path
            d={`M${B.x - 4} ${B.y} l3 3 l5 -6`}
            fill="none"
            stroke="#000"
            strokeWidth={1.8}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </g>
      ) : (
        <>
          {live && <circle className="cnst-halo" cx={B.x} cy={B.y} r={7} fill="none" stroke="rgb(var(--paper))" strokeWidth={1.2} style={{ animationDelay: "1.3s" }} />}
          <circle cx={B.x} cy={B.y} r={7} fill="rgb(var(--canvas))" stroke="rgba(255,255,255,0.28)" strokeWidth={1.5} strokeDasharray={live ? undefined : "2.5 2.5"} />
        </>
      )}
    </svg>
  );
}

function Countdown({
  remaining,
  fraction,
  expired,
  t,
}: {
  remaining: number;
  fraction: number;
  expired: boolean;
  t: Translate;
}) {
  if (expired) {
    return (
      <p className="mt-4 flex items-center gap-2 text-sm font-medium text-danger" role="alert">
        <span className="h-1.5 w-1.5 rounded-full bg-danger" />
        {t("pairing.timedOut")}
      </p>
    );
  }
  // Urgency ramps up over the final PAIRING_URGENT_SECONDS: the label
  // and fill shift from ink/paper toward the danger token and the label
  // gets a slow pulse, so the last stretch reads as "hurry" without any
  // new hue or layout-affecting property -- only opacity/color.
  const urgent = remaining <= PAIRING_URGENT_SECONDS;
  return (
    <div className="mt-4">
      <div className="mb-1.5 flex items-center justify-between text-[11px] text-ink-faint">
        <span>{t("pairing.expiresIn")}</span>
        <span
          className={`nums font-medium tabular-nums transition-colors duration-300 ${
            urgent ? "text-danger animate-pulse" : "text-ink-muted"
          }`}
          data-testid="pin-countdown-remaining"
        >
          {remaining}s
        </span>
      </div>
      <div className="h-1 w-full overflow-hidden rounded-full bg-white/[0.06]">
        {/* Fixed-width track, transform-scaled fill: the countdown ticks
            every 100ms, so animating `width` here would force a reflow
            on every tick. `transform: scaleX()` is compositor-only. */}
        <div
          className={`h-full w-full origin-left rounded-full transition-colors duration-300 ease-linear ${
            urgent ? "bg-danger" : "bg-paper"
          }`}
          style={{ transform: `scaleX(${fraction})` }}
          data-testid="pin-countdown-bar"
        />
      </div>
    </div>
  );
}

/// One PIN cell. `filled` digits pop in; `active` shows a blinking caret;
/// `error` tints the border while the shake plays.
function PinCell({
  digit,
  active,
  error,
  delay,
}: {
  digit?: string;
  active?: boolean;
  error?: boolean;
  delay?: number;
}) {
  const filled = digit !== undefined && digit !== "";
  return (
    <div
      className={`relative flex h-14 items-center justify-center rounded-lg border bg-black/40 font-mono text-2xl font-semibold text-ink shadow-[0_1px_0_0_rgba(255,255,255,0.04)_inset] transition-colors duration-200 ${
        error
          ? "border-danger/70"
          : active
            ? "border-white/45 ring-2 ring-white/10"
            : filled
              ? "border-line-strong"
              : "border-line"
      }`}
      style={delay !== undefined ? { animation: "cell-rise 0.4s cubic-bezier(0.16,1,0.3,1) both", animationDelay: `${delay}s` } : undefined}
    >
      {filled ? (
        <span key={digit} style={{ animation: "digit-pop 0.24s cubic-bezier(0.16,1,0.3,1)" }}>
          {digit}
        </span>
      ) : (
        active && <span className="h-6 w-px bg-ink" style={{ animation: "caret-blink 1.1s steps(1) infinite" }} />
      )}
    </div>
  );
}

function ResponderBody({ prompt, t }: { prompt: PairingPrompt; t: Translate }) {
  const digits = prompt.pinCode.padEnd(6, " ").slice(0, 6).split("");
  return (
    <div>
      <p className="mb-3 text-sm text-ink-muted">{t("pairing.wantsToPair", { name: prompt.requesterDeviceName })}</p>
      <div className="grid grid-cols-6 gap-2" aria-label={t("pairing.pinLabel")}>
        {digits.map((d, i) => (
          <PinCell key={i} digit={d.trim()} delay={i * 0.06} />
        ))}
      </div>
    </div>
  );
}

function RequesterBody({
  device,
  expired,
  onPaired,
  t,
}: {
  device: NearbyDevice;
  expired: boolean;
  onPaired: () => void;
  t: Translate;
}) {
  const [pin, setPin] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [shake, setShake] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const canSubmit = useMemo(
    () => /^\d{6}$/.test(pin) && !expired && !submitting,
    [pin, expired, submitting],
  );

  function triggerShake() {
    setShake(true);
    window.setTimeout(() => setShake(false), 480);
  }

  async function submit() {
    setSubmitting(true);
    setError(null);
    const result = await ipc.confirmPin(device.addr, device.port, pin, device.deviceId);
    setSubmitting(false);
    if (!result.ok) {
      setError(errorCodeMessage(result.error.code, t));
      triggerShake();
      return;
    }
    if (result.value) {
      onPaired();
    } else {
      setError(t("pairing.incorrectPin"));
      setPin("");
      triggerShake();
      inputRef.current?.focus();
    }
  }

  const cells = Array.from({ length: 6 }, (_, i) => i);

  return (
    <div>
      <p className="mb-3 text-sm text-ink-muted">{t("pairing.typeCode", { name: device.deviceName })}</p>

      {/* A real (visually hidden) input carries the value for keyboard and
          assistive tech; the animated cells are the visual layer. Clicking
          the cells focuses the input. */}
      <div className="relative" onClick={() => inputRef.current?.focus()}>
        <input
          ref={inputRef}
          value={pin}
          onChange={(e) => setPin(e.target.value.replace(/\D/g, "").slice(0, 6))}
          onKeyDown={(e) => {
            if (e.key === "Enter" && canSubmit) submit();
          }}
          inputMode="numeric"
          autoFocus
          aria-label={t("pairing.pinLabel")}
          className="absolute inset-0 z-10 h-full w-full cursor-pointer bg-transparent text-transparent caret-transparent outline-none"
        />
        <div
          className="grid grid-cols-6 gap-2"
          aria-hidden="true"
          style={shake ? { animation: "shake 0.48s cubic-bezier(0.36,0.07,0.19,0.97)" } : undefined}
        >
          {cells.map((i) => (
            <PinCell key={i} digit={pin[i]} active={i === pin.length && !expired} error={shake} />
          ))}
        </div>
      </div>

      {error && (
        <p className="mt-2 text-sm text-danger" role="alert">
          {error}
        </p>
      )}

      <button type="button" className="btn-primary mt-4 w-full" disabled={!canSubmit} onClick={submit}>
        {submitting ? (
          <>
            <Icon name="refresh" className="h-4 w-4 animate-spin" />
            {t("pairing.verifying")}
          </>
        ) : (
          t("common.pair")
        )}
      </button>
    </div>
  );
}

function SuccessBody({ t }: { t: Translate }) {
  // The header glyph already delivers the "linked" beat (tie locks, peer
  // resolves to a check), so the body stays a quiet confirmation line
  // rather than a second, competing checkmark.
  return (
    <div className="flex flex-col items-center py-2 text-center animate-scale-in">
      <p className="text-sm font-semibold text-ink">{t("pairing.pairedTitle")}</p>
      <p className="mt-1 text-xs text-ink-faint">{t("pairing.pairedSub")}</p>
    </div>
  );
}
