import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { ClipboardPanel } from "./ClipboardPanel";
import type { ClipboardEntry } from "../lib/types";

vi.mock("@tauri-apps/plugin-clipboard-manager", () => ({ writeText: vi.fn(), writeImage: vi.fn() }));

// Base64 of "hello world" -- entries carry raw bytes as base64 since
// Phase L (content can be an image, not just text).
const entries: ClipboardEntry[] = [
  {
    content: "aGVsbG8gd29ybGQ=",
    mimeType: "text/plain",
    capturedAtMs: Date.now(),
    source: "local",
    oversized: false,
    byteSize: 11,
  },
];

describe("ClipboardPanel", () => {
  it("shows an empty state with no history and no loading/error state active", () => {
    render(<ClipboardPanel entries={[]} />);
    expect(screen.getByText("Nothing copied yet")).toBeInTheDocument();
    expect(screen.queryByTestId("clipboard-list-skeleton")).not.toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("shows a loading skeleton before the first snapshot loads, distinct from the empty state (T-601)", () => {
    render(<ClipboardPanel entries={[]} loading />);
    expect(screen.getByTestId("clipboard-list-skeleton")).toBeInTheDocument();
    expect(screen.queryByText("Nothing copied yet")).not.toBeInTheDocument();
  });

  it("shows a distinct error state when the initial fetch failed, not the empty state (T-601/T-602)", () => {
    const onRefresh = vi.fn();
    render(
      <ClipboardPanel
        entries={[]}
        loading={false}
        loadError={{ code: "UNSPECIFIED", message: "raw grpc text" }}
        onRefresh={onRefresh}
      />,
    );
    const alert = screen.getByRole("alert");
    expect(alert).toHaveTextContent(
      "Something went wrong. Try again, and check the daemon logs if it persists.",
    );
    expect(alert).not.toHaveTextContent("raw grpc text");
    expect(screen.queryByText("Nothing copied yet")).not.toBeInTheDocument();
    expect(screen.queryByTestId("clipboard-list-skeleton")).not.toBeInTheDocument();
  });

  it("renders real clipboard entries when loaded", () => {
    render(<ClipboardPanel entries={entries} />);
    expect(screen.getByText("hello world")).toBeInTheDocument();
    expect(screen.queryByTestId("clipboard-list-skeleton")).not.toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("shows a size message instead of a preview/copy button for an oversized entry (T-L8)", () => {
    const oversized: ClipboardEntry[] = [
      {
        content: "",
        mimeType: "text/plain",
        capturedAtMs: Date.now(),
        source: "local",
        oversized: true,
        byteSize: 12 * 1024 * 1024,
      },
    ];
    render(<ClipboardPanel entries={oversized} />);
    expect(screen.getByText("Too large to sync (12.0 MB)")).toBeInTheDocument();
    expect(screen.queryByText("Copy")).not.toBeInTheDocument();
  });

  it("renders an image entry as a thumbnail, not a text preview (Phase L)", () => {
    // 1x1 transparent PNG.
    const png =
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
    const imageEntries: ClipboardEntry[] = [
      {
        content: png,
        mimeType: "image/png",
        capturedAtMs: Date.now(),
        source: "local",
        oversized: false,
        byteSize: 68,
      },
    ];
    render(<ClipboardPanel entries={imageEntries} />);
    const img = screen.getByAltText("Image") as HTMLImageElement;
    expect(img.src).toBe(`data:image/png;base64,${png}`);
  });
});
