import { createContext, useContext, useMemo, useState, type ReactNode } from "react";
import en from "./locales/en.json";
import tr from "./locales/tr.json";

export type Locale = "en" | "tr";

// English is the source of truth for the key set; every other locale
// must provide the same keys (enforced structurally by this typed
// Record). TranslationKey is derived from en.json so t() calls are
// checked at compile time.
export type TranslationKey = keyof typeof en;

const DICTS: Record<Locale, Record<TranslationKey, string>> = {
  en,
  tr,
};

const STORAGE_KEY = "connectible.locale";

export type Translate = (key: TranslationKey, params?: Record<string, string | number>) => string;

interface I18nValue {
  locale: Locale;
  setLocale: (locale: Locale) => void;
  t: Translate;
}

/// Pure, hook-free translator for a fixed locale. Exported so
/// non-component code (e.g. errors.test.ts, label helpers invoked
/// outside a render) can get a deterministic `Translate` without going
/// through I18nProvider/useT().
export function translator(locale: Locale): Translate {
  const dict = DICTS[locale];
  return (key, params) => {
    const template = dict[key] ?? en[key] ?? key;
    if (!params) return template;
    return template.replace(/\{(\w+)\}/g, (_, name: string) =>
      name in params ? String(params[name]) : `{${name}}`,
    );
  };
}

// Default value uses English, so components rendered WITHOUT a provider
// (e.g. in unit tests) still translate to English rather than crashing.
const I18nContext = createContext<I18nValue>({
  locale: "en",
  setLocale: () => {},
  t: translator("en"),
});

function detectInitialLocale(): Locale {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved === "en" || saved === "tr") return saved;
  } catch {
    // localStorage unavailable (SSR/sandbox) -- fall through to detection.
  }
  const nav = typeof navigator !== "undefined" ? navigator.language.toLowerCase() : "en";
  return nav.startsWith("tr") ? "tr" : "en";
}

export function I18nProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(detectInitialLocale);

  const value = useMemo<I18nValue>(
    () => ({
      locale,
      setLocale: (next) => {
        setLocaleState(next);
        try {
          localStorage.setItem(STORAGE_KEY, next);
        } catch {
          // Persist is best-effort.
        }
      },
      t: translator(locale),
    }),
    [locale],
  );

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n(): I18nValue {
  return useContext(I18nContext);
}

/// Convenience hook when a component only needs the translate function.
export function useT(): Translate {
  return useContext(I18nContext).t;
}
