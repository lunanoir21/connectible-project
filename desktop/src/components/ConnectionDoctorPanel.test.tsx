import { describe, expect, it, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { ConnectionDoctorPanel } from "./ConnectionDoctorPanel";
import { I18nProvider } from "../i18n";
import type { DiagnosticsReport } from "../lib/types";

// The panel is a thin renderer over the daemon's diagnostics engine
// (RunDiagnostics RPC), so the only ipc call it makes is runDiagnostics.
const runDiagnostics = vi.fn();
vi.mock("../lib/ipc", () => ({
  ipc: { runDiagnostics: (...args: unknown[]) => runDiagnostics(...args) },
}));
vi.mock("@tauri-apps/plugin-opener", () => ({ openUrl: vi.fn() }));

function ok<T>(value: T) {
  return { ok: true as const, value };
}

const report: DiagnosticsReport = {
  worst: "error",
  checks: [
    {
      id: "data-dir-writable",
      title: "Data directory writable",
      category: "environment",
      status: "ok",
      summary: "Directory exists and is writable",
      detail: "",
      remediation: "",
      data: {},
    },
    {
      id: "daemon-port",
      title: "Daemon port",
      category: "network",
      status: "error",
      summary: "Nothing is listening on port 58231",
      detail: "",
      remediation: "Start the daemon.",
      data: {},
    },
    {
      id: "paired-store",
      title: "Paired devices",
      category: "pairing",
      status: "warn",
      summary: "1 device not yet cert-pinned",
      detail: "",
      remediation: "They pin automatically on the next connect.",
      data: {},
    },
  ],
};

describe("ConnectionDoctorPanel", () => {
  beforeEach(() => {
    runDiagnostics.mockReset();
  });

  it("runs on mount and renders every check grouped, with badges + remediation", async () => {
    runDiagnostics.mockResolvedValue(ok(report));
    render(<ConnectionDoctorPanel />);

    await waitFor(() =>
      expect(screen.getByText("Daemon port")).toBeInTheDocument(),
    );
    // Ran all checks on mount (no check id argument).
    expect(runDiagnostics).toHaveBeenCalledWith();

    expect(screen.getByText("Data directory writable")).toBeInTheDocument();
    expect(screen.getByText("Paired devices")).toBeInTheDocument();
    // Remediation is shown for the failing/ warning checks.
    expect(screen.getByText(/Start the daemon\./)).toBeInTheDocument();
    // Monochrome status badges are text, not color, and now from i18n
    // (T-X13): the default (no-provider) context is English, so the
    // error roll-up + failing check read "Error" and the warning "Warning".
    expect(screen.getAllByText("Error").length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText("Warning")).toBeInTheDocument();
  });

  it("renders localized check titles + badges under a Turkish locale, falling back for an unknown check id (T-X13)", async () => {
    const withUnknown: DiagnosticsReport = {
      worst: "warn",
      checks: [
        ...report.checks,
        {
          id: "some-future-check",
          title: "Some future check",
          category: "features",
          status: "ok",
          summary: "n/a",
          detail: "",
          remediation: "",
          data: {},
        },
      ],
    };
    runDiagnostics.mockResolvedValue(ok(withUnknown));
    // Force the locale via navigator.language: jsdom here exposes no
    // localStorage global, so I18nProvider's detectInitialLocale falls
    // through to navigator.language, which "tr-TR" resolves to "tr".
    const originalLanguage = Object.getOwnPropertyDescriptor(navigator, "language");
    Object.defineProperty(navigator, "language", { value: "tr-TR", configurable: true });
    try {
      render(
        <I18nProvider>
          <ConnectionDoctorPanel />
        </I18nProvider>,
      );
      // Known ids render their Turkish titles...
      await waitFor(() =>
        expect(screen.getByText("Eşleşmiş cihazlar")).toBeInTheDocument(),
      );
      expect(screen.getByText("Arka plan servisi portu")).toBeInTheDocument();
      // ...an unknown id falls back to the daemon-provided English title...
      expect(screen.getByText("Some future check")).toBeInTheDocument();
      // ...and badges are localized ("Hata"/"Uyarı"), not hardcoded.
      expect(screen.getAllByText("Hata").length).toBeGreaterThanOrEqual(1);
      expect(screen.getAllByText("Uyarı").length).toBeGreaterThanOrEqual(1);
    } finally {
      if (originalLanguage) {
        Object.defineProperty(navigator, "language", originalLanguage);
      }
    }
  });

  it("re-runs a single check via its Re-run button", async () => {
    runDiagnostics.mockResolvedValue(ok(report));
    render(<ConnectionDoctorPanel />);
    await waitFor(() =>
      expect(screen.getByText("Data directory writable")).toBeInTheDocument(),
    );

    runDiagnostics.mockClear();
    runDiagnostics.mockResolvedValue(
      ok({ worst: "ok", checks: [report.checks[0]] } as DiagnosticsReport),
    );
    // The first check (environment category) is rendered first.
    fireEvent.click(screen.getAllByText("Re-run")[0]);

    await waitFor(() =>
      expect(runDiagnostics).toHaveBeenCalledWith("data-dir-writable"),
    );
  });

  it("surfaces a handled error (no checks) when the daemon is not connected", async () => {
    runDiagnostics.mockResolvedValue({
      ok: false as const,
      error: { code: "UNSPECIFIED", message: "daemon not connected yet" },
    });
    render(<ConnectionDoctorPanel />);

    await waitFor(() => expect(runDiagnostics).toHaveBeenCalled());
    // No check rows render on an error result.
    expect(screen.queryByText("Daemon port")).not.toBeInTheDocument();
  });
});
