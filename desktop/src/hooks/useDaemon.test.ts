import { describe, expect, it, vi, beforeEach } from "vitest";
import { renderHook, waitFor, act } from "@testing-library/react";
import { useDaemon } from "./useDaemon";
import type { LocalState, Device } from "../lib/types";

// The IPC layer (both the request/response wrappers and the Tauri
// event subscriptions) is the single seam to the Rust backend; mocking
// it keeps this hook test hermetic (no Tauri runtime needed). Written
// the same way DeviceListPanel.test.tsx/RemoteInputPanel.test.tsx wrap
// their mocks, so outer `const`s referenced inside the vi.mock factory
// are safe under Vitest's hoisting.
// Left untyped (no inline implementation) so each stays inferred as
// the permissive `(...args: any[]) => any` vi.fn() shape -- giving
// these an inline arrow implementation instead pins their arity to
// that implementation's parameter list, which then makes the
// `(...args: unknown[]) => mock(...args)` wrappers below fail to
// typecheck ("a spread argument must either have a tuple type or be
// passed to a rest parameter") since `args` is `unknown[]`, not a
// tuple matching that fixed arity.
const daemonConnected = vi.fn();
const startDaemon = vi.fn((..._args: unknown[]) =>
  Promise.resolve({ ok: true, value: { running: true, reachable: true, rttMs: 1, errorCode: null } }),
);
const getLocalState = vi.fn();
const listDevices = vi.fn();
const onDaemonStatusMock = vi.fn();
const onLocalEventMock = vi.fn();
const onTransferProgressMock = vi.fn();
const onRequestRefreshMock = vi.fn();

vi.mock("../lib/ipc", () => ({
  ipc: {
    daemonConnected: (...args: unknown[]) => daemonConnected(...args),
    startDaemon: (...args: unknown[]) => startDaemon(...args),
    getLocalState: (...args: unknown[]) => getLocalState(...args),
    listDevices: (...args: unknown[]) => listDevices(...args),
  },
  onDaemonStatus: (...args: unknown[]) => onDaemonStatusMock(...args),
  onLocalEvent: (...args: unknown[]) => onLocalEventMock(...args),
  onTransferProgress: (...args: unknown[]) => onTransferProgressMock(...args),
  onRequestRefresh: (...args: unknown[]) => onRequestRefreshMock(...args),
}));

const realState: LocalState = {
  deviceId: "self-1",
  deviceName: "Living Room PC",
  capabilities: ["remote_input", "clipboard_sync"],
  clipboardHistory: [
    { content: "hello world", mimeType: "text/plain", capturedAtMs: 1000, source: "local" },
  ],
  latestBattery: { percentage: 88, isCharging: false, minutesRemaining: 200, reportedAtMs: 1000 },
  notifications: [
    {
      notificationId: "n1",
      appName: "Messages",
      title: "New message",
      body: "Hi there",
      postedAtMs: 1000,
      isDismissal: false,
    },
  ],
  nearbyDevices: [
    { deviceId: "d2", deviceName: "Anil's Phone", platform: "PLATFORM_ANDROID", addr: "192.168.1.20", port: 58231 },
  ],
  remoteInputEnabled: true,
  clipboardSyncEnabled: true,
};

const realDevices: Device[] = [
  { deviceId: "d1", deviceName: "Work Laptop", platform: "PLATFORM_WINDOWS", online: true, pairedAtMs: 1, lastSeenMs: 2 },
];

const emptyState: LocalState = {
  deviceId: "self-1",
  deviceName: "Living Room PC",
  capabilities: [],
  clipboardHistory: [],
  latestBattery: null,
  notifications: [],
  nearbyDevices: [],
  remoteInputEnabled: false,
  clipboardSyncEnabled: false,
};

