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

export function formatRelativeTime(epochMs: number, nowMs: number = Date.now()): string {
  const deltaSec = Math.round((nowMs - epochMs) / 1000);
  if (deltaSec < 5) return "just now";
  if (deltaSec < 60) return `${deltaSec}s ago`;
  const deltaMin = Math.round(deltaSec / 60);
  if (deltaMin < 60) return `${deltaMin}m ago`;
  const deltaHr = Math.round(deltaMin / 60);
  if (deltaHr < 24) return `${deltaHr}h ago`;
  const deltaDay = Math.round(deltaHr / 24);
  return `${deltaDay}d ago`;
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
