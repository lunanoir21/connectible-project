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

describe("formatRelativeTime (T-X15)", () => {
  const now = 1_000_000_000_000;
  // Expected strings are computed from Intl directly rather than
  // hardcoded, so the test is independent of the runtime's exact ICU
  // wording ("30 sec. ago" vs "30 sec ago" etc.) -- it verifies the
  // right unit/sign/locale is chosen, which is what the code decides.
  const rtf = (locale: string) =>
    new Intl.RelativeTimeFormat(locale, { numeric: "auto", style: "short" });

  it("buckets deltas into the right unit (en)", () => {
    expect(formatRelativeTime(now, "en", now)).toBe(rtf("en").format(0, "second"));
    expect(formatRelativeTime(now - 30_000, "en", now)).toBe(rtf("en").format(-30, "second"));
    expect(formatRelativeTime(now - 5 * 60_000, "en", now)).toBe(rtf("en").format(-5, "minute"));
    expect(formatRelativeTime(now - 3 * 3_600_000, "en", now)).toBe(rtf("en").format(-3, "hour"));
    expect(formatRelativeTime(now - 2 * 86_400_000, "en", now)).toBe(rtf("en").format(-2, "day"));
  });

  it("renders in the active locale (tr differs from en)", () => {
    expect(formatRelativeTime(now - 30_000, "tr", now)).toBe(rtf("tr").format(-30, "second"));
    // Turkish "30 sn. önce" must not equal the English rendering, i.e.
    // the locale is actually threaded through, not ignored.
    expect(formatRelativeTime(now - 30_000, "tr", now)).not.toBe(
      formatRelativeTime(now - 30_000, "en", now),
    );
  });

  it("renders the sub-5s case as the locale's 'now' wording", () => {
    expect(formatRelativeTime(now - 1_000, "en", now)).toBe(rtf("en").format(0, "second"));
    expect(formatRelativeTime(now - 1_000, "tr", now)).toBe(rtf("tr").format(0, "second"));
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
