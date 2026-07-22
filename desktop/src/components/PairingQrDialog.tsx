import { useEffect, useRef, useState } from "react";
import QRCode from "qrcode";
import { ipc } from "../lib/ipc";
import { encodePairingPayload } from "../lib/pairingCode";
import { errorCodeMessage } from "../lib/errors";
import { Icon } from "./Icon";
import { useT } from "../i18n";

const PIN_TTL_SECONDS = 30;

// Module-scope (not a ref inside the component) so the race guard
// survives across mount/unmount: each open of the dialog is a fresh
// component instance (see App.tsx), so a ref reset to 0 on every mount
// can't stop a stale instance's in-flight preArmPairingCode() from
// resolving after a newer instance's and silently invalidating the PIN
// currently on screen. Incrementing this counter on every generate()
// call, from any instance, is what actually makes "only the most
// recent call wins" hold across a close/reopen, not just within one
// instance's lifetime.
let moduleRequestId = 0;

interface PairingQrDialogProps {
  deviceId: string;
  deviceName: string;
  onClose: () => void;
  // True once a real inbound pairing request (using this code) has
  // arrived -- the caller's own responder PairingDialog takes over at
  // that point, so this dialog closes itself instead of stacking.
  consumed: boolean;
}

/// Desktop side of scan-to-pair (§QR): pre-arms a PIN with the daemon,
/// encodes it plus this device's LAN address into a QR code, and shows
/// both the code and the human-readable PIN (so the manual/no-camera
/// fallback still works). Regenerates automatically when the 30s
/// window elapses with nobody having scanned it.
export function PairingQrDialog({ deviceId, deviceName, onClose, consumed }: PairingQrDialogProps) {
  const t = useT();
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [pin, setPin] = useState<string | null>(null);
  const [expiresAtMs, setExpiresAtMs] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [nowMs, setNowMs] = useState(() => Date.now());
  const closeButtonRef = useRef<HTMLButtonElement>(null);

  const generate = async () => {
    const myId = ++moduleRequestId;
    setError(null);
    const own = await ipc.localAddresses();
    if (myId !== moduleRequestId) return; // superseded by a newer call
    if (!own.ok || own.value.addresses.length === 0) {
      setError(t("pairingQr.noAddress"));
      return;
    }
    // Arming a code invalidates whatever the daemon had armed before, so
    // if a newer call already started, skip this RPC entirely rather
    // than winning a race the newer call would just re-invalidate anyway.
    if (myId !== moduleRequestId) return;
    const armed = await ipc.preArmPairingCode();
    if (myId !== moduleRequestId) return; // superseded while awaiting
    if (!armed.ok) {
      setError(errorCodeMessage(armed.error.code, t));
      return;
    }
    setPin(armed.value.pinCode);
    setExpiresAtMs(armed.value.pinExpiresAtMs);

    const payload = encodePairingPayload({
      host: own.value.addresses[0],
      port: own.value.port,
      pin: armed.value.pinCode,
      deviceId,
      deviceName,
    });
    if (canvasRef.current) {
      try {
        await QRCode.toCanvas(canvasRef.current, payload, {
          width: 208,
          margin: 1,
          color: { dark: "#0a0a0c", light: "#ffffff" },
        });
      } catch {
        if (myId !== moduleRequestId) return; // superseded while rendering
        setError(t("pairingQr.renderFailed"));
      }
    }
  };

  useEffect(() => {
    void generate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (consumed) onClose();
  }, [consumed, onClose]);

  useEffect(() => {
    const timer = setInterval(() => setNowMs(Date.now()), 500);
    return () => clearInterval(timer);
  }, []);

  // Focus the close button on mount so keyboard/screen-reader users land
  // somewhere sensible inside the dialog immediately, without relying on
  // a full focus trap.
  useEffect(() => {
    closeButtonRef.current?.focus();
  }, []);

  // Escape closes the dialog, matching standard modal behavior; PairingDialog
  // has the same listener.
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);

  const msLeft = expiresAtMs ? Math.max(0, expiresAtMs - nowMs) : 0;
  const remaining = Math.ceil(msLeft / 1000);
  const fraction = Math.max(0, Math.min(1, msLeft / (PIN_TTL_SECONDS * 1000)));
  const expired = expiresAtMs !== null && msLeft <= 0;

  // An expired code only dimming to opacity-30 still leaves the QR
  // technically scannable (e.g. in a screenshot); clear the drawn code
  // once it's no longer valid so nothing scannable remains behind the
  // dimmed placeholder.
  useEffect(() => {
    if (expired) {
      canvasRef.current?.getContext("2d")?.clearRect(0, 0, canvasRef.current.width, canvasRef.current.height);
    }
  }, [expired]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm animate-fade-in"
      role="dialog"
      aria-modal="true"
      aria-label={t("pairingQr.title")}
    >
      <div className="card w-full max-w-sm p-6 shadow-pop animate-scale-in">
        <p className="text-center text-sm font-semibold text-ink">{t("pairingQr.title")}</p>
        <p className="mt-1 text-center text-xs text-ink-faint">{t("pairingQr.subtitle")}</p>

        <div className="mt-5 flex justify-center">
          {error ? (
            <div className="flex h-[208px] w-[208px] items-center justify-center rounded-xl border border-danger/30 bg-danger-soft p-4 text-center text-xs text-danger">
              {error}
            </div>
          ) : (
            <div className="relative rounded-xl border border-line bg-white p-3">
              <canvas ref={canvasRef} aria-label={t("pairingQr.title")} className={expired ? "opacity-30" : ""} />
              {expired && (
                <button
                  type="button"
                  onClick={() => void generate()}
                  className="absolute inset-0 flex flex-col items-center justify-center gap-1.5 text-xs font-medium text-black"
                >
                  <Icon name="refresh" className="h-5 w-5" />
                  {t("pairingQr.regenerate")}
                </button>
              )}
            </div>
          )}
        </div>

        {pin && !error && (
          <p className="mt-4 text-center font-mono text-lg font-semibold tracking-[0.3em] text-ink nums">{pin}</p>
        )}

        {expiresAtMs !== null && !error && (
          <div className="mt-3">
            <div className="mb-1.5 flex items-center justify-between text-[11px] text-ink-faint">
              <span>{expired ? t("pairingQr.expired") : t("pairing.expiresIn")}</span>
              {!expired && <span className="nums font-medium tabular-nums text-ink-muted">{remaining}s</span>}
            </div>
            <div className="h-1 w-full overflow-hidden rounded-full bg-white/[0.06]">
              <div
                className="h-full w-full origin-left rounded-full bg-paper transition-transform duration-300 ease-linear"
                style={{ transform: `scaleX(${fraction})` }}
              />
            </div>
          </div>
        )}

        <div className="mt-5 flex justify-end">
          <button type="button" ref={closeButtonRef} className="btn-ghost" onClick={onClose}>
            {t("common.close")}
          </button>
        </div>
      </div>
    </div>
  );
}
