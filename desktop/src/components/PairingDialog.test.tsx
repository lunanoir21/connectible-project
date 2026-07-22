import { describe, expect, it, vi, beforeEach } from "vitest";
import { act, render, screen, fireEvent, waitFor } from "@testing-library/react";
import { PairingDialog } from "./PairingDialog";
import type { NearbyDevice, PairingPrompt } from "../lib/types";

const confirmPin = vi.fn();
vi.mock("../lib/ipc", () => ({
  ipc: {
    confirmPin: (...args: unknown[]) => confirmPin(...args),
  },
}));

const device: NearbyDevice = {
  deviceId: "d2",
  deviceName: "Anil's Phone",
  platform: "PLATFORM_ANDROID",
  addr: "192.168.1.20",
  port: 58231,
};

describe("PairingDialog", () => {
  beforeEach(() => {
    confirmPin.mockReset();
  });

  it("responder shows the PIN and a live countdown", () => {
    const prompt: PairingPrompt = {
      requesterDeviceId: "d2",
      requesterDeviceName: "Anil's Phone",
      pinCode: "428170",
      pinExpiresAtMs: Date.now() + 30_000,
    };
    render(
      <PairingDialog mode={{ role: "responder", prompt }} onClose={vi.fn()} onPaired={vi.fn()} />,
    );
    expect(screen.getByLabelText("Pairing PIN")).toHaveTextContent("428170");
    expect(screen.getByText(/Expires in/)).toBeInTheDocument();
  });

  // Fake timers are scoped to this single test (the countdown interval),
  // because mixing them with the async `waitFor` used in the requester
  // tests deadlocks the fake clock.
  it("responder shows a distinct timed-out state after expiry", () => {
    vi.useFakeTimers();
    try {
      const prompt: PairingPrompt = {
        requesterDeviceId: "d2",
        requesterDeviceName: "Anil's Phone",
        pinCode: "428170",
        pinExpiresAtMs: Date.now() + 1_000,
      };
      render(
        <PairingDialog mode={{ role: "responder", prompt }} onClose={vi.fn()} onPaired={vi.fn()} />,
      );
      // The interval callback calls setState, so the clock advance must
      // be wrapped in act() for React to flush the re-render.
      act(() => {
        vi.advanceTimersByTime(1_500);
      });
      expect(screen.getByRole("alert")).toHaveTextContent("Pairing timed out");
    } finally {
      vi.useRealTimers();
    }
  });

  // Same fake-timer scoping rationale as the timed-out test above: the
  // countdown interval needs a fake clock, and mixing that with the
  // async `waitFor` in the requester tests deadlocks it.
  it("countdown shifts to the danger state once under 10s remain", () => {
    vi.useFakeTimers();
    try {
      const prompt: PairingPrompt = {
        requesterDeviceId: "d2",
        requesterDeviceName: "Anil's Phone",
        pinCode: "428170",
        pinExpiresAtMs: Date.now() + 30_000,
      };
      render(
        <PairingDialog mode={{ role: "responder", prompt }} onClose={vi.fn()} onPaired={vi.fn()} />,
      );

      // At 30s remaining the countdown is still in its normal (non-urgent) state.
      expect(screen.getByTestId("pin-countdown-remaining")).not.toHaveClass("text-danger");
      expect(screen.getByTestId("pin-countdown-bar")).not.toHaveClass("bg-danger");

      // Advance to 9s remaining -- under the 10s urgency threshold.
      act(() => {
        vi.advanceTimersByTime(21_000);
      });

      expect(screen.getByTestId("pin-countdown-remaining")).toHaveClass("text-danger");
      expect(screen.getByTestId("pin-countdown-bar")).toHaveClass("bg-danger");
      // The fill stays transform-driven (no `width` inline style), so the
      // urgency color shift never triggers layout reflow.
      const barStyle = screen.getByTestId("pin-countdown-bar").getAttribute("style") ?? "";
      expect(barStyle).not.toContain("width");
      expect(barStyle).toContain("transform");
    } finally {
      vi.useRealTimers();
    }
  });

  it("responder shows a success beat and closes once justCompleted flips true", async () => {
    const prompt: PairingPrompt = {
      requesterDeviceId: "d2",
      requesterDeviceName: "Anil's Phone",
      pinCode: "428170",
      pinExpiresAtMs: Date.now() + 30_000,
    };
    const onPaired = vi.fn();
    const { rerender } = render(
      <PairingDialog
        mode={{ role: "responder", prompt }}
        onClose={vi.fn()}
        onPaired={onPaired}
        justCompleted={false}
      />,
    );
    expect(screen.getByLabelText("Pairing PIN")).toBeInTheDocument();

    rerender(
      <PairingDialog
        mode={{ role: "responder", prompt }}
        onClose={vi.fn()}
        onPaired={onPaired}
        justCompleted
      />,
    );

    expect(screen.getByText("Paired")).toBeInTheDocument();
    expect(screen.queryByLabelText("Pairing PIN")).not.toBeInTheDocument();
    await waitFor(() => expect(onPaired).toHaveBeenCalled());
  });

  it("requester submits the typed PIN and calls onPaired when verified", async () => {
    confirmPin.mockResolvedValue({ ok: true, value: true });
    const onPaired = vi.fn();
    render(
      <PairingDialog
        mode={{ role: "requester", device, pinExpiresAtMs: Date.now() + 30_000 }}
        onClose={vi.fn()}
        onPaired={onPaired}
      />,
    );

    fireEvent.change(screen.getByLabelText("Pairing PIN"), { target: { value: "428170" } });
    fireEvent.click(screen.getByRole("button", { name: "Pair" }));

    await waitFor(() => expect(onPaired).toHaveBeenCalled());
    // The PIN is keyed daemon-side by the local requester id; the target's
    // device_id is now passed too so the daemon pins its cert at pairing
    // (TOFU, T-C2).
    expect(confirmPin).toHaveBeenCalledWith(
      "192.168.1.20",
      58231,
      "428170",
      "d2",
    );
  });

  it("requester shows an error and does not pair on a wrong PIN", async () => {
    confirmPin.mockResolvedValue({ ok: true, value: false });
    const onPaired = vi.fn();
    render(
      <PairingDialog
        mode={{ role: "requester", device, pinExpiresAtMs: Date.now() + 30_000 }}
        onClose={vi.fn()}
        onPaired={onPaired}
      />,
    );

    fireEvent.change(screen.getByLabelText("Pairing PIN"), { target: { value: "000000" } });
    fireEvent.click(screen.getByRole("button", { name: "Pair" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Incorrect PIN");
    expect(onPaired).not.toHaveBeenCalled();
  });
});
