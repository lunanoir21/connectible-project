import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { TransferPanel } from "./TransferPanel";
import type { Device, TransferHistoryEntry, TransferProgress } from "../lib/types";

function device(over: Partial<Device>): Device {
  return {
    deviceId: "dev-1",
    deviceName: "A Device",
    platform: "PLATFORM_ANDROID",
    online: true,
    pairedAtMs: 0,
    lastSeenMs: 0,
    ...over,
  };
}

function historyEntry(over: Partial<TransferHistoryEntry>): TransferHistoryEntry {
  return {
    transferId: "h1",
    peerDeviceId: "dev-1",
    fileName: "file.bin",
    totalBytes: 100,
    direction: "incoming",
    status: "completed",
    startedAtMs: 1000,
    finishedAtMs: 2000,
    ...over,
  };
}

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
const listTransferHistory = vi.fn(
  (): Promise<{ ok: true; value: TransferHistoryEntry[] }> =>
    Promise.resolve({ ok: true, value: [] }),
);
vi.mock("../lib/ipc", () => ({
  ipc: {
    sendFile: vi.fn(),
    cancelTransfer: (...args: unknown[]) => cancelTransfer(...args),
    getDownloadDir: vi.fn(() => Promise.resolve({ ok: true, value: "/home/me/Downloads" })),
    openPath: vi.fn(() => Promise.resolve({ ok: true, value: null })),
    listTransferHistory: () => listTransferHistory(),
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
    mimeType: "",
    ...over,
  };
}

describe("TransferPanel", () => {
  beforeEach(() => {
    cancelTransfer.mockReset();
    listTransferHistory.mockReset();
    listTransferHistory.mockResolvedValue({ ok: true, value: [] });
  });

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

  // Phase J: a transfer that finished before this app launch (no live
  // `transfers` prop entry at all) still shows up, sourced from the
  // daemon's persisted history rather than the in-memory map.
  it("shows a persisted history entry from a previous session, surviving a restart", async () => {
    const entry: TransferHistoryEntry = {
      transferId: "old-1",
      peerDeviceId: "dev-1",
      fileName: "archive.zip",
      totalBytes: 4096,
      direction: "incoming",
      status: "completed",
      startedAtMs: 1000,
      finishedAtMs: 2000,
    };
    listTransferHistory.mockResolvedValue({ ok: true, value: [entry] });

    render(<TransferPanel transfers={{}} devices={[]} nearby={[]} />);

    await waitFor(() => expect(screen.getByText("archive.zip")).toBeInTheDocument());
    expect(screen.getByText(/Completed/)).toBeInTheDocument();
  });

  // A transfer that just finished in this session (present in the live
  // `transfers` prop) must not also render a duplicate row once the
  // persisted-history fetch resolves with the same transferId.
  it("does not duplicate a transfer that is both live and persisted", async () => {
    const entry: TransferHistoryEntry = {
      transferId: "t2",
      peerDeviceId: "dev-1",
      fileName: "doc.pdf",
      totalBytes: 200,
      direction: "incoming",
      status: "completed",
      startedAtMs: 1000,
      finishedAtMs: 2000,
    };
    listTransferHistory.mockResolvedValue({ ok: true, value: [entry] });

    const transfers = {
      t2: progress({ transferId: "t2", fileName: "doc.pdf", bytesTransferred: 200, completed: true, direction: "incoming" }),
    };
    render(<TransferPanel transfers={transfers} devices={[]} nearby={[]} />);

    await waitFor(() => expect(listTransferHistory).toHaveBeenCalled());
    expect(screen.getAllByText("doc.pdf")).toHaveLength(1);
  });

  // T-X16(c): a restored *canceled* transfer is terminal, not active --
  // it must not render a working Cancel button (the pre-fix bug, where
  // canceled mapped to failed:false made it look in-flight).
  it("renders a restored canceled transfer as terminal, with no cancel button (T-X16)", async () => {
    listTransferHistory.mockResolvedValue({
      ok: true,
      value: [historyEntry({ transferId: "c1", fileName: "aborted.bin", direction: "outgoing", status: "canceled" })],
    });
    render(<TransferPanel transfers={{}} devices={[]} nearby={[]} />);

    await waitFor(() => expect(screen.getByText("aborted.bin")).toBeInTheDocument());
    expect(screen.getByText(/Canceled/)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Cancel transfer" })).not.toBeInTheDocument();
  });

  // T-X16(a): persisted history rows show peer name (resolved from the
  // devices list, falling back to a shortened id) and a finished time.
  it("shows peer name (or a shortened id) and time on persisted history rows (T-X16)", async () => {
    listTransferHistory.mockResolvedValue({
      ok: true,
      value: [
        historyEntry({ transferId: "known", fileName: "known.bin", peerDeviceId: "dev-1" }),
        historyEntry({ transferId: "unknown", fileName: "unknown.bin", peerDeviceId: "abcdef1234567890" }),
      ],
    });
    render(
      <TransferPanel
        transfers={{}}
        devices={[device({ deviceId: "dev-1", deviceName: "Anil's Phone" })]}
        nearby={[]}
      />,
    );

    // Known peer resolves to its friendly name...
    await waitFor(() => expect(screen.getByText(/Anil's Phone/)).toBeInTheDocument());
    // ...an unknown peer falls back to a shortened id, never a blank.
    expect(screen.getByText(/abcdef12\.\.\./)).toBeInTheDocument();
  });

  // T-X16(b): merged history is ordered by finish time, most recent first,
  // not by transferId hash.
  it("orders history rows by finish time, most recent first (T-X16)", async () => {
    listTransferHistory.mockResolvedValue({
      ok: true,
      value: [
        historyEntry({ transferId: "older", fileName: "older.bin", finishedAtMs: 1000 }),
        historyEntry({ transferId: "newer", fileName: "newer.bin", finishedAtMs: 9000 }),
      ],
    });
    render(<TransferPanel transfers={{}} devices={[]} nearby={[]} />);

    await waitFor(() => expect(screen.getByText("newer.bin")).toBeInTheDocument());
    const newer = screen.getByText("newer.bin");
    const older = screen.getByText("older.bin");
    // newer precedes older in document order.
    expect(newer.compareDocumentPosition(older) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });
});
