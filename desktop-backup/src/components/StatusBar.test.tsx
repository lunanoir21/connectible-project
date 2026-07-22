import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { StatusBar } from "./StatusBar";
import type { Battery, DaemonStatusDto } from "../lib/types";

const battery: Battery = {
  percentage: 72,
  isCharging: true,
  minutesRemaining: 120,
  reportedAtMs: Date.now(),
};

const runningReachable: DaemonStatusDto = {
  running: true,
  reachable: true,
  rttMs: 12,
  errorCode: null,
};

const runningUnreachable: DaemonStatusDto = {
  running: true,
  reachable: false,
  rttMs: null,
  errorCode: null,
};

const stopped: DaemonStatusDto = {
  running: false,
  reachable: false,
  rttMs: null,
  errorCode: null,
};

describe("StatusBar", () => {
  it("renders the panel title and device name with real data", () => {
    render(<StatusBar connected deviceName="Living Room PC" battery={null} title="Devices" />);
    expect(screen.getByText("Devices")).toBeInTheDocument();
    expect(screen.getByText("Living Room PC")).toBeInTheDocument();
  });

  it("omits the device name entirely when there is none yet, rather than rendering an empty label", () => {
    render(<StatusBar connected={false} deviceName="" battery={null} title="Home" />);
    expect(screen.queryByText("this device")).not.toBeInTheDocument();
  });

  it("shows a connected pill and hides the daemon-status pill when running and reachable", () => {
    render(
      <StatusBar connected deviceName="Me" battery={null} title="Home" daemonStatus={runningReachable} />,
    );
    expect(screen.getByText("Connected")).toBeInTheDocument();
    expect(screen.queryByText("Daemon stopped")).not.toBeInTheDocument();
    expect(screen.queryByText("Daemon unreachable")).not.toBeInTheDocument();
  });

  it("shows a distinct connecting state when not connected", () => {
    render(<StatusBar connected={false} deviceName="Me" battery={null} title="Home" />);
    expect(screen.getByText("Connecting...")).toBeInTheDocument();
  });

  it("shows a daemon-unreachable pill distinct from stopped when running but unreachable", () => {
    render(
      <StatusBar connected={false} deviceName="Me" battery={null} title="Home" daemonStatus={runningUnreachable} />,
    );
    expect(screen.getByText("Daemon unreachable")).toBeInTheDocument();
    expect(screen.queryByText("Daemon stopped")).not.toBeInTheDocument();
  });

  it("shows a daemon-stopped pill distinct from unreachable when the daemon isn't running", () => {
    render(<StatusBar connected={false} deviceName="Me" battery={null} title="Home" daemonStatus={stopped} />);
    expect(screen.getByText("Daemon stopped")).toBeInTheDocument();
    expect(screen.queryByText("Daemon unreachable")).not.toBeInTheDocument();
  });

  it("renders the paired device's battery percentage when present, and omits it when absent", () => {
    const { rerender } = render(<StatusBar connected deviceName="Me" battery={battery} title="Home" />);
    expect(screen.getByText("72%")).toBeInTheDocument();

    rerender(<StatusBar connected deviceName="Me" battery={null} title="Home" />);
    expect(screen.queryByText("72%")).not.toBeInTheDocument();
  });
});
