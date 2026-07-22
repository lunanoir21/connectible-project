import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { PairingQrDialog } from "./PairingQrDialog";

const localAddresses = vi.fn();
const preArmPairingCode = vi.fn();
vi.mock("../lib/ipc", () => ({
  ipc: {
    localAddresses: (...args: unknown[]) => localAddresses(...args),
    preArmPairingCode: (...args: unknown[]) => preArmPairingCode(...args),
  },
}));

// jsdom has no real <canvas> backend, so the real `qrcode` package would
// reject on every render (no 2D context); stub it the same way any other
// external side effect is mocked in this suite.
const toCanvas = vi.fn();
vi.mock("qrcode", () => ({
  default: { toCanvas: (...args: unknown[]) => toCanvas(...args) },
}));

describe("PairingQrDialog", () => {
  beforeEach(() => {
    localAddresses.mockReset();
    preArmPairingCode.mockReset();
    toCanvas.mockReset();
    toCanvas.mockResolvedValue(undefined);
  });

  it("renders the PIN once preArmPairingCode/localAddresses resolve", async () => {
    localAddresses.mockResolvedValue({ ok: true, value: { addresses: ["192.168.1.50"], port: 58231 } });
    preArmPairingCode.mockResolvedValue({ ok: true, value: { pinCode: "428170", pinExpiresAtMs: Date.now() + 30_000 } });

    render(<PairingQrDialog deviceId="d1" deviceName="Living Room PC" onClose={vi.fn()} consumed={false} />);

    expect(await screen.findByText("428170")).toBeInTheDocument();
    expect(toCanvas).toHaveBeenCalled();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("shows an error state when localAddresses returns no addresses", async () => {
    localAddresses.mockResolvedValue({ ok: true, value: { addresses: [], port: 58231 } });
    preArmPairingCode.mockResolvedValue({ ok: true, value: { pinCode: "428170", pinExpiresAtMs: Date.now() + 30_000 } });

    render(<PairingQrDialog deviceId="d1" deviceName="Living Room PC" onClose={vi.fn()} consumed={false} />);

    expect(await screen.findByText("No network address found. Connect this computer to a network and try again.")).toBeInTheDocument();
    expect(preArmPairingCode).not.toHaveBeenCalled();
  });

  it("shows an error state when preArmPairingCode fails", async () => {
    localAddresses.mockResolvedValue({ ok: true, value: { addresses: ["192.168.1.50"], port: 58231 } });
    preArmPairingCode.mockResolvedValue({
      ok: false,
      error: { code: "INTERNAL", message: "raw grpc status text" },
    });

    render(<PairingQrDialog deviceId="d1" deviceName="Living Room PC" onClose={vi.fn()} consumed={false} />);

    expect(
      await screen.findByText("The daemon hit an internal error. Try again, and check the daemon logs if it persists."),
    ).toBeInTheDocument();
  });

  it("shows an error state when the QR code itself fails to render", async () => {
    localAddresses.mockResolvedValue({ ok: true, value: { addresses: ["192.168.1.50"], port: 58231 } });
    preArmPairingCode.mockResolvedValue({ ok: true, value: { pinCode: "428170", pinExpiresAtMs: Date.now() + 30_000 } });
    toCanvas.mockRejectedValue(new Error("no 2d context"));

    render(<PairingQrDialog deviceId="d1" deviceName="Living Room PC" onClose={vi.fn()} consumed={false} />);

    expect(await screen.findByText("Couldn't render the code. Try again.")).toBeInTheDocument();
  });

  it("calls onClose when the close button is clicked", async () => {
    localAddresses.mockResolvedValue({ ok: true, value: { addresses: ["192.168.1.50"], port: 58231 } });
    preArmPairingCode.mockResolvedValue({ ok: true, value: { pinCode: "428170", pinExpiresAtMs: Date.now() + 30_000 } });
    const onClose = vi.fn();

    render(<PairingQrDialog deviceId="d1" deviceName="Living Room PC" onClose={onClose} consumed={false} />);
    await screen.findByText("428170");

    fireEvent.click(screen.getByRole("button", { name: "Close" }));
    expect(onClose).toHaveBeenCalled();
  });

  it("auto-closes when the consumed prop flips true", async () => {
    localAddresses.mockResolvedValue({ ok: true, value: { addresses: ["192.168.1.50"], port: 58231 } });
    preArmPairingCode.mockResolvedValue({ ok: true, value: { pinCode: "428170", pinExpiresAtMs: Date.now() + 30_000 } });
    const onClose = vi.fn();

    const { rerender } = render(
      <PairingQrDialog deviceId="d1" deviceName="Living Room PC" onClose={onClose} consumed={false} />,
    );
    await screen.findByText("428170");
    expect(onClose).not.toHaveBeenCalled();

    rerender(<PairingQrDialog deviceId="d1" deviceName="Living Room PC" onClose={onClose} consumed />);
    await waitFor(() => expect(onClose).toHaveBeenCalled());
  });

  it("closes on Escape", async () => {
    localAddresses.mockResolvedValue({ ok: true, value: { addresses: ["192.168.1.50"], port: 58231 } });
    preArmPairingCode.mockResolvedValue({ ok: true, value: { pinCode: "428170", pinExpiresAtMs: Date.now() + 30_000 } });
    const onClose = vi.fn();

    render(<PairingQrDialog deviceId="d1" deviceName="Living Room PC" onClose={onClose} consumed={false} />);
    await screen.findByText("428170");

    fireEvent.keyDown(window, { key: "Escape" });
    expect(onClose).toHaveBeenCalled();
  });
});
