// Base64 <-> bytes/text helpers for clipboard content (Phase L: the
// daemon DTO carries raw bytes as base64 since clipboard content can
// now be an image, not just UTF-8 text). Kept pure/standalone so they
// can be unit tested directly (see src/lib/base64.test.ts).

export function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

export function base64ToText(base64: string): string {
  return new TextDecoder().decode(base64ToBytes(base64));
}
