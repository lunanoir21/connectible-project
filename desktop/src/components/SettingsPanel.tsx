import { Icon } from "./Icon";
import { useI18n } from "../i18n";
import { THEMES, type ThemeId } from "../theme";
import { useState, useCallback, useEffect } from "react";
import { open } from "@tauri-apps/plugin-dialog";
import { ipc } from "../lib/ipc";
import { errorCodeMessage } from "../lib/errors";
import type { DaemonStatusDto } from "../lib/types";

interface SettingsPanelProps {
  theme: ThemeId;
  onThemeChange: (theme: ThemeId) => void;
  deviceName: string;
  appVersion: string;
  onOpenPairingQr: () => void;
  // T-310's clipboard-sync toggle, previously reachable only from the
  // system tray menu (src-tauri/src/tray.rs). Sourced from the shared
  // daemon state (App.tsx's `daemon.clipboardSyncEnabled`) the same way
  // RemoteInputPanel's `enabled` prop mirrors `daemon.remoteInputEnabled`.
  clipboardSyncEnabled: boolean;
  // Re-fetches daemon state after a successful toggle, mirroring
  // RemoteInputPanel's onRefresh -- the toggle itself calls
  // ipc.setClipboardSyncEnabled directly (matching how every other
  // action in this panel calls ipc.* directly rather than going through
  // a callback prop).
  onClipboardSyncRefresh: () => void;
}

