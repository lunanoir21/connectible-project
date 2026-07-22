// Shared payload format for the pairing QR code (scan-to-pair): a
// custom URI scheme both desktop (encode, here) and mobile (decode,
// mobile/lib/src/screens/pair_scan_screen.dart) agree on. Keep the two
// in sync if this ever changes.
export interface PairingCodePayload {
  host: string;
  port: number;
  pin: string;
  deviceId: string;
  deviceName: string;
}

const SCHEME = "connectible://pair";

export function encodePairingPayload(p: PairingCodePayload): string {
  const params = new URLSearchParams({
    host: p.host,
    port: String(p.port),
    pin: p.pin,
    id: p.deviceId,
    name: p.deviceName,
  });
  return `${SCHEME}?${params.toString()}`;
}
