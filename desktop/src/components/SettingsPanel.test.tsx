import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { SettingsPanel } from "./SettingsPanel";

const daemonStatus = vi.fn();
const startDaemon = vi.fn();
const stopDaemon = vi.fn();
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
    startDaemon.mockReset();
    stopDaemon.mockReset();
    getDownloadDir.mockClear();
    setDownloadDir.mockClear();
    dialogOpen.mockClear();
    openPath.mockClear();
  });

  it("renders real about data (device name, version) and the theme options", () => {
    render(
      <SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Living Room PC" appVersion="0.4.2" />,
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
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" />);

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
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" />);
    await screen.findByText("/home/me/Downloads");
    fireEvent.click(screen.getByRole("button", { name: "Change..." }));
    await waitFor(() => expect(dialogOpen).toHaveBeenCalled());
    expect(setDownloadDir).not.toHaveBeenCalled();
  });

  it("falls back to a placeholder when there is no device name yet, distinct from a real name", () => {
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="" appVersion="0.4.2" />);
    expect(screen.getByText("-")).toBeInTheDocument();
  });

  it("shows a checking placeholder before any daemon status has loaded", () => {
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" />);
    expect(screen.getByText("Checking...")).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("marks the active theme as pressed and calls onThemeChange when another is picked", () => {
    const onThemeChange = vi.fn();
    render(<SettingsPanel theme="onyx" onThemeChange={onThemeChange} deviceName="Me" appVersion="0.1.0" />);
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
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" />);

    fireEvent.click(screen.getByRole("button", { name: "Refresh" }));

    await waitFor(() => expect(screen.getByText(/Running/)).toBeInTheDocument());
    expect(screen.getByText(/Reachable/)).toBeInTheDocument();
    expect(screen.getByText(/RTT: 8ms/)).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("shows a distinct error banner, mapped from ErrorCode, when the status check itself fails (T-103/T-602)", async () => {
    daemonStatus.mockResolvedValue({
      ok: false,
      error: { code: "INTERNAL", message: "raw grpc status text" },
    });
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" />);

    fireEvent.click(screen.getByRole("button", { name: "Refresh" }));

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(
      "The daemon hit an internal error. Try again, and check the daemon logs if it persists.",
    );
    expect(alert).not.toHaveTextContent("raw grpc status text");
  });

  it("starts the daemon and reflects the new status on success (T-103)", async () => {
    startDaemon.mockResolvedValue({
      ok: true,
      value: { running: true, reachable: false, rttMs: null, errorCode: null },
    });
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" />);

    fireEvent.click(screen.getByRole("button", { name: "Start daemon" }));

    await waitFor(() => expect(screen.getByText(/Running/)).toBeInTheDocument());
    expect(startDaemon).toHaveBeenCalled();
    // Running-but-unreachable now shows the Stop button instead of Start.
    expect(screen.getByRole("button", { name: "Stop daemon" })).toBeInTheDocument();
  });

  it("surfaces a start-daemon failure as an error banner instead of throwing (T-103)", async () => {
    startDaemon.mockResolvedValue({
      ok: false,
      error: { code: "UNSPECIFIED", message: "spawn failed" },
    });
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" />);

    fireEvent.click(screen.getByRole("button", { name: "Start daemon" }));

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
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" />);

    // Get into the "running" state first so the Stop button is visible.
    fireEvent.click(screen.getByRole("button", { name: "Refresh" }));
    await waitFor(() => expect(screen.getByRole("button", { name: "Stop daemon" })).toBeInTheDocument());

    fireEvent.click(screen.getByRole("button", { name: "Stop daemon" }));

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent(
      "The daemon hit an internal error. Try again, and check the daemon logs if it persists.",
    );
    // stopDaemon failing short-circuits before the status re-check.
    expect(daemonStatus).toHaveBeenCalledTimes(1);
  });

  it("shows the daemon's own reported errorCode distinctly from an action error", async () => {
    daemonStatus.mockResolvedValue({
      ok: true,
      value: { running: false, reachable: false, rttMs: null, errorCode: "RATE_LIMITED" },
    });
    render(<SettingsPanel theme="charcoal" onThemeChange={vi.fn()} deviceName="Me" appVersion="0.1.0" />);

    fireEvent.click(screen.getByRole("button", { name: "Refresh" }));

    await waitFor(() =>
      expect(screen.getByText("Too many attempts -- wait a moment before retrying.")).toBeInTheDocument(),
    );
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });
});