/// Settings panel (T-034 area): spacious, sectioned surface for
/// appearance (theme), language, connection, and read-only about info.
export function SettingsPanel({
  theme,
  onThemeChange,
  deviceName,
  appVersion,
  onOpenPairingQr,
  clipboardSyncEnabled,
  onClipboardSyncRefresh,
}: SettingsPanelProps) {
  const { t, locale, setLocale } = useI18n();
  const [daemonStatus, setDaemonStatus] = useState<DaemonStatusDto | null>(null);
  const [checking, setChecking] = useState(false);
  const [togglingClipboardSync, setTogglingClipboardSync] = useState(false);
  // Distinct from `daemonStatus.error` (which reflects the daemon's own
  // reported state): this is for a start/stop *command itself* failing
  // to reach the Tauri backend at all (RULES.md "never swallow an
  // error silently").
  const [actionError, setActionError] = useState<string | null>(null);
  // T-X11: a neutral (non-error) notice, e.g. "the daemon is managed
  // externally, stop it with systemctl" when Stop had nothing of its
  // own to kill. Distinct from `actionError` so it renders calmly.
  const [actionNotice, setActionNotice] = useState<string | null>(null);
  // Where the daemon saves received files (T-108 follow-up): resolved
  // effective folder, plus a picker to change it. null until the first
  // fetch resolves.
  const [downloadDir, setDownloadDir] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    ipc.getDownloadDir().then((r) => {
      if (!alive) return;
      if (r.ok) {
        setDownloadDir(r.value);
      } else {
        // T-X30: a failed fetch used to leave this row on "Loading..."
        // forever, with the Open/Change buttons quietly staying disabled
        // and no indication why.
        setActionError(errorCodeMessage(r.error.code, t));
      }
    });
    return () => {
      alive = false;
    };
  }, [t]);

  const changeDownloadDir = useCallback(async () => {
    const selected = await open({ directory: true, multiple: false });
    if (typeof selected !== "string") return;
    const result = await ipc.setDownloadDir(selected);
    if (result.ok) {
      setDownloadDir(result.value);
    } else {
      setActionError(errorCodeMessage(result.error.code, t));
    }
  }, [t]);

  const openDownloadDir = useCallback(async () => {
    if (!downloadDir) return;
    const result = await ipc.openPath(downloadDir);
    if (!result.ok) setActionError(errorCodeMessage(result.error.code, t));
  }, [downloadDir, t]);

  const checkDaemonStatus = useCallback(async () => {
    setChecking(true);
    setActionError(null);
    const result = await ipc.daemonStatus();
    if (result.ok) {
      setDaemonStatus(result.value);
    } else {
      setActionError(errorCodeMessage(result.error.code, t));
    }
    setChecking(false);
  }, [t]);

  // Fetch the daemon's status as soon as the panel mounts, instead of
  // leaving it on "Checking..." until the user notices and clicks
  // Refresh themselves.
  useEffect(() => {
    void checkDaemonStatus();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const toggleClipboardSync = useCallback(async () => {
    setTogglingClipboardSync(true);
    setActionError(null);
    const result = await ipc.setClipboardSyncEnabled(!clipboardSyncEnabled);
    setTogglingClipboardSync(false);
    if (!result.ok) {
      setActionError(errorCodeMessage(result.error.code, t));
      return;
    }
    onClipboardSyncRefresh();
  }, [clipboardSyncEnabled, onClipboardSyncRefresh, t]);

  const startDaemon = useCallback(async () => {
    setChecking(true);
    setActionError(null);
    const result = await ipc.startDaemon();
    if (result.ok) {
      setDaemonStatus(result.value);
    } else {
      setActionError(errorCodeMessage(result.error.code, t));
    }
    setChecking(false);
  }, [t]);

  const stopDaemon = useCallback(async () => {
    setChecking(true);
    setActionError(null);
    setActionNotice(null);
    const stopResult = await ipc.stopDaemon();
    if (!stopResult.ok) {
      setActionError(errorCodeMessage(stopResult.error.code, t));
      setChecking(false);
      return;
    }
    // T-X11: `stop_daemon` returns false when this app did not spawn the
    // running daemon (e.g. a systemd user service) and so has no process
    // to kill. That is not an error, but silently doing nothing looks
    // broken -- tell the user where the real off switch is.
    if (!stopResult.value) {
      setActionNotice(t("settings.daemonExternal"));
    }
    // Re-check status
    const statusResult = await ipc.daemonStatus();
    if (statusResult.ok) {
      setDaemonStatus(statusResult.value);
    } else {
      setActionError(errorCodeMessage(statusResult.error.code, t));
    }
    setChecking(false);
  }, [t]);

  return (
    <section className="mx-auto flex h-full max-w-3xl flex-col gap-6 overflow-y-auto pr-1 animate-fade-in">
      <div>
        <h2 className="text-lg font-semibold tracking-tightest text-ink">{t("settings.title")}</h2>
        <p className="mt-0.5 text-sm text-ink-faint">{t("settings.subtitle")}</p>
      </div>

      {/* Appearance / theme */}
      <SettingsSection icon="palette" title={t("settings.appearance")} hint={t("settings.appearanceHint")}>
        <div className="grid grid-cols-3 gap-3">
          {THEMES.map((option) => {
            const active = theme === option.id;
            return (
              <button
                key={option.id}
                type="button"
                onClick={() => onThemeChange(option.id)}
                aria-pressed={active}
                className={`group flex flex-col gap-3 rounded-xl border p-3 text-left transition-all ${
                  active
                    ? "border-white/25 bg-white/[0.05] shadow-glow"
                    : "border-line bg-surface-raised hover:border-line-strong hover:bg-surface-hover"
                }`}
              >
                <div className="flex h-16 items-end gap-1.5 overflow-hidden rounded-lg border border-line p-2" style={{ background: option.swatch[0] }}>
                  <span className="h-8 flex-1 rounded" style={{ background: option.swatch[1] }} />
                  <span className="h-11 flex-1 rounded" style={{ background: option.swatch[2] }} />
                  <span className="h-5 w-2.5 rounded-full bg-paper" />
                </div>
                <span className={`text-sm font-medium ${active ? "text-ink" : "text-ink-muted"}`}>
                  {t(option.nameKey)}
                </span>
              </button>
            );
          })}
        </div>
      </SettingsSection>

      {/* Language */}
      <SettingsSection icon="globe" title={t("settings.language")} hint={t("settings.languageHint")}>
        <div className="flex flex-col gap-2">
          {(["en", "tr"] as const).map((id) => {
            const active = locale === id;
            return (
              <button
                key={id}
                type="button"
                onClick={() => setLocale(id)}
                aria-pressed={active}
                className={`flex items-center justify-between rounded-lg border px-4 py-3 text-sm transition-all ${
                  active
                    ? "border-white/25 bg-white/[0.05] text-ink"
                    : "border-line bg-surface-raised text-ink-muted hover:border-line-strong hover:bg-surface-hover"
                }`}
              >
                <span className="flex items-center gap-3">
                  <span className="flex h-6 w-8 items-center justify-center rounded border border-line text-[11px] font-semibold uppercase text-ink-muted">
                    {id}
                  </span>
                  {t(id === "en" ? "lang.en" : "lang.tr")}
                </span>
                {active && (
                  <span className="flex h-4 w-4 items-center justify-center rounded-full bg-paper">
                    <Icon name="check" className="h-3 w-3 text-black" strokeWidth={2.4} />
                  </span>
                )}
              </button>
            );
          })}
        </div>
      </SettingsSection>

      {/* Connection */}
      <SettingsSection icon="desktop" title={t("settings.connection")} hint={t("settings.connectionHint")}>
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-ink">{t("settings.daemon")}</p>
              <p className="text-xs text-ink-faint">{t("settings.daemonHint")}</p>
            </div>
            <div className="flex items-center gap-2">
              {daemonStatus && (
                <>
                  <span
                    className={`flex h-2 w-2 rounded-full ${
                      !daemonStatus.running ? "bg-ink-ghost" : daemonStatus.reachable ? "bg-paper" : "bg-danger"
                    }`}
                  />
                  <span className="text-sm text-ink-muted">
                    {!daemonStatus.running
                      ? t("daemon.stopped")
                      : daemonStatus.reachable
                        ? t("daemon.reachable")
                        : t("daemon.unreachable")}
                  </span>
                  {daemonStatus.running && daemonStatus.reachable && daemonStatus.rttMs !== null && (
                    <span className="text-xs text-ink-faint nums">
                      {t("daemon.rtt", { ms: daemonStatus.rttMs })}
                    </span>
                  )}
                </>
              )}
              {!daemonStatus && <span className="text-sm text-ink-faint">{t("daemon.checking")}</span>}
            </div>
          </div>
          {daemonStatus?.errorCode && (
            <p className="text-xs text-danger bg-danger/10 rounded p-2">
              {errorCodeMessage(daemonStatus.errorCode, t)}
            </p>
          )}
          {actionError && (
            <p className="rounded-lg border border-danger/30 bg-danger-soft px-3.5 py-2.5 text-sm text-danger" role="alert">
              {actionError}
            </p>
          )}
          {actionNotice && (
            <p className="rounded-lg border border-line bg-surface-overlay px-3.5 py-2.5 text-sm text-ink-muted" role="status">
              {actionNotice}
            </p>
          )}
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={checkDaemonStatus}
              disabled={checking}
              className="btn-ghost text-sm"
            >
              {checking ? t("daemon.checking") : t("common.refresh")}
            </button>
            {daemonStatus?.running ? (
              <button type="button" onClick={stopDaemon} disabled={checking} className="btn-ghost text-sm">
                {t("daemon.stop")}
              </button>
            ) : (
              <button type="button" onClick={startDaemon} disabled={checking} className="btn-primary text-sm">
                {t("daemon.start")}
              </button>
            )}
          </div>
        </div>
      </SettingsSection>

      {/* Clipboard sync */}
      <SettingsSection icon="clipboard" title={t("settings.clipboardSync")} hint={t("settings.clipboardSyncHint")}>
        <div className="flex items-center justify-between rounded-lg border border-line bg-black/20 px-3.5 py-3">
          <div>
            <p className="text-sm font-medium text-ink">
              {clipboardSyncEnabled ? t("settings.clipboardSyncEnabledTitle") : t("settings.clipboardSyncDisabledTitle")}
            </p>
            <p className="mt-0.5 text-xs text-ink-faint">{t("settings.clipboardSyncToggleHint")}</p>
          </div>
          <button
            type="button"
            role="switch"
            aria-checked={clipboardSyncEnabled}
            aria-label={t("settings.clipboardSyncToggleLabel")}
            disabled={togglingClipboardSync}
            onClick={() => void toggleClipboardSync()}
            className={`relative h-6 w-11 shrink-0 rounded-full border transition-colors disabled:opacity-50 ${
              clipboardSyncEnabled ? "border-white/25 bg-white/20" : "border-line bg-surface-overlay"
            }`}
          >
            <span
              className={`absolute top-0.5 h-4 w-4 rounded-full bg-paper transition-transform ${
                clipboardSyncEnabled ? "translate-x-[22px]" : "translate-x-0.5"
              }`}
            />
          </button>
        </div>
      </SettingsSection>

      {/* Pairing QR */}
      <SettingsSection icon="devices" title={t("settings.pairingQr")} hint={t("settings.pairingQrHint")}>
        <button type="button" onClick={onOpenPairingQr} className="btn-primary text-sm">
          {t("settings.pairingQrOpen")}
        </button>
      </SettingsSection>

      {/* Received files */}
      <SettingsSection icon="arrow-down" title={t("settings.files")} hint={t("settings.filesHint")}>
        <div className="flex items-center justify-between gap-3">
          <div className="min-w-0">
            <p className="text-sm font-medium text-ink">{t("settings.downloadDir")}</p>
            <p className="mt-0.5 truncate text-xs text-ink-faint nums" title={downloadDir ?? undefined}>
              {downloadDir ?? t("common.loading")}
            </p>
          </div>
          <div className="flex shrink-0 gap-2">
            <button
              type="button"
              onClick={openDownloadDir}
              disabled={!downloadDir}
              className="btn-ghost text-sm"
            >
              <Icon name="globe" className="h-4 w-4" />
              {t("settings.openFolder")}
            </button>
            <button type="button" onClick={changeDownloadDir} className="btn-primary text-sm">
              {t("settings.changeFolder")}
            </button>
          </div>
        </div>
      </SettingsSection>

      {/* About */}
      <SettingsSection icon="shield" title={t("settings.about")}>
        <dl className="divide-y divide-line">
          <Row label={t("settings.thisDeviceName")} value={deviceName || "-"} />
          <Row label={t("settings.version")} value={appVersion} mono />
          <Row label={t("settings.security")} value={t("settings.securityValue")} />
        </dl>
      </SettingsSection>
    </section>
  );
}

function SettingsSection({
  icon,
  title,
  hint,
  children,
}: {
  icon: "palette" | "globe" | "shield" | "cpu" | "desktop" | "arrow-down" | "devices" | "clipboard";
  title: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="card p-5">
      <div className="mb-4 flex items-start gap-3">
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-line bg-surface-overlay text-ink-muted">
          <Icon name={icon} className="h-[18px] w-[18px]" />
        </div>
        <div>
          <h3 className="text-sm font-semibold text-ink">{title}</h3>
          {hint && <p className="mt-0.5 text-xs text-ink-faint">{hint}</p>}
        </div>
      </div>
      {children}
    </div>
  );
}

function Row({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="flex items-center justify-between py-2.5">
      <dt className="text-sm text-ink-muted">{label}</dt>
      <dd className={`text-sm text-ink ${mono ? "font-mono nums" : ""}`}>{value}</dd>
    </div>
  );
}
