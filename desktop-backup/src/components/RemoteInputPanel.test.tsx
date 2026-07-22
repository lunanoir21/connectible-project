import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { RemoteInputPanel } from "./RemoteInputPanel";

const setRemoteInputEnabled = vi.fn();
vi.mock("../lib/ipc", () => ({
  ipc: {
    setRemoteInputEnabled: (...args: unknown[]) => setRemoteInputEnabled(...args),
  },
}));

describe("RemoteInputPanel", () => {
  beforeEach(() => {
    setRemoteInputEnabled.mockReset();
  });

  it("shows unavailable and hides the toggle when no input backend capability is present", () => {
    render(<RemoteInputPanel capabilities={[]} enabled={false} onRefresh={vi.fn()} />);
    expect(screen.getByText("Unavailable")).toBeInTheDocument();
    expect(screen.queryByRole("switch")).not.toBeInTheDocument();
  });

  it("shows a loading skeleton instead of a premature Unavailable while capabilities haven't loaded yet (T-601)", () => {
    render(<RemoteInputPanel capabilities={[]} enabled={false} onRefresh={vi.fn()} loading />);
    expect(screen.getByTestId("remote-input-status-skeleton")).toBeInTheDocument();
    expect(screen.queryByText("Unavailable")).not.toBeInTheDocument();
  });

  it("renders the toggle as on when remote input is enabled and available", () => {
    render(<RemoteInputPanel capabilities={["remote_input"]} enabled onRefresh={vi.fn()} />);
    expect(screen.getByText("Ready")).toBeInTheDocument();
    expect(screen.getByRole("switch")).toHaveAttribute("aria-checked", "true");
  });

  it("renders the toggle as off when remote input is disabled", () => {
    render(<RemoteInputPanel capabilities={["remote_input"]} enabled={false} onRefresh={vi.fn()} />);
    expect(screen.getByRole("switch")).toHaveAttribute("aria-checked", "false");
  });

  it("calls setRemoteInputEnabled and refreshes on toggle (T-309)", async () => {
    setRemoteInputEnabled.mockResolvedValue({ ok: true, value: false });
    const onRefresh = vi.fn();
    render(<RemoteInputPanel capabilities={["remote_input"]} enabled onRefresh={onRefresh} />);

    fireEvent.click(screen.getByRole("switch"));

    await waitFor(() => expect(onRefresh).toHaveBeenCalled());
    expect(setRemoteInputEnabled).toHaveBeenCalledWith(false);
  });

  it("surfaces a toggle error instead of throwing, mapped from its ErrorCode (T-602)", async () => {
    setRemoteInputEnabled.mockResolvedValue({
      ok: false,
      error: { code: "UNSPECIFIED", message: "daemon not connected yet" },
    });
    render(<RemoteInputPanel capabilities={["remote_input"]} enabled onRefresh={vi.fn()} />);

    fireEvent.click(screen.getByRole("switch"));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Something went wrong. Try again, and check the daemon logs if it persists.",
    );
  });
});
