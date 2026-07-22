import { useI18n, type Locale } from "../i18n";

const OPTIONS: Array<{ id: Locale; short: string }> = [
  { id: "en", short: "EN" },
  { id: "tr", short: "TR" },
];

/// Compact monochrome segmented control for switching UI language.
export function LanguageSwitcher() {
  const { locale, setLocale, t } = useI18n();

  return (
    <div
      className="inline-flex rounded-lg border border-line bg-surface-raised p-0.5"
      role="group"
      aria-label={t("lang.label")}
    >
      {OPTIONS.map((opt) => {
        const active = locale === opt.id;
        return (
          <button
            key={opt.id}
            type="button"
            onClick={() => setLocale(opt.id)}
            aria-pressed={active}
            className={`rounded-md px-2 py-1 text-[11px] font-semibold tracking-wide transition-colors ${
              active ? "bg-white/[0.1] text-ink" : "text-ink-faint hover:text-ink-muted"
            }`}
          >
            {opt.short}
          </button>
        );
      })}
    </div>
  );
}
