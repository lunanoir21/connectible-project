import { Icon, type IconName } from "./Icon";
import { useT } from "../i18n";
import type { TranslationKey } from "../i18n";

export type PanelId =
  | "home"
  | "devices"
  | "clipboard"
  | "transfers"
  | "input"
  | "notifications"
  | "doctor"
  | "settings";

interface SidebarProps {
  active: PanelId;
  onSelect: (panel: PanelId) => void;
  counts: Partial<Record<PanelId, number>>;
}

const ITEMS: Array<{ id: PanelId; labelKey: TranslationKey; icon: IconName }> = [
  { id: "home", labelKey: "nav.home", icon: "home" },
  { id: "devices", labelKey: "nav.devices", icon: "devices" },
  { id: "clipboard", labelKey: "nav.clipboard", icon: "clipboard" },
  { id: "transfers", labelKey: "nav.transfers", icon: "transfer" },
  { id: "input", labelKey: "nav.input", icon: "cursor" },
  { id: "notifications", labelKey: "nav.notifications", icon: "bell" },
  { id: "doctor", labelKey: "nav.doctor", icon: "shield" },
];

export function Sidebar({ active, onSelect, counts }: SidebarProps) {
  const t = useT();
  return (
    <nav
      className="flex w-[236px] shrink-0 flex-col border-r border-line bg-surface/60 backdrop-blur-xl"
      aria-label={t("a11y.panels")}
    >
      <div className="flex items-center gap-2.5 px-5 pb-4 pt-5">
        <div className="flex h-8 w-8 items-center justify-center rounded-lg border border-line-strong bg-gradient-to-b from-white/[0.16] to-transparent shadow-glow">
          <Icon name="link" className="h-4 w-4 text-ink" strokeWidth={1.8} />
        </div>
        <div className="leading-tight">
          <div className="text-[15px] font-semibold tracking-tightest text-ink">Connectible</div>
          <div className="text-[11px] text-ink-faint">{t("brand.sub")}</div>
        </div>
      </div>

      <div className="flex flex-1 flex-col gap-0.5 px-3">
        {ITEMS.map((item) => (
          <RailButton
            key={item.id}
            icon={item.icon}
            label={t(item.labelKey)}
            active={active === item.id}
            count={counts[item.id] ?? 0}
            onClick={() => onSelect(item.id)}
          />
        ))}
      </div>

      {/* Pinned bottom area: prominent, full-width Settings entry plus
          the security line. */}
      <div className="mt-2 border-t border-line px-3 py-3">
        <RailButton
          icon="settings"
          label={t("nav.settings")}
          active={active === "settings"}
          count={0}
          onClick={() => onSelect("settings")}
        />
        <div className="mt-2 flex items-center gap-2 px-3 text-[11px] text-ink-ghost">
          <Icon name="shield" className="h-3.5 w-3.5" />
          <span>{t("footer.security")}</span>
        </div>
      </div>
    </nav>
  );
}

function RailButton({
  icon,
  label,
  active,
  count,
  onClick,
}: {
  icon: IconName;
  label: string;
  active: boolean;
  count: number;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-current={active ? "page" : undefined}
      className={`rail-item group ${
        active ? "bg-white/[0.07] text-ink" : "text-ink-muted hover:bg-white/[0.04] hover:text-ink"
      }`}
    >
      {active && (
        <span className="absolute left-0 top-1/2 h-4 w-[3px] -translate-y-1/2 rounded-r-full bg-paper" />
      )}
      <Icon
        name={icon}
        className={`h-[18px] w-[18px] transition-colors ${
          active ? "text-ink" : "text-ink-faint group-hover:text-ink-muted"
        }`}
      />
      <span className="flex-1 text-left">{label}</span>
      {count > 0 && (
        <span className="rounded-full bg-white/10 px-1.5 text-[11px] font-semibold text-ink-muted nums">
          {count}
        </span>
      )}
    </button>
  );
}
