import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { HomePanel } from "./HomePanel";
import type { Device, NearbyDevice } from "../lib/types";

const pairWithDevice = vi.fn();
const disconnectDevice = vi.fn();
const forgetDevice = vi.fn();
const localAddresses = vi.fn((..._args: unknown[]) =>
  Promise.resolve({ ok: true, value: { addresses: ["192.168.1.50"], port: 58231 } }),
);
vi.mock("../lib/ipc", () => ({
  ipc: {
    pairWithDevice: (...args: unknown[]) => pairWithDevice(...args),
    disconnectDevice: (...args: unknown[]) => disconnectDevice(...args),
    forgetDevice: (...args: unknown[]) => forgetDevice(...args),
    localAddresses: (...args: unknown[]) => localAddresses(...args),
  },
}));

const writeText = vi.fn((..._args: unknown[]) => Promise.resolve());
vi.mock("@tauri-apps/plugin-clipboard-manager", () => ({
  writeText: (...args: unknown[]) => writeText(...args),
}));

const pairedPhone: Device = {
  deviceId: "d1",
  deviceName: "Anil Phone",
  platform: "PLATFORM_ANDROID",
  online: true,
  pairedAtMs: 0,
  lastSeenMs: 0,
};

const nearbyDesktop: NearbyDevice = {
  deviceId: "d2",
  deviceName: "Linux Box",
  platform: "PLATFORM_LINUX_X11",
  addr: "192.168.1.30",
  port: 58231,
};

const nearbyPhone: NearbyDevice = {
  deviceId: "d3",
  deviceName: "Pixel",
  platform: "PLATFORM_ANDROID",
  addr: "192.168.1.31",
  port: 58231,
};

