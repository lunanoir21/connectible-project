import { describe, expect, it } from "vitest";
import { formatBytes, formatRelativeTime, secondsUntil, transferPercent, truncate } from "./format";

describe("formatBytes", () => {
  it("formats sub-KB as bytes", () => {
    expect(formatBytes(512)).toBe("512 B");
  });

  it("scales into KB/MB/GB", () => {
    expect(formatBytes(1536)).toBe("1.5 KB");
    expect(formatBytes(5 * 1024 * 1024)).toBe("5.0 MB");
    expect(formatBytes(3 * 1024 * 1024 * 1024)).toBe("3.0 GB");
  });
});

describe("transferPercent", () => {
  it("returns 0 for a zero or unknown total", () => {
    expect(transferPercent(10, 0)).toBe(0);
  });

  it("computes and clamps the percentage", () => {
    expect(transferPercent(50, 200)).toBe(25);
    expect(transferPercent(300, 200)).toBe(100);
    expect(transferPercent(-5, 200)).toBe(0);
  });
});

describe("secondsUntil", () => {
  it("counts down and never goes negative", () => {
    const now = 1_000_000;
    expect(secondsUntil(now + 30_000, now)).toBe(30);
    expect(secondsUntil(now - 5_000, now)).toBe(0);
  });
});

describe("formatRelativeTime", () => {
  it("bucket-formats deltas", () => {
    const now = 1_000_000_000_000;
    expect(formatRelativeTime(now, now)).toBe("just now");
    expect(formatRelativeTime(now - 30_000, now)).toBe("30s ago");
    expect(formatRelativeTime(now - 5 * 60_000, now)).toBe("5m ago");
    expect(formatRelativeTime(now - 3 * 3_600_000, now)).toBe("3h ago");
    expect(formatRelativeTime(now - 2 * 86_400_000, now)).toBe("2d ago");
  });
});

describe("truncate", () => {
  it("leaves short strings untouched", () => {
    expect(truncate("hello", 10)).toBe("hello");
  });

  it("adds an ellipsis when over the limit", () => {
    expect(truncate("abcdefghij", 5)).toBe("abcd...");
  });
});
