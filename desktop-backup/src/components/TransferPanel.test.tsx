import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { TransferPanel } from "./TransferPanel";
import type { TransferProgress } from "../lib/types";

const cancelTransfer = vi.fn();
vi.mock("@tauri-apps/plugin-dialog", () => ({ open: vi.fn() }));
// Drag-and-drop send subscribes to the webview's drag-drop event on
// mount; in jsdom there is no Tauri bridge, so provide a no-op that
// resolves to an unlisten fn (the component also guards this at runtime).
vi.mock("@tauri-apps/api/webview", () => ({
  getCurrentWebview: () => ({
    onDragDropEvent: () => Promise.resolve(() => {}),
  }),
}));
vi.mock("../lib/ipc", () => ({
  ipc: {
    sendFile: vi.fn(),
    cancelTransfer: (...args: unknown[]) => cancelTransfer(...args),
    getDownloadDir: vi.fn(() => Promise.resolve({ ok: true, value: "/home/me/Downloads" })),
    openPath: vi.fn(() => Promise.resolve({ ok: true, value: null })),
  },
}));

function progress(over: Partial<TransferProgress>): TransferProgress {
  return {
    transferId: "t1",
    fileName: "photo.png",
    bytesTransferred: 50,
    totalBytes: 200,
    completed: false,
    failed: false,
    canceled: false,
    direction: "outgoing",
    ...over,
  };
}

describe("TransferPanel", () => {
  beforeEach(() => cancelTransfer.mockReset());

  it("shows an empty state with no transfers", () => {
    render(<TransferPanel transfers={{}} devices={[]} nearby={[]} />);
    expect(screen.getByText("No transfers yet")).toBeInTheDocument();
  });

  it("shows a loading skeleton before the first snapshot loads, distinct from the empty state (T-601)", () => {
    render(<TransferPanel transfers={{}} devices={[]} nearby={[]} loading />);
    expect(screen.getByTestId("transfer-list-skeleton")).toBeInTheDocument();
    expect(screen.queryByText("No transfers yet")).not.toBeInTheDocument();
  });

  it("shows a distinct error state when the initial fetch failed, not the empty state (T-601/T-602)", () => {
    render(
      <TransferPanel
        transfers={{}}
        devices={[]}
        nearby={[]}
        loading={false}
        loadError={{ code: "INTERNAL", message: "raw grpc text" }}
        onRefresh={vi.fn()}
      />,
    );
    const alert = screen.getByRole("alert");
    expect(alert).toHaveTextContent(
      "The daemon hit an internal error. Try again, and check the daemon logs if it persists.",
    );
    expect(alert).not.toHaveTextContent("raw grpc text");
    expect(screen.queryByText("No transfers yet")).not.toBeInTheDocument();
    expect(screen.queryByTestId("transfer-list-skeleton")).not.toBeInTheDocument();
  });

  it("renders a progress bar reflecting the transferred fraction", () => {
    render(<TransferPanel transfers={{ t1: progress({}) }} devices={[]} nearby={[]} />);

    expect(screen.getByText("photo.png")).toBeInTheDocument();
    const bar = screen.getByRole("progressbar");
    expect(bar).toHaveAttribute("aria-valuenow", "25");
    expect(screen.getByText(/Sending/)).toBeInTheDocument();
  });

  it("marks a completed transfer distinctly", () => {
    const transfers = {
      t2: progress({ transferId: "t2", fileName: "doc.pdf", bytesTransferred: 200, completed: true, direction: "incoming" }),
    };
    render(<TransferPanel transfers={transfers} devices={[]} nearby={[]} />);
    expect(screen.getByText(/Completed/)).toBeInTheDocument();
    expect(screen.getByRole("progressbar")).toHaveAttribute("aria-valuenow", "100");
  });

  it("cancels an in-flight outgoing transfer", () => {
    render(<TransferPanel transfers={{ t1: progress({}) }} devices={[]} nearby={[]} />);
    fireEvent.click(screen.getByRole("button", { name: "Cancel transfer" }));
    expect(cancelTransfer).toHaveBeenCalledWith("t1");
  });

  it("shows a canceled transfer and offers no cancel button", () => {
    render(
      <TransferPanel
        transfers={{ t1: progress({ failed: true, canceled: true }) }}
        devices={[]}
        nearby={[]}
      />,
    );
    expect(screen.getByText(/Canceled/)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Cancel transfer" })).not.toBeInTheDocument();
  });

  it("offers no cancel button for incoming transfers", () => {
    render(
      <TransferPanel
        transfers={{ t3: progress({ transferId: "t3", direction: "incoming" }) }}
        devices={[]}
        nearby={[]}
      />,
    );
    expect(screen.queryByRole("button", { name: "Cancel transfer" })).not.toBeInTheDocument();
  });
});
