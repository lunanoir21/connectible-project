import { Icon, type IconName } from "./Icon";

interface ErrorStateProps {
  icon?: IconName;
  title: string;
  message: string;
  // Both required together (or omit both): ErrorState never falls back
  // to a hardcoded English retry label -- RULES.md keeps non-resource
  // strings out of components, so the caller always supplies a
  // translated one via t("common.refresh") or similar.
  retryLabel?: string;
  onRetry?: () => void;
}

/// Distinct error state (T-601): a danger-toned icon well + message,
/// visually parallel to EmptyState's composition but never confusable
/// with it -- a failed daemon call reads as "something went wrong",
/// not as "there is deliberately nothing here yet". Message text must
/// come from errorCodeMessage() (T-602), never a raw error string.
export function ErrorState({ icon = "alert", title, message, retryLabel, onRetry }: ErrorStateProps) {
  return (
    <div className="flex h-full flex-col items-center justify-center px-8 py-16 text-center animate-fade-in" role="alert">
      <div className="mb-4 flex h-14 w-14 items-center justify-center rounded-2xl border border-danger/30 bg-danger-soft shadow-card">
        <Icon name={icon} className="h-6 w-6 text-danger" />
      </div>
      <p className="text-sm font-medium text-ink">{title}</p>
      <p className="mt-1.5 max-w-xs text-xs leading-relaxed text-ink-faint">{message}</p>
      {onRetry && retryLabel && (
        <button type="button" className="btn-ghost mt-4" onClick={onRetry}>
          <Icon name="refresh" className="h-4 w-4" />
          {retryLabel}
        </button>
      )}
    </div>
  );
}
