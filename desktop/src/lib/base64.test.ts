import { describe, expect, it } from "vitest";
import { base64ToBytes, base64ToText } from "./base64";

describe("base64ToBytes", () => {
  it("decodes to the exact byte sequence", () => {
    expect(Array.from(base64ToBytes("aGVsbG8="))).toEqual([104, 101, 108, 108, 111]);
  });
});

describe("base64ToText", () => {
  it("decodes ASCII text", () => {
    expect(base64ToText("aGVsbG8gd29ybGQ=")).toBe("hello world");
  });

  it("decodes multi-byte UTF-8 text correctly", () => {
    // "münih" UTF-8 encoded then base64'd -- exercises the TextDecoder
    // path rather than a naive charCode-per-byte join.
    expect(base64ToText(btoa(unescape(encodeURIComponent("münih"))))).toBe("münih");
  });
});
