import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { SettingsPanel } from "./SettingsPanel";

const daemonStatus = vi.fn();
const startDaemon = vi.fn();
const stopDaemon = vi.fn();
const setClipboardSyncEnabled = vi.fn();
// Never resolves by default so the mount-time fetch leaves no dangling
// state update in the many tests that don't exercise the folder picker
// (which would otherwise fire an act() warning). The two folder tests
// give it a resolving value with mockReturnValueOnce.
const getDownloadDir = vi.fn((..._args: unknown[]): Promise<unknown> => new Promise(() => {}));
const setDownloadDir = vi.fn(
  (..._args: unknown[]): Promise<unknown> => Promise.resolve({ ok: true, value: "/home/me/Downloads" }),
);
vi.mock("../lib/ipc", () => ({
  ipc: {
    daemonStatus: (...args: unknown[]) => daemonStatus(...args),
    startDaemon: (...args: unknown[]) => startDaemon(...args),
    stopDaemon: (...args: unknown[]) => stopDaemon(...args),
    getDownloadDir: (...args: unknown[]) => getDownloadDir(...args),
    setDownloadDir: (...args: unknown[]) => setDownloadDir(...args),
    openPath: (...args: unknown[]) => openPath(...args),
    setClipboardSyncEnabled: (...args: unknown[]) => setClipboardSyncEnabled(...args),
  },
}));

const dialogOpen = vi.fn((..._args: unknown[]): Promise<string | null> => Promise.resolve(null));
vi.mock("@tauri-apps/plugin-dialog", () => ({
  open: (...args: unknown[]) => dialogOpen(...args),
}));

// The received-files "Open" button now goes through the native ipc
// command (commands::open_path), not the opener plugin.
const openPath = vi.fn((..._args: unknown[]) => Promise.resolve({ ok: true, value: null }));