describe("useDaemon", () => {
  beforeEach(() => {
    daemonConnected.mockReset();
    startDaemon.mockClear();
    getLocalState.mockReset();
    listDevices.mockReset();
    onDaemonStatusMock.mockClear();
    onLocalEventMock.mockClear();
    onTransferProgressMock.mockClear();
    onRequestRefreshMock.mockClear();
    onDaemonStatusMock.mockReturnValue(Promise.resolve(() => {}));
    onLocalEventMock.mockReturnValue(Promise.resolve(() => {}));
    onTransferProgressMock.mockReturnValue(Promise.resolve(() => {}));
    onRequestRefreshMock.mockReturnValue(Promise.resolve(() => {}));
  });

  it("starts in the loading state, not connected, before the first daemon round trip resolves", () => {
    // Never resolves within this test -- exercises the state exactly at
    // mount, before any microtask has had a chance to run.
    daemonConnected.mockReturnValue(new Promise(() => {}));

    const { result } = renderHook(() => useDaemon());

    expect(result.current.loading).toBe(true);
    expect(result.current.connected).toBe(false);
    expect(result.current.devices).toEqual([]);
    expect(result.current.loadError).toBeNull();
  });

  it("populates real state after a successful GetLocalState/ListDevices round trip", async () => {
    daemonConnected.mockResolvedValue({ ok: true, value: true });
    getLocalState.mockResolvedValue({ ok: true, value: realState });
    listDevices.mockResolvedValue({ ok: true, value: realDevices });

    const { result } = renderHook(() => useDaemon());

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.connected).toBe(true);
    expect(result.current.deviceName).toBe("Living Room PC");
    expect(result.current.capabilities).toEqual(["remote_input", "clipboard_sync"]);
    expect(result.current.devices).toEqual(realDevices);
    expect(result.current.nearby).toEqual(realState.nearbyDevices);
    expect(result.current.clipboard).toEqual(realState.clipboardHistory);
    expect(result.current.battery).toEqual(realState.latestBattery);
    expect(result.current.notifications).toEqual(realState.notifications);
    expect(result.current.remoteInputEnabled).toBe(true);
    expect(result.current.clipboardSyncEnabled).toBe(true);
    expect(result.current.loadError).toBeNull();
  });

  it("populates loadError (without getting stuck loading) when the refresh round trip fails", async () => {
    daemonConnected.mockResolvedValue({ ok: true, value: true });
    // getLocalState succeeds, but listDevices -- the second half of the
    // same refresh() -- fails; the final loadError must reflect that
    // failure rather than being silently cleared by the earlier success.
    getLocalState.mockResolvedValue({ ok: true, value: realState });
    listDevices.mockResolvedValue({ ok: false, error: { code: "INTERNAL", message: "boom" } });

    const { result } = renderHook(() => useDaemon());

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.loadError).toEqual({ code: "INTERNAL", message: "boom" });
    // Loading must still flip off on failure (T-311/T-601): an error is
    // a distinct terminal state, not an infinite skeleton.
    expect(result.current.loading).toBe(false);
  });

  it("keeps loadError set when the FIRST fetch fails and the second succeeds (T-X17)", async () => {
    daemonConnected.mockResolvedValue({ ok: true, value: true });
    // The opposite ordering from the test above and the exact T-X17 bug:
    // getLocalState fails, but the immediately-following successful
    // listDevices must NOT clear the error (the old per-branch
    // `setLoadError(null)` did, making clipboard/notification panels look
    // genuinely empty instead of failed).
    getLocalState.mockResolvedValue({ ok: false, error: { code: "INTERNAL", message: "state boom" } });
    listDevices.mockResolvedValue({ ok: true, value: [] });

    const { result } = renderHook(() => useDaemon());

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.loadError).toEqual({ code: "INTERNAL", message: "state boom" });
  });

  it("distinguishes 'loaded and genuinely empty' (loading false, no error) from the initial loading state", async () => {
    daemonConnected.mockResolvedValue({ ok: true, value: true });
    getLocalState.mockResolvedValue({ ok: true, value: emptyState });
    listDevices.mockResolvedValue({ ok: true, value: [] });

    const { result } = renderHook(() => useDaemon());

    // Immediately after mount, still loading -- same shape (empty
    // arrays) as the eventual empty-but-loaded state, so `loading` is
    // the only thing that tells them apart.
    expect(result.current.loading).toBe(true);
    expect(result.current.devices).toEqual([]);

    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.devices).toEqual([]);
    expect(result.current.clipboard).toEqual([]);
    expect(result.current.nearby).toEqual([]);
    // Genuinely empty, not errored -- this is what separates it from
    // the loadError case above even though both end with loading=false.
    expect(result.current.loadError).toBeNull();
  });

  it("does not fetch anything and stays disconnected/loading when the daemon isn't reachable yet", async () => {
    daemonConnected.mockResolvedValue({ ok: true, value: false });

    const { result } = renderHook(() => useDaemon());

    await waitFor(() => expect(daemonConnected).toHaveBeenCalled());

    expect(result.current.connected).toBe(false);
    expect(result.current.loading).toBe(true);
    expect(getLocalState).not.toHaveBeenCalled();
    expect(listDevices).not.toHaveBeenCalled();
  });

  it("applies incoming local events (battery, pairing prompt) pushed from the Tauri event stream", async () => {
    daemonConnected.mockResolvedValue({ ok: true, value: false });

    const { result } = renderHook(() => useDaemon());

    await waitFor(() => expect(onLocalEventMock).toHaveBeenCalled());
    const handler = onLocalEventMock.mock.calls[0][0] as (event: unknown) => void;

    act(() => {
      handler({
        kind: "battery",
        battery: { percentage: 55, isCharging: true, minutesRemaining: 40, reportedAtMs: 5 },
      });
    });
    await waitFor(() => expect(result.current.battery?.percentage).toBe(55));

    act(() => {
      handler({
        kind: "pairingRequested",
        prompt: {
          requesterDeviceId: "d9",
          requesterDeviceName: "New Phone",
          pinCode: "123456",
          pinExpiresAtMs: 9999,
        },
      });
    });
    await waitFor(() =>
      expect(result.current.pairingPrompt?.requesterDeviceName).toBe("New Phone"),
    );

    act(() => {
      result.current.dismissPairingPrompt();
    });
    expect(result.current.pairingPrompt).toBeNull();
  });

  // T-X9: the poll below is the only thing that makes a newly appeared
  // device show up "automatically" (no DeviceListChanged push event
  // exists), so these two tests pin the polling contract itself.
  it("polls every 5s while visible: a device appearing daemon-side shows up with no manual refresh", async () => {
    vi.useFakeTimers();
    try {
      daemonConnected.mockResolvedValue({ ok: true, value: true });
      getLocalState.mockResolvedValue({ ok: true, value: emptyState });
      listDevices.mockResolvedValue({ ok: true, value: [] });

      const { result, unmount } = renderHook(() => useDaemon());
      await act(async () => {
        await vi.advanceTimersByTimeAsync(0);
      });
      expect(result.current.devices).toEqual([]);
      expect(result.current.nearby).toEqual([]);

      // A new paired device and a new nearby peer appear in the
      // daemon's responses; the UI must pick them up on its own.
      getLocalState.mockResolvedValue({ ok: true, value: realState });
      listDevices.mockResolvedValue({ ok: true, value: realDevices });

      await act(async () => {
        await vi.advanceTimersByTimeAsync(5000);
      });

      expect(result.current.devices).toEqual(realDevices);
      expect(result.current.nearby).toEqual(realState.nearbyDevices);
      unmount();
    } finally {
      vi.useRealTimers();
    }
  });

  it("pauses polling while the document is hidden and catches up immediately when shown again", async () => {
    vi.useFakeTimers();
    try {
      daemonConnected.mockResolvedValue({ ok: true, value: true });
      getLocalState.mockResolvedValue({ ok: true, value: emptyState });
      listDevices.mockResolvedValue({ ok: true, value: [] });

      const { unmount } = renderHook(() => useDaemon());
      await act(async () => {
        await vi.advanceTimersByTimeAsync(0);
      });
      const afterInit = listDevices.mock.calls.length;

      await act(async () => {
        setDocumentVisibility("hidden");
        await vi.advanceTimersByTimeAsync(0);
      });
      await act(async () => {
        await vi.advanceTimersByTimeAsync(20000);
      });
      // Four intervals' worth of time elapsed hidden: zero polls.
      expect(listDevices.mock.calls.length).toBe(afterInit);

      await act(async () => {
        setDocumentVisibility("visible");
        await vi.advanceTimersByTimeAsync(0);
      });
      // Becoming visible triggers an immediate catch-up refresh...
      expect(listDevices.mock.calls.length).toBe(afterInit + 1);

      await act(async () => {
        await vi.advanceTimersByTimeAsync(5000);
      });
      // ...and the 5s cadence resumes.
      expect(listDevices.mock.calls.length).toBe(afterInit + 2);
      unmount();
    } finally {
      // Unshadow the prototype getter so later tests see jsdom's own
      // (always "visible") value again.
      Reflect.deleteProperty(document, "visibilityState");
      vi.useRealTimers();
    }
  });
});

// Overrides jsdom's read-only Document.prototype.visibilityState with
// an own-property getter (configurable, so tests can delete it to
// restore the original), then fires the visibilitychange event the
// hook listens for -- the same sequence a real hide/show produces.
function setDocumentVisibility(state: DocumentVisibilityState) {
  Object.defineProperty(document, "visibilityState", {
    configurable: true,
    get: () => state,
  });
  document.dispatchEvent(new Event("visibilitychange"));
}
