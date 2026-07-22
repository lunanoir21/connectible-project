// Small pure formatting helpers, kept out of components so they can be
// unit tested directly (see src/lib/format.test.ts).

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let value = bytes / 1024;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value.toFixed(1)} ${units[unitIndex]}`;
}

export function transferPercent(transferred: number, total: number): number {
  if (total <= 0) return 0;
  const pct = Math.round((transferred / total) * 100);
  return Math.max(0, Math.min(100, pct));
}

// Localized relative time (T-X15). `Intl.RelativeTimeFormat` with
// `numeric: "auto"` renders the sub-5s case as the locale's own "now"
// wording ("now" / "şimdi") for free, so no separate i18n key is
// needed. `style: "short"` keeps it compact ("5 min. ago" / "5 dk.
// önce"). `locale` is required so callers thread the active i18n
// locale; it defaults to "en" only so non-component/test callers stay
// convenient.
export function formatRelativeTime(
  epochMs: number,
  locale: string = "en",
  nowMs: number = Date.now(),
): string {
  const rtf = new Intl.RelativeTimeFormat(locale, { numeric: "auto", style: "short" });
  const deltaSec = Math.round((nowMs - epochMs) / 1000);
  if (deltaSec < 5) return rtf.format(0, "second");
  if (deltaSec < 60) return rtf.format(-deltaSec, "second");
  const deltaMin = Math.round(deltaSec / 60);
  if (deltaMin < 60) return rtf.format(-deltaMin, "minute");
  const deltaHr = Math.round(deltaMin / 60);
  if (deltaHr < 24) return rtf.format(-deltaHr, "hour");
  const deltaDay = Math.round(deltaHr / 24);
  return rtf.format(-deltaDay, "day");
}

// Seconds remaining until a pairing PIN expires, clamped at 0. Used by
// the countdown in the pairing dialog.
export function secondsUntil(expiryMs: number, nowMs: number = Date.now()): number {
  return Math.max(0, Math.ceil((expiryMs - nowMs) / 1000));
}

export function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1)}...`;
}
