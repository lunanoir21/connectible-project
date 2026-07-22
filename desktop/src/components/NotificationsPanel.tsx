import type { Notification } from "../lib/types";
import type { IpcError } from "../lib/ipc";
import { formatRelativeTime } from "../lib/format";
import { errorCodeMessage } from "../lib/errors";
import { EmptyState } from "./EmptyState";
import { ErrorState } from "./ErrorState";
import { useT, useI18n } from "../i18n";

interface NotificationsPanelProps {
  notifications: Notification[];
  // True until the daemon's first GetLocalState snapshot (which carries
  // the notification feed) has loaded (T-601), distinct from a
  // genuinely empty feed.
  loading?: boolean;
  loadError?: IpcError | null;
  onRefresh?: () => void;
}

/// Placeholder rows shown before the daemon's first snapshot has loaded
/// (T-601), matching DeviceListPanel's T-311 skeleton.
function NotificationsListSkeleton() {
  return (
    <div className="flex flex-col gap-2" data-testid="notifications-list-skeleton" aria-busy="true">
      {[0, 1, 2].map((i) => (
        <div key={i} className="card px-4 py-3.5">
          <div className="flex items-center gap-2">
            <div className="h-6 w-6 animate-pulse rounded-md bg-white/[0.06]" />
            <div className="h-2.5 w-1/4 animate-pulse rounded bg-white/[0.06]" />
          </div>
          <div className="mt-2.5 h-3 w-2/3 animate-pulse rounded bg-white/[0.04]" />
        </div>
      ))}
    </div>
  );
}

/// Forwarded-notification feed (T-040). One-way (phone -> desktop) in the
/// MVP, so this is a read-only view and says so.
export function NotificationsPanel({ notifications, loading, loadError, onRefresh }: NotificationsPanelProps) {
  const t = useT();
  const { locale } = useI18n();
  return (
    <section className="flex h-full flex-col gap-5 animate-fade-in">
      <div className="flex items-center justify-between">
        <span className="eyebrow">{t("notifications.eyebrow")}</span>
        <span className="pill bg-surface-raised text-ink-faint">{t("notifications.readOnly")}</span>
      </div>

      {loading ? (
        <NotificationsListSkeleton />
      ) : loadError ? (
        <ErrorState
          title={t("errors.loadFailedTitle")}
          message={errorCodeMessage(loadError.code, t)}
          retryLabel={onRefresh ? t("common.refresh") : undefined}
          onRetry={onRefresh}
        />
      ) : notifications.length === 0 ? (
        <EmptyState icon="bell" title={t("notifications.emptyTitle")} hint={t("notifications.emptyHint")} />
      ) : (
        <ul className="flex flex-col gap-2 overflow-y-auto pr-1">
          {notifications.map((n) => (
            <li key={n.notificationId} className="card card-hover px-4 py-3.5">
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-2">
                  <span className="flex h-6 w-6 items-center justify-center rounded-md border border-line bg-surface-overlay text-[10px] font-semibold uppercase text-ink-muted">
                    {n.appName.slice(0, 2)}
                  </span>
                  <p className="text-[13px] font-medium text-ink">{n.appName}</p>
                </div>
                <span className="text-[11px] text-ink-faint">{formatRelativeTime(n.postedAtMs, locale)}</span>
              </div>
              {n.title && <p className="mt-2 text-sm text-ink">{n.title}</p>}
              {n.body && <p className="mt-0.5 text-[13px] leading-relaxed text-ink-muted">{n.body}</p>}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
