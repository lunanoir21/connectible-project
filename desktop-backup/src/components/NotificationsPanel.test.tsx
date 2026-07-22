import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { NotificationsPanel } from "./NotificationsPanel";
import type { Notification } from "../lib/types";

const notifications: Notification[] = [
  {
    notificationId: "n1",
    appName: "Messages",
    title: "New message",
    body: "Hey there",
    postedAtMs: Date.now(),
    isDismissal: false,
  },
];

describe("NotificationsPanel", () => {
  it("shows an empty state with no notifications and no loading/error state active", () => {
    render(<NotificationsPanel notifications={[]} />);
    expect(screen.getByText("No notifications")).toBeInTheDocument();
    expect(screen.queryByTestId("notifications-list-skeleton")).not.toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("shows a loading skeleton before the first snapshot loads, distinct from the empty state (T-601)", () => {
    render(<NotificationsPanel notifications={[]} loading />);
    expect(screen.getByTestId("notifications-list-skeleton")).toBeInTheDocument();
    expect(screen.queryByText("No notifications")).not.toBeInTheDocument();
  });

  it("shows a distinct error state when the initial fetch failed, not the empty state (T-601/T-602)", () => {
    const onRefresh = vi.fn();
    render(
      <NotificationsPanel
        notifications={[]}
        loading={false}
        loadError={{ code: "DEVICE_NOT_FOUND", message: "raw grpc text" }}
        onRefresh={onRefresh}
      />,
    );
    const alert = screen.getByRole("alert");
    expect(alert).toHaveTextContent("That device is no longer available. Refresh the device list.");
    expect(alert).not.toHaveTextContent("raw grpc text");
    expect(screen.queryByText("No notifications")).not.toBeInTheDocument();
    expect(screen.queryByTestId("notifications-list-skeleton")).not.toBeInTheDocument();
  });

  it("renders real notifications when loaded", () => {
    render(<NotificationsPanel notifications={notifications} />);
    expect(screen.getByText("Messages")).toBeInTheDocument();
    expect(screen.getByText("New message")).toBeInTheDocument();
    expect(screen.queryByTestId("notifications-list-skeleton")).not.toBeInTheDocument();
  });
});