describe("SettingsPanel", () => {
  beforeEach(() => {
    daemonStatus.mockReset();
    // The panel now fetches daemon status once on mount (T-103
    // follow-up), on top of the explicit Refresh button -- so every
    // test now triggers at least one daemonStatus() call whether it
    // cares or not. Default to never-resolving (same rationale as
    // getDownloadDir above) so tests that don't care about daemon
    // status leave no dangling state update / act() warning; tests
    // that do care call mockResolvedValue again before render, which
    // overrides this.
    daemonStatus.mockReturnValue(new Promise(() => {}));
    startDaemon.mockReset();
    stopDaemon.mockReset();
    setClipboardSyncEnabled.mockReset();
    getDownloadDir.mockClear();
    setDownloadDir.mockClear();
    dialogOpen.mockClear();
    openPath.mockClear();
  });

  it("renders real about data (device name, version) and the theme options", () => {
    render(
      <SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Living Room PC" appVersion="0.4.2" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />,
    );
    expect(screen.getByText("Living Room PC")).toBeInTheDocument();
    expect(screen.getByText("0.4.2")).toBeInTheDocument();
    expect(screen.getByText("Charcoal")).toBeInTheDocument();
    expect(screen.getByText("Onyx")).toBeInTheDocument();
    expect(screen.getByText("Graphite")).toBeInTheDocument();
  });

  it("shows the resolved received-files folder and persists a newly picked one", async () => {
    getDownloadDir.mockReturnValueOnce(Promise.resolve({ ok: true, value: "/home/me/Downloads" }));
    dialogOpen.mockResolvedValueOnce("/home/me/Desktop/Incoming");
    setDownloadDir.mockResolvedValueOnce({ ok: true, value: "/home/me/Desktop/Incoming" });
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);

    // Effective folder is fetched and shown.
    expect(await screen.findByText("/home/me/Downloads")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Change..." }));
    await waitFor(() => expect(setDownloadDir).toHaveBeenCalledWith("/home/me/Desktop/Incoming"));
    // Display updates to the new folder.
    expect(await screen.findByText("/home/me/Desktop/Incoming")).toBeInTheDocument();
  });

  it("does not persist a folder change when the picker is dismissed", async () => {
    getDownloadDir.mockReturnValueOnce(Promise.resolve({ ok: true, value: "/home/me/Downloads" }));
    dialogOpen.mockResolvedValueOnce(null);
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);
    await screen.findByText("/home/me/Downloads");
    fireEvent.click(screen.getByRole("button", { name: "Change..." }));
    await waitFor(() => expect(dialogOpen).toHaveBeenCalled());
    expect(setDownloadDir).not.toHaveBeenCalled();
  });

  it("surfaces an error instead of an eternal Loading... when getDownloadDir fails (T-X30)", async () => {
    getDownloadDir.mockReturnValueOnce(
      Promise.resolve({ ok: false, error: { code: "INTERNAL", message: "disk error" } }),
    );
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);

    expect(
      await screen.findByText(
        "The daemon hit an internal error. Try again, and check the daemon logs if it persists.",
      ),
    ).toBeInTheDocument();
    // The folder row stays on the loading placeholder rather than
    // silently resolving to nothing -- the point is the error is
    // surfaced, not that the row itself changes.
    expect(screen.getByText("Loading...")).toBeInTheDocument();
  });

  it("falls back to a placeholder when there is no device name yet, distinct from a real name", () => {
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="" appVersion="0.4.2" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);
    expect(screen.getByText("-")).toBeInTheDocument();
  });

  it("shows a checking placeholder before any daemon status has loaded", () => {
    // Never resolves, so the mount-time auto-fetch (T-103 follow-up)
    // leaves the panel sitting in its "checking" state for the
    // assertions below, same as before that auto-fetch existed.
    daemonStatus.mockReturnValue(new Promise(() => {}));
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);
    // "Checking..." now appears twice while a check is in flight: once
    // in the connection status row, once as the Refresh button's own
    // label -- both are the checking placeholder this test cares about.
    expect(screen.getAllByText("Checking...").length).toBeGreaterThan(0);
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("marks the active theme as pressed and calls onThemeChange when another is picked", () => {
    const onThemeChange = vi.fn();
    render(<SettingsPanel theme="onyx" onThemeChange={onThemeChange} deviceName="Me" appVersion="0.1.0" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);
    expect(screen.getByRole("button", { name: /Onyx/ })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("button", { name: /Charcoal/ })).toHaveAttribute("aria-pressed", "false");

    fireEvent.click(screen.getByRole("button", { name: /Graphite/ }));
    expect(onThemeChange).toHaveBeenCalledWith("graphite");
  });

  it("refreshes and renders real running/reachable daemon status on success", async () => {
    daemonStatus.mockResolvedValue({
      ok: true,
      value: { running: true, reachable: true, rttMs: 8, errorCode: null },
    });
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);

    // The mount-time auto-fetch (T-103 follow-up) leaves the Refresh
    // button reading "Checking..." for a tick, so wait for it to settle
    // back before clicking it explicitly.
    fireEvent.click(await screen.findByRole("button", { name: "Refresh" }));

    await waitFor(() => expect(screen.getByText(/Reachable/)).toBeInTheDocument());
    expect(screen.getByText(/RTT: 8ms/)).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("shows a genuinely 0ms RTT instead of hiding it as falsy (T-X30)", async () => {
    daemonStatus.mockResolvedValue({
      ok: true,
      value: { running: true, reachable: true, rttMs: 0, errorCode: null },
    });
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);

    fireEvent.click(await screen.findByRole("button", { name: "Refresh" }));

    await waitFor(() => expect(screen.getByText(/Reachable/)).toBeInTheDocument());
    expect(screen.getByText(/RTT: 0ms/)).toBeInTheDocument();
  });

  it("shows a distinct error banner, mapped from ErrorCode, when the status check itself fails (T-103/T-602)", async () => {
    daemonStatus.mockResolvedValue({
      ok: false,
      error: { code: "INTERNAL", message: "raw grpc status text" },
    });
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(
      "The daemon hit an internal error. Try again, and check the daemon logs if it persists.",
    );
    expect(alert).not.toHaveTextContent("raw grpc status text");
  });

  it("starts the daemon and reflects the new status on success (T-103)", async () => {
    // Mount-time auto-fetch needs a resolved value too, so the panel
    // settles into "Start daemon" before the test clicks it.
    daemonStatus.mockResolvedValue({
      ok: true,
      value: { running: false, reachable: false, rttMs: null, errorCode: null },
    });
    startDaemon.mockResolvedValue({
      ok: true,
      value: { running: true, reachable: false, rttMs: null, errorCode: null },
    });
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);

    fireEvent.click(await screen.findByRole("button", { name: "Start daemon" }));

    await waitFor(() => expect(screen.getByText(/Unreachable/)).toBeInTheDocument());
    expect(startDaemon).toHaveBeenCalled();
    // Running-but-unreachable now shows the Stop button instead of Start.
    expect(screen.getByRole("button", { name: "Stop daemon" })).toBeInTheDocument();
  });

  it("surfaces a start-daemon failure as an error banner instead of throwing (T-103)", async () => {
    daemonStatus.mockResolvedValue({
      ok: true,
      value: { running: false, reachable: false, rttMs: null, errorCode: null },
    });
    startDaemon.mockResolvedValue({
      ok: false,
      error: { code: "UNSPECIFIED", message: "spawn failed" },
    });
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);

    fireEvent.click(await screen.findByRole("button", { name: "Start daemon" }));

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(
      "Something went wrong. Try again, and check the daemon logs if it persists.",
    );
    expect(alert).not.toHaveTextContent("spawn failed");
  });

  it("stops the daemon, re-checks status, and surfaces a stop failure distinctly from a status-check failure (T-103)", async () => {
    stopDaemon.mockResolvedValue({ ok: false, error: { code: "INTERNAL", message: "stop failed" } });
    daemonStatus.mockResolvedValue({
      ok: true,
      value: { running: true, reachable: true, rttMs: 5, errorCode: null },
    });
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);

    // The mount-time auto-fetch (T-103 follow-up) already lands the
    // panel in the "running" state, so the Stop button shows up without
    // an explicit Refresh click.
    await waitFor(() => expect(screen.getByRole("button", { name: "Stop daemon" })).toBeInTheDocument());
    daemonStatus.mockClear();

    fireEvent.click(screen.getByRole("button", { name: "Stop daemon" }));

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(
      "The daemon hit an internal error. Try again, and check the daemon logs if it persists.",
    );
    // stopDaemon failing short-circuits before the status re-check.
    expect(daemonStatus).not.toHaveBeenCalled();
  });

  it("shows an externally-managed notice when Stop had no process of its own to kill (T-X11)", async () => {
    // ok:true but value:false = the app did not spawn the running daemon.
    stopDaemon.mockResolvedValue({ ok: true, value: false });
    daemonStatus.mockResolvedValue({
      ok: true,
      value: { running: true, reachable: true, rttMs: 5, errorCode: null },
    });
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);
    await waitFor(() => expect(screen.getByRole("button", { name: "Stop daemon" })).toBeInTheDocument());

    fireEvent.click(screen.getByRole("button", { name: "Stop daemon" }));

    const notice = await screen.findByRole("status");
    expect(notice).toHaveTextContent("managed externally");
    // A neutral notice, not an error.
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("shows no notice when Stop actually killed the app-spawned daemon (T-X11)", async () => {
    stopDaemon.mockResolvedValue({ ok: true, value: true });
    // Mount status is running so the Stop button is present to click.
    daemonStatus.mockResolvedValue({
      ok: true,
      value: { running: true, reachable: true, rttMs: 5, errorCode: null },
    });
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);
    await waitFor(() => expect(screen.getByRole("button", { name: "Stop daemon" })).toBeInTheDocument());

    fireEvent.click(screen.getByRole("button", { name: "Stop daemon" }));
    // Let the click's async handler settle, then assert no notice.
    await waitFor(() => expect(stopDaemon).toHaveBeenCalled());
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });

  it("shows the daemon's own reported errorCode distinctly from an action error", async () => {
    daemonStatus.mockResolvedValue({
      ok: true,
      value: { running: false, reachable: false, rttMs: null, errorCode: "RATE_LIMITED" },
    });
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" onOpenPairingQr={vi.fn()} clipboardSyncEnabled={false} onClipboardSyncRefresh={vi.fn()} />);

    await waitFor(() =>
      expect(screen.getByText("Too many attempts -- wait a moment before retrying.")).toBeInTheDocument(),
    );
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("shows a clipboard-sync toggle wired to setClipboardSyncEnabled (T-310)", async () => {
    setClipboardSyncEnabled.mockResolvedValue({ ok: true, value: true });
    const onClipboardSyncRefresh = vi.fn();
    render(
      <SettingsPanel
        theme="charcoal"
        onThemeChange={vi.fn()}
        deviceName="Me"
        appVersion="0.1.0"
        onOpenPairingQr={vi.fn()}
        clipboardSyncEnabled={false}
        onClipboardSyncRefresh={onClipboardSyncRefresh}
      />,
    );

    const toggle = screen.getByRole("switch", { name: "Toggle clipboard sync" });
    expect(toggle).toHaveAttribute("aria-checked", "false");

    fireEvent.click(toggle);

    await waitFor(() => expect(onClipboardSyncRefresh).toHaveBeenCalled());
    expect(setClipboardSyncEnabled).toHaveBeenCalledWith(true);
  });

  it("surfaces a clipboard-sync toggle failure instead of throwing, mapped from its ErrorCode (T-602)", async () => {
    setClipboardSyncEnabled.mockResolvedValue({
      ok: false,
      error: { code: "UNSPECIFIED", message: "daemon not connected yet" },
    });
    render(
      <SettingsPanel
        theme="charcoal"
        onThemeChange={vi.fn()}
        deviceName="Me"
        appVersion="0.1.0"
        onOpenPairingQr={vi.fn()}
        clipboardSyncEnabled={false}
        onClipboardSyncRefresh={vi.fn()}
      />,
    );

    fireEvent.click(screen.getByRole("switch", { name: "Toggle clipboard sync" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Something went wrong. Try again, and check the daemon logs if it persists.",
    );
  });
});
