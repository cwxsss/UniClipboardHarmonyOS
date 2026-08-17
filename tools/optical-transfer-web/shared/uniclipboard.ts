import { packFrame, parseFrame, type FrameHeader } from "./protocol";

export const FRAME_PREFIX = "UCO1:";
export const FRAME_BLOCK_BYTES = 288;
export const MAX_PAYLOAD_BYTES = 4 * 1024 * 1024;

const ENVELOPE_MAGIC = new Uint8Array([0x55, 0x43, 0x4f, 0x31]);

export interface UniClipboardEnvelope {
  kind: "Text" | "Image" | "File";
  name: string;
  data: Uint8Array;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let index = 0; index < bytes.length; index++) {
    binary += String.fromCharCode(bytes[index]!);
  }
  return btoa(binary);
}

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

export function packEnvelope(envelope: UniClipboardEnvelope): Uint8Array {
  const nameBytes = new TextEncoder().encode(envelope.name);
  if (nameBytes.length > 0xffff) throw new Error("file name is too long");
  const kind = envelope.kind === "Image" ? 2 : envelope.kind === "File" ? 3 : 1;
  const output = new Uint8Array(7 + nameBytes.length + envelope.data.length);
  output.set(ENVELOPE_MAGIC, 0);
  output[4] = kind;
  output[5] = nameBytes.length & 0xff;
  output[6] = (nameBytes.length >>> 8) & 0xff;
  output.set(nameBytes, 7);
  output.set(envelope.data, 7 + nameBytes.length);
  return output;
}

export function unpackEnvelope(bytes: Uint8Array): UniClipboardEnvelope | null {
  if (
    bytes.length < 7 ||
    bytes[0] !== ENVELOPE_MAGIC[0] ||
    bytes[1] !== ENVELOPE_MAGIC[1] ||
    bytes[2] !== ENVELOPE_MAGIC[2] ||
    bytes[3] !== ENVELOPE_MAGIC[3]
  ) return null;
  const kindCode = bytes[4]!;
  if (kindCode < 1 || kindCode > 3) return null;
  const nameLength = bytes[5]! | (bytes[6]! << 8);
  if (7 + nameLength > bytes.length) return null;
  const kind = kindCode === 2 ? "Image" : kindCode === 3 ? "File" : "Text";
  const name = new TextDecoder().decode(bytes.subarray(7, 7 + nameLength));
  return { kind, name, data: bytes.slice(7 + nameLength) };
}

export function encodeFrameText(header: FrameHeader, block: Uint8Array): string {
  return FRAME_PREFIX + bytesToBase64(packFrame(header, block));
}

export function decodeFrameText(value: string) {
  if (!value.startsWith(FRAME_PREFIX)) return null;
  try {
    return parseFrame(base64ToBytes(value.slice(FRAME_PREFIX.length)));
  } catch {
    return null;
  }
}

