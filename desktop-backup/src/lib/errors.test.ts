import { describe, expect, it } from "vitest";
import { errorCodeMessage, isErrorCode, type ErrorCode } from "./errors";
import { translator } from "../i18n";

// English is the locale these assertions pin to (translator() bypasses
// the I18nProvider/localStorage detection entirely, so this is
// hermetic regardless of the host's navigator.language).
const t = translator("en");

const ALL_CODES: ErrorCode[] = [
  "UNSPECIFIED",
  "UNAUTHENTICATED",
  "PAIRING_REJECTED",
  "PAIRING_TIMEOUT",
  "DEVICE_NOT_FOUND",
  "FILE_TRANSFER_FAILED",
  "CHECKSUM_MISMATCH",
  "UNSUPPORTED_PLATFORM",
  "INTERNAL",
  "PROTOCOL_VERSION_MISMATCH",
  "RATE_LIMITED",
];

describe("isErrorCode", () => {
  it("accepts every wire ErrorCode name", () => {
    for (const code of ALL_CODES) {
      expect(isErrorCode(code)).toBe(true);
    }
  });

  it("rejects unknown strings (e.g. a raw gRPC status word)", () => {
    expect(isErrorCode("NOT_FOUND")).toBe(false);
    expect(isErrorCode("")).toBe(false);
    // Guards against a bare `Object.prototype` method name being
    // mistaken for a mapped code via unguarded property lookup.
    expect(isErrorCode("toString")).toBe(false);
    expect(isErrorCode("hasOwnProperty")).toBe(false);
  });
});

describe("errorCodeMessage", () => {
  it("maps every ErrorCode to a non-empty, distinct, translated message", () => {
    const messages = ALL_CODES.map((code) => errorCodeMessage(code, t));
    for (const message of messages) {
      expect(message.length).toBeGreaterThan(0);
    }
    // Distinct per code -- a shared fallback string for two different
    // codes would defeat the point of threading the code through at
    // all (T-602's whole premise is one specific message per code).
    expect(new Set(messages).size).toBe(ALL_CODES.length);
  });

  it("never echoes raw transport text (e.g. a tonic::Status Display string)", () => {
    const message = errorCodeMessage("DEVICE_NOT_FOUND", t);
    expect(message).not.toMatch(/status:|tonic::|rpc failed/i);
    expect(message).toBe("That device is no longer available. Refresh the device list.");
  });

  it("gives UNSPECIFIED a generic but actionable fallback message", () => {
    expect(errorCodeMessage("UNSPECIFIED", t)).toBe(
      "Something went wrong. Try again, and check the daemon logs if it persists.",
    );
  });
});
