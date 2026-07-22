import { Icon, type IconName } from "./Icon";

interface EmptyStateProps {
  icon: IconName;
  title: string;
  hint?: string;
}

/// Distinct, composed empty state (icon + title + hint) so each panel's
/// zero-data view reads as intentional, not a blank void.
export function EmptyState({ icon, title, hint }: EmptyStateProps) {
  return (
    <div className="flex h-full flex-col items-center justify-center px-8 py-16 text-center animate-fade-in">
      <div className="mb-4 flex h-14 w-14 items-center justify-center rounded-2xl border border-line bg-surface-raised shadow-card">
        <Icon name={icon} className="h-6 w-6 text-ink-faint" />
      </div>
      <p className="text-sm font-medium text-ink">{title}</p>
      {hint && <p className="mt-1.5 max-w-xs text-xs leading-relaxed text-ink-faint">{hint}</p>}
    </div>
  );
}