describe("HomePanel", () => {
  beforeEach(() => {
    pairWithDevice.mockReset();
    disconnectDevice.mockReset();
    forgetDevice.mockReset();
    writeText.mockClear();
    localAddresses.mockClear();
    // Forgetting now asks for confirmation first; default to "confirmed"
    // so the existing forget test exercises the same flow as before.
    // The dedicated cancel test below overrides this per-call.
    vi.spyOn(window, "confirm").mockReturnValue(true);
  });

  it("shows the real peer-connection status, not local-daemon liveness", () => {
    const { rerender } = render(
      <HomePanel
        deviceName="Me"
        devices={[]}
        nearby={[]}
        onPairStarted={vi.fn()}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );
    expect(screen.getByText("No paired devices yet")).toBeInTheDocument();

    rerender(
      <HomePanel
        deviceName="Me"
        devices={[pairedPhone]}
        nearby={[]}
        onPairStarted={vi.fn()}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );
    expect(screen.getByText("Connected to Anil Phone")).toBeInTheDocument();

    rerender(
      <HomePanel
        deviceName="Me"
        devices={[{ ...pairedPhone, online: false }]}
        nearby={[]}
        onPairStarted={vi.fn()}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );
    expect(screen.getByText("No device connected")).toBeInTheDocument();
  });

  it("starts pairing when a nearby device's constellation star is clicked", async () => {
    pairWithDevice.mockResolvedValue({ ok: true, value: { accepted: true, pinExpiresAtMs: 123 } });
    const onPairStarted = vi.fn();
    render(
      <HomePanel
        deviceName="Me"
        devices={[]}
        nearby={[nearbyDesktop]}
        onPairStarted={onPairStarted}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /Linux Box/ }));
    await waitFor(() => expect(onPairStarted).toHaveBeenCalled());
    expect(pairWithDevice).toHaveBeenCalledWith("192.168.1.30", 58231);
  });

  it("starts pairing when a nearby phone's star is clicked (phones run a server too)", async () => {
    pairWithDevice.mockResolvedValue({ ok: true, value: { accepted: true, pinExpiresAtMs: 123 } });
    const onPairStarted = vi.fn();
    render(
      <HomePanel
        deviceName="Me"
        devices={[]}
        nearby={[nearbyPhone]}
        onPairStarted={onPairStarted}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /Pixel/ }));
    await waitFor(() => expect(onPairStarted).toHaveBeenCalled());
    expect(pairWithDevice).toHaveBeenCalledWith("192.168.1.31", 58231);
  });

  it("pairs by manually typed address when mDNS discovery is unavailable", async () => {
    pairWithDevice.mockResolvedValue({ ok: true, value: { accepted: true, pinExpiresAtMs: 123 } });
    const onPairStarted = vi.fn();
    render(
      <HomePanel
        deviceName="Me"
        devices={[]}
        nearby={[]}
        onPairStarted={onPairStarted}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: /Connect by address/ }));
    fireEvent.change(screen.getByLabelText("IP address"), { target: { value: "192.168.1.42" } });
    fireEvent.change(screen.getByLabelText("Port"), { target: { value: "58231" } });
    fireEvent.click(screen.getByRole("button", { name: "Connect" }));

    await waitFor(() => expect(pairWithDevice).toHaveBeenCalledWith("192.168.1.42", 58231));
    await waitFor(() => expect(onPairStarted).toHaveBeenCalled());
  });

  it("shows this device's own LAN address and copies it on click", async () => {
    render(
      <HomePanel
        deviceName="Me"
        devices={[]}
        nearby={[]}
        onPairStarted={vi.fn()}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: /Connect by address/ }));
    const ownAddress = await screen.findByRole("button", { name: /192\.168\.1\.50:58231/ });
    fireEvent.click(ownAddress);
    await waitFor(() => expect(writeText).toHaveBeenCalledWith("192.168.1.50:58231"));
  });

  it("rejects an empty or invalid manual address before dialing", async () => {
    render(
      <HomePanel
        deviceName="Me"
        devices={[]}
        nearby={[]}
        onPairStarted={vi.fn()}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: /Connect by address/ }));
    // Let the own-address effect settle so its state update doesn't
    // land outside act() after the synchronous assertions below.
    await screen.findByLabelText("IP address");
    // Blank address -> validation error, no dial.
    fireEvent.click(screen.getByRole("button", { name: "Connect" }));
    expect(screen.getByRole("alert")).toHaveTextContent("Enter a valid IP address");
    expect(pairWithDevice).not.toHaveBeenCalled();
  });

  it("shows a loading skeleton before the first fetch completes (T-601)", () => {
    render(
      <HomePanel
        deviceName="Me"
        devices={[]}
        nearby={[]}
        loading
        onPairStarted={vi.fn()}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );
    expect(screen.getByTestId("home-devices-skeleton")).toBeInTheDocument();
    expect(screen.queryByText("No devices yet")).not.toBeInTheDocument();
  });

  it("shows a distinct error state when the initial fetch failed (T-601/T-602)", () => {
    render(
      <HomePanel
        deviceName="Me"
        devices={[]}
        nearby={[]}
        loading={false}
        loadError={{ code: "INTERNAL", message: "raw grpc text" }}
        onPairStarted={vi.fn()}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );
    const alert = screen.getByRole("alert");
    expect(alert).toHaveTextContent(
      "The daemon hit an internal error. Try again, and check the daemon logs if it persists.",
    );
    expect(alert).not.toHaveTextContent("raw grpc text");
    expect(screen.queryByText("No devices yet")).not.toBeInTheDocument();
    expect(screen.queryByTestId("home-devices-skeleton")).not.toBeInTheDocument();
  });

  it("opens device details when a paired device row is clicked", () => {
    render(
      <HomePanel
        deviceName="Me"
        devices={[pairedPhone]}
        nearby={[]}
        onPairStarted={vi.fn()}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );
    fireEvent.click(screen.getByText("Anil Phone"));
    expect(screen.getByText("Device details")).toBeInTheDocument();
    expect(screen.getByText("Connected and paired.")).toBeInTheDocument();
    expect(pairWithDevice).not.toHaveBeenCalled();
  });

  it("wires each Quick Action to real panel navigation instead of a no-op (T-101)", () => {
    const onNavigate = vi.fn();
    render(
      <HomePanel
        deviceName="Me"
        devices={[pairedPhone]}
        nearby={[]}
        onPairStarted={vi.fn()}
        onNavigate={onNavigate}
        onRefresh={vi.fn()}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: /Send file/ }));
    expect(onNavigate).toHaveBeenCalledWith("transfers");

    fireEvent.click(screen.getByRole("button", { name: /Settings/ }));
    expect(onNavigate).toHaveBeenCalledWith("settings");

    fireEvent.click(screen.getByRole("button", { name: /System Doctor/ }));
    expect(onNavigate).toHaveBeenCalledWith("doctor");
  });

  it("disables connection-dependent Quick Actions when no paired device is online, but not Clipboard/Settings (T-106)", () => {
    render(
      <HomePanel
        deviceName="Me"
        devices={[]}
        nearby={[]}
        onPairStarted={vi.fn()}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );
    expect(screen.getByRole("button", { name: /Send file/ })).toBeDisabled();
    expect(screen.getByRole("button", { name: /Remote input/ })).toBeDisabled();
    expect(screen.getByRole("button", { name: "History" })).toBeEnabled();
    expect(screen.getByRole("button", { name: /Settings/ })).toBeEnabled();
  });

  it("disconnects an online paired device from its info dialog and refreshes on success (T-102)", async () => {
    disconnectDevice.mockResolvedValue({ ok: true, value: true });
    const onRefresh = vi.fn();
    render(
      <HomePanel
        deviceName="Me"
        devices={[pairedPhone]}
        nearby={[]}
        onPairStarted={vi.fn()}
        onNavigate={vi.fn()}
        onRefresh={onRefresh}
      />,
    );

    fireEvent.click(screen.getByText("Anil Phone"));
    fireEvent.click(screen.getByRole("button", { name: "Disconnect" }));

    await waitFor(() => expect(disconnectDevice).toHaveBeenCalledWith("d1"));
    await waitFor(() => expect(onRefresh).toHaveBeenCalled());
  });

  it("surfaces a disconnect failure instead of silently clearing state, mapped from its ErrorCode (T-602)", async () => {
    disconnectDevice.mockResolvedValue({
      ok: false,
      error: { code: "DEVICE_NOT_FOUND", message: "daemon unreachable" },
    });
    render(
      <HomePanel
        deviceName="Me"
        devices={[pairedPhone]}
        nearby={[]}
        onPairStarted={vi.fn()}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );

    fireEvent.click(screen.getByText("Anil Phone"));
    fireEvent.click(screen.getByRole("button", { name: "Disconnect" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "That device is no longer available. Refresh the device list.",
    );
  });

  it("bounds the nearby list under many advertisers, collapsing the rest into a +X more count (T-E7)", () => {
    const many: NearbyDevice[] = Array.from({ length: 20 }, (_, i) => ({
      deviceId: `n${i}`,
      deviceName: `Nearby ${i}`,
      platform: "PLATFORM_LINUX_X11",
      addr: `192.168.1.${100 + i}`,
      port: 58231,
    }));
    render(
      <HomePanel
        deviceName="Me"
        devices={[]}
        nearby={many}
        onPairStarted={vi.fn()}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );

    // Only the cap (8) of the 20 advertisers are drawn as pairable stars.
    const stars = screen.getAllByRole("button", { name: /Nearby \d+ -/ });
    expect(stars).toHaveLength(8);

    // The other 12 are counted, not rendered.
    const more = screen.getByTestId("home-nearby-more");
    expect(more).toHaveTextContent("+12 more nearby");
  });

  it("forgets a paired device from its info dialog and refreshes on success (T-307)", async () => {
    forgetDevice.mockResolvedValue({ ok: true, value: true });
    const onRefresh = vi.fn();
    render(
      <HomePanel
        deviceName="Me"
        devices={[pairedPhone]}
        nearby={[]}
        onPairStarted={vi.fn()}
        onNavigate={vi.fn()}
        onRefresh={onRefresh}
      />,
    );

    fireEvent.click(screen.getByText("Anil Phone"));
    fireEvent.click(screen.getByRole("button", { name: "Forget device" }));

    await waitFor(() => expect(forgetDevice).toHaveBeenCalledWith("d1"));
    await waitFor(() => expect(onRefresh).toHaveBeenCalled());
  });

  it("does not forget a device from its info dialog when the confirmation is dismissed", () => {
    vi.spyOn(window, "confirm").mockReturnValue(false);
    render(
      <HomePanel
        deviceName="Me"
        devices={[pairedPhone]}
        nearby={[]}
        onPairStarted={vi.fn()}
        onNavigate={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );

    fireEvent.click(screen.getByText("Anil Phone"));
    fireEvent.click(screen.getByRole("button", { name: "Forget device" }));

    expect(forgetDevice).not.toHaveBeenCalled();
  });
});
