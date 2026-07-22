import { describe, expect, it } from "vitest";
import { encodePairingPayload } from "./pairingCode";

// This is a cross-platform wire contract with mobile's own parser
// (mobile/lib/src/screens/pair_scan_screen.dart) -- both sides agree on
// the exact scheme, query param names, and value formatting. Pin those
// down explicitly so a refactor here can't silently drift out of sync
// with what mobile expects to parse.
describe("encodePairingPayload", () => {
  it("encodes the exact connectible://pair URI shape mobile expects", () => {
    const payload = encodePairingPayload({
      host: "192.168.1.50",
      port: 58231,
      pin: "428170",
      deviceId: "d1",
      deviceName: "Living Room PC",
    });

    expect(payload).toBe(
      "connectible://pair?host=192.168.1.50&port=58231&pin=428170&id=d1&name=Living+Room+PC",
    );
  });

  it("round-trips every field back out via URLSearchParams", () => {
    const payload = encodePairingPayload({
      host: "10.0.0.7",
      port: 12345,
      pin: "000001",
      deviceId: "abc-123",
      deviceName: "Anıl's Phone",
    });

    expect(payload.startsWith("connectible://pair?")).toBe(true);
    const query = payload.slice("connectible://pair?".length);
    const params = new URLSearchParams(query);
    expect(params.get("host")).toBe("10.0.0.7");
    expect(params.get("port")).toBe("12345");
    expect(params.get("pin")).toBe("000001");
    expect(params.get("id")).toBe("abc-123");
    expect(params.get("name")).toBe("Anıl's Phone");
  });

  it("URL-encodes special characters in the device name", () => {
    const payload = encodePairingPayload({
      host: "192.168.1.1",
      port: 58231,
      pin: "111111",
      deviceId: "d2",
      deviceName: "Test & Debug Box",
    });

    expect(payload).toContain("name=Test+%26+Debug+Box");
  });
});
