// Sender: turn a file into an endless fountain-coded QR stream.
//
// Tuning notes from the experiments this PoC is distilled from:
// - Frame payload sets the QR version; denser wins on goodput as long as the
//   receiver can still decode it. 1465 bytes ≈ V27 is a safe middle ground
//   for arbitrary monitors; 2953 (V40) is the ceiling and works phone-to-
//   phone at close range.
// - The mask pattern is pinned (any declared mask is valid to a decoder);
//   this skips the spec's 8-way mask evaluation and speeds generation ~4×.
// - Displays need each frame shown for ≥2 refresh cycles or captures catch
//   the transition; 24 fps on a 60 Hz screen is comfortable.
// - Error correction stays at L by default: the fountain layer already
//   handles erasures, and a frame is either decoded whole or discarded.

import QRCode from "qrcode";
import { LTEncoder } from "../shared/fountain";
import { fnv1a, type FrameHeader } from "../shared/protocol";
import {
  FRAME_BLOCK_BYTES,
  MAX_PAYLOAD_BYTES,
  encodeFrameText,
  packEnvelope,
  type UniClipboardEnvelope,
} from "../shared/uniclipboard";

const MARGIN = 4; // quiet-zone modules
const LOOKAHEAD = 3;

const canvas = document.getElementById("qr") as HTMLCanvasElement;
const specs = document.getElementById("specs")!;
const cfgFps = document.getElementById("cfg-fps") as HTMLSelectElement;
const cfgEcc = document.getElementById("cfg-ecc") as HTMLSelectElement;
const cfgSize = document.getElementById("cfg-size") as HTMLInputElement;
const sourceFile = document.getElementById("source-file") as HTMLInputElement;
const sourceText = document.getElementById("source-text") as HTMLTextAreaElement;
const startButton = document.getElementById("start-stream") as HTMLButtonElement;

let generation = 0; // bumped on every restart; stale loops see it and die
let selectedEnvelope: UniClipboardEnvelope | null = null;

async function readSource(): Promise<UniClipboardEnvelope | null> {
  const file = sourceFile.files?.[0];
  if (file) {
    const kind = file.type.startsWith("image/") ? "Image" : "File";
    return { kind, name: file.name, data: new Uint8Array(await file.arrayBuffer()) };
  }
  const text = sourceText.value;
  if (text.length > 0) return { kind: "Text", name: "", data: new TextEncoder().encode(text) };
  return null;
}

async function main() {
  for (const el of [cfgFps, cfgEcc, cfgSize]) {
    el.addEventListener("change", () => {
      if (selectedEnvelope) void startStream(selectedEnvelope);
    });
  }
  sourceFile.addEventListener("change", () => {
    if (sourceFile.files?.length) sourceText.value = "";
  });
  sourceText.addEventListener("input", () => {
    if (sourceText.value.length > 0) sourceFile.value = "";
  });
  startButton.addEventListener("click", async () => {
    const envelope = await readSource();
    if (!envelope) {
      specs.textContent = "✗ 请先选择文件或输入文本";
      return;
    }
    selectedEnvelope = envelope;
    await startStream(envelope);
  });
  try {
    await (navigator as Navigator & { wakeLock?: { request(t: "screen"): Promise<unknown> } })
      .wakeLock?.request("screen");
  } catch {
    /* fine without it */
  }
}

async function startStream(envelope: UniClipboardEnvelope) {
  const gen = ++generation;
  const payload = packEnvelope(envelope);
  if (payload.length > MAX_PAYLOAD_BYTES) {
    specs.textContent = "✗ 当前兼容模式最多支持 4 MB";
    return;
  }
  const txFps = Number(cfgFps.value);
  const ecc = cfgEcc.value as "L" | "M" | "Q" | "H";
  const displayPx = Number(cfgSize.value);

  const sessionId = (Math.floor(Math.random() * 0xffff) + 1) & 0xffff;
  const blockLen = FRAME_BLOCK_BYTES;
  const encoder = new LTEncoder(payload, blockLen, sessionId);
  const header: FrameHeader = {
    sessionId,
    seq: 0,
    k: encoder.k,
    blockLen,
    totalLen: payload.length,
    payloadFnv: fnv1a(payload),
  };

  let version: number | undefined; // locked after the first frame
  let modules = 0;
  let scale = 1;
  const staging = document.createElement("canvas");
  const queue: ImageData[] = [];
  let nextSeq = 0;

  const sizeCanvas = () => {
    const dpr = window.devicePixelRatio || 1;
    const total = modules + 2 * MARGIN;
    const cssBudget = Math.min(0.9 * Math.min(window.innerWidth, window.innerHeight), displayPx);
    scale = Math.max(1, Math.floor((cssBudget * dpr) / total));
    staging.width = total;
    staging.height = total;
    canvas.width = total * scale;
    canvas.height = total * scale;
    canvas.style.width = `${(total * scale) / dpr}px`;
    canvas.style.height = `${(total * scale) / dpr}px`;
  };

  const makeFrame = (): ImageData => {
    const frameText = encodeFrameText({ ...header, seq: nextSeq }, encoder.encode(nextSeq));
    nextSeq++;
    const qr = QRCode.create(frameText, {
      errorCorrectionLevel: ecc,
      version,
      maskPattern: 4,
    });
    if (version === undefined) {
      version = qr.version;
      modules = qr.modules.size;
      sizeCanvas();
      specs.textContent =
        `${envelope.kind} · ${envelope.name || "文本"} · ${txFps} FPS · ` +
        `${blockLen} bytes/block · V${version} · ECC ${ecc} · ` +
        `${Math.round(payload.length / 1024)} KB · K=${encoder.k}`;
    }
    const size = qr.modules.size;
    const data = qr.modules.data;
    const total = size + 2 * MARGIN;
    const img = new ImageData(total, total);
    const px = new Uint32Array(img.data.buffer);
    px.fill(0xffffffff);
    for (let y = 0; y < size; y++) {
      const row = (y + MARGIN) * total + MARGIN;
      const src = y * size;
      for (let x = 0; x < size; x++) {
        if (data[src + x]) px[row + x] = 0xff000000;
      }
    }
    return img;
  };

  const pump = () => {
    if (gen !== generation) return; // superseded by a settings change
    try {
      while (queue.length < LOOKAHEAD) queue.push(makeFrame());
    } catch (err) {
      // e.g. frame bytes over capacity for the chosen ECC level
      specs.textContent = `✗ ${err instanceof Error ? err.message : String(err)}`;
      return;
    }
    setTimeout(pump, 0);
  };
  pump();

  const interval = 1000 / txFps;
  let nextAt = performance.now();
  const tick = (now: number) => {
    if (gen !== generation) return;
    requestAnimationFrame(tick);
    if (now < nextAt) return;
    const img = queue.shift();
    if (!img) {
      nextAt = now + interval;
      return;
    }
    staging.getContext("2d")!.putImageData(img, 0, 0);
    const ctx = canvas.getContext("2d")!;
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(staging, 0, 0, canvas.width, canvas.height);
    nextAt += interval;
    if (now - nextAt > 3 * interval) nextAt = now + interval; // fell behind — don't burst
  };
  requestAnimationFrame(tick);
}

void main();

