import { useCallback, useEffect, useState } from "react";
import type { TranslationKey } from "./i18n";

export type ThemeId = "charcoal" | "onyx" | "graphite";

// Preview swatches use the actual token values so the Settings cards
// show a true sample of each theme. `nameKey` points at an i18n key.
export const THEMES: Array<{ id: ThemeId; nameKey: TranslationKey; swatch: [string, string, string] }> = [
  { id: "charcoal", nameKey: "settings.themeCharcoal", swatch: ["#08080a", "#161619", "#222227"] },
  { id: "onyx", nameKey: "settings.themeOnyx", swatch: ["#000000", "#0b0b0d", "#17171a"] },
  { id: "graphite", nameKey: "settings.themeGraphite", swatch: ["#0f0f13", "#18181e", "#202027"] },
];

const STORAGE_KEY = "connectible.theme";
const DEFAULT_THEME: ThemeId = "charcoal";

function isThemeId(value: string | null): value is ThemeId {
  return value === "charcoal" || value === "onyx" || value === "graphite";
}

export function getInitialTheme(): ThemeId {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (isThemeId(saved)) return saved;
  } catch {
    // localStorage unavailable -- use default.
  }
  return DEFAULT_THEME;
}

export function applyTheme(theme: ThemeId): void {
  document.documentElement.setAttribute("data-theme", theme);
  try {
    localStorage.setItem(STORAGE_KEY, theme);
  } catch {
    // Persist is best-effort.
  }
}

/// Hook owning the active theme: applies it to <html data-theme> and
/// persists it. Applied on mount so a saved theme survives reloads.
export function useTheme(): { theme: ThemeId; setTheme: (theme: ThemeId) => void } {
  const [theme, setThemeState] = useState<ThemeId>(getInitialTheme);

  useEffect(() => {
    applyTheme(theme);
  }, [theme]);

  const setTheme = useCallback((next: ThemeId) => setThemeState(next), []);

  return { theme, setTheme };
}
