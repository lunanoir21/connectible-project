import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { DeviceListPanel } from "./DeviceListPanel";
import type { Device, NearbyDevice } from "../lib/types";

// The IPC layer is the single seam to the Rust backend; mocking it
// keeps these component tests hermetic (no Tauri runtime needed).
const pairWithDevice = vi.fn();
const forgetDevice = vi.fn();
vi.mock("../lib/ipc", () => ({
  ipc: {
    pairWithDevice: (...args: unknown[]) => pairWithDevice(...args),
    forgetDevice: (...args: unknown[]) => forgetDevice(...args),
  },
}));

const paired: Device[] = [
  { deviceId: "d1", deviceName: "Living Room PC", platform: "PLATFORM_LINUX_X11", online: true, pairedAtMs: 1, lastSeenMs: Date.now() },
];
// A phone: mobile now runs its own gRPC/TLS server too (bidirectional
// pairing), so this desktop can dial it exactly like another desktop --
// same click-to-pair affordance, no special-cased hint (T-105).
const nearby: NearbyDevice[] = [
  { deviceId: "d2", deviceName: "Anil's Phone", platform: "PLATFORM_ANDROID", addr: "192.168.1.20", port: 58231 },
];
// A reachable peer (another computer running the daemon): this one the
// desktop CAN dial, so it gets a Pair button.
const nearbyReachable: NearbyDevice[] = [
  { deviceId: "d3", deviceName: "Work Laptop", platform: "PLATFORM_LINUX_X11", addr: "192.168.1.30", port: 58231 },
];

describe("DeviceListPanel", () => {
  beforeEach(() => {
    pairWithDevice.mockReset();
    forgetDevice.mockReset();
  });

  it("shows a distinct empty state when there are no devices and loading has finished", () => {
    render(
      <DeviceListPanel devices={[]} nearby={[]} loading={false} onPairStarted={vi.fn()} onRefresh={vi.fn()} />,
    );
    expect(screen.getByText("No devices yet")).toBeInTheDocument();
    expect(screen.queryByTestId("device-list-skeleton")).not.toBeInTheDocument();
  });

  it("shows a loading skeleton before the first fetch completes, distinct from the empty state", () => {
    render(
      <DeviceListPanel devices={[]} nearby={[]} loading onPairStarted={vi.fn()} onRefresh={vi.fn()} />,
    );
    expect(screen.getByTestId("device-list-skeleton")).toBeInTheDocument();
    expect(screen.queryByText("No devices yet")).not.toBeInTheDocument();
  });

  it("renders paired and nearby sections with real data", () => {
    render(
      <DeviceListPanel devices={paired} nearby={nearby} loading={false} onPairStarted={vi.fn()} onRefresh={vi.fn()} />,
    );
    expect(screen.getByText("Living Room PC")).toBeInTheDocument();
    expect(screen.getByText("Online")).toBeInTheDocument();
    expect(screen.getByText("Anil's Phone")).toBeInTheDocument();
  });

  it("shows a click-to-pair Pair button for a nearby phone (phones run a server too)", async () => {
    pairWithDevice.mockResolvedValue({ ok: true, value: { accepted: true, pinExpiresAtMs: 42 } });
    const onPairStarted = vi.fn();
    render(
      <DeviceListPanel devices={[]} nearby={nearby} loading={false} onPairStarted={onPairStarted} onRefresh={vi.fn()} />,
    );

    fireEvent.click(screen.getByRole("button", { name: "Pair" }));

    await waitFor(() => expect(onPairStarted).toHaveBeenCalledWith(nearby[0], 42));
    expect(pairWithDevice).toHaveBeenCalledWith("192.168.1.20", 58231);
  });

  it("invokes pairing and reports the PIN expiry to the parent on success", async () => {
    pairWithDevice.mockResolvedValue({ ok: true, value: { accepted: true, pinExpiresAtMs: 42 } });
    const onPairStarted = vi.fn();
    render(
      <DeviceListPanel
        devices={[]}
        nearby={nearbyReachable}
        loading={false}
        onPairStarted={onPairStarted}
        onRefresh={vi.fn()}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "Pair" }));

    await waitFor(() => expect(onPairStarted).toHaveBeenCalledWith(nearbyReachable[0], 42));
    expect(pairWithDevice).toHaveBeenCalledWith("192.168.1.30", 58231);
  });

  it("surfaces a pairing error instead of throwing, mapped from its ErrorCode (T-602)", async () => {
    pairWithDevice.mockResolvedValue({
      ok: false,
      error: { code: "DEVICE_NOT_FOUND", message: "raw grpc status text should never reach the UI" },
    });
    render(
      <DeviceListPanel devices={[]} nearby={nearbyReachable} loading={false} onPairStarted={vi.fn()} onRefresh={vi.fn()} />,
    );

    fireEvent.click(screen.getByRole("button", { name: "Pair" }));

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("That device is no longer available. Refresh the device list.");
    expect(alert).not.toHaveTextContent("raw grpc status text");
  });

  it("forgets a paired device and refreshes the list (T-307)", async () => {
    forgetDevice.mockResolvedValue({ ok: true, value: true });
    const onRefresh = vi.fn();
    render(
      <DeviceListPanel devices={paired} nearby={[]} loading={false} onPairStarted={vi.fn()} onRefresh={onRefresh} />,
    );

    fireEvent.click(screen.getByRole("button", { name: "Forget device" }));

    await waitFor(() => expect(onRefresh).toHaveBeenCalled());
    expect(forgetDevice).toHaveBeenCalledWith("d1");
  });

  it("surfaces a forget error instead of throwing, mapped from its ErrorCode (T-602)", async () => {
    forgetDevice.mockResolvedValue({
      ok: false,
      error: { code: "UNSPECIFIED", message: "daemon not connected yet" },
    });
    render(
      <DeviceListPanel devices={paired} nearby={[]} loading={false} onPairStarted={vi.fn()} onRefresh={vi.fn()} />,
    );

    fireEvent.click(screen.getByRole("button", { name: "Forget device" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Something went wrong. Try again, and check the daemon logs if it persists.",
    );
  });

  it("shows a distinct error state when the initial device fetch itself failed (T-601)", () => {
    render(
      <DeviceListPanel
        devices={[]}
        nearby={[]}
        loading={false}
        loadError={{ code: "INTERNAL", message: "boom" }}
        onPairStarted={vi.fn()}
        onRefresh={vi.fn()}
      />,
    );
    expect(screen.getByRole("alert")).toHaveTextContent(
      "The daemon hit an internal error. Try again, and check the daemon logs if it persists.",
    );
    expect(screen.queryByText("No devices yet")).not.toBeInTheDocument();
    expect(screen.queryByTestId("device-list-skeleton")).not.toBeInTheDocument();
  });
});
