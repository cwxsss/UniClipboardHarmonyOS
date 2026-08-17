import { util } from '@kit.ArkTS';

// Fountain coding and frame protocol adapted from decimen-optical-transfer.
// Copyright (c) 2026 BashAlarmist, used under the MIT License.

const FRAME_PREFIX: string = 'UCO1:';
const HEADER_LENGTH: number = 20;
const MAGIC_0: number = 0xD1;
const MAGIC_1: number = 0x0C;
const ENVELOPE_MAGIC_0: number = 0x55;
const ENVELOPE_MAGIC_1: number = 0x43;
const ENVELOPE_MAGIC_2: number = 0x4F;
const ENVELOPE_MAGIC_3: number = 0x31;
const SOLITON_C: number = 0.1;
const SOLITON_DELTA: number = 0.5;
const LN_2: number = 0.6931471805599453;

export const OPTICAL_FRAME_BYTES: number = 288;
export const OPTICAL_MAX_PAYLOAD_BYTES: number = 4 * 1024 * 1024;

export class OpticalTransferEnvelope {
  kind: string = 'Text';
  name: string = '';
  data: Uint8Array = new Uint8Array(0);

  constructor(kind: string, name: string, data: Uint8Array) {
    this.kind = kind;
    this.name = name;
    this.data = data;
  }
}

export class OpticalFrame {
  sessionId: number = 0;
  sequence: number = 0;
  blockCount: number = 0;
  blockLength: number = 0;
  totalLength: number = 0;
  payloadHash: number = 0;
  block: Uint8Array = new Uint8Array(0);
}

class OpticalPendingFrame {
  indices: number[] = [];
  bytes: Uint8Array = new Uint8Array(0);
  active: boolean = true;

  constructor(indices: number[], bytes: Uint8Array) {
    this.indices = indices;
    this.bytes = bytes;
  }
}

function deterministicLog(value: number): number {
  let exponent: number = 0;
  let mantissa: number = value;
  while (mantissa >= 1.5) {
    mantissa /= 2;
    exponent += 1;
  }
  while (mantissa < 0.75) {
    mantissa *= 2;
    exponent -= 1;
  }
  let z: number = (mantissa - 1) / (mantissa + 1);
  let zSquared: number = z * z;
  let term: number = z;
  let sum: number = 0;
  for (let n: number = 1; n <= 21; n += 2) {
    sum += term / n;
    term *= zSquared;
  }
  return exponent * LN_2 + 2 * sum;
}

function createSolitonCdf(blockCount: number): Float64Array {
  let cdf: Float64Array = new Float64Array(blockCount);
  if (blockCount === 1) {
    cdf[0] = 1;
    return cdf;
  }
  let robustValue: number = Math.max(1,
    SOLITON_C * deterministicLog(blockCount / SOLITON_DELTA) * Math.sqrt(blockCount));
  let spike: number = Math.min(blockCount, Math.ceil(blockCount / robustValue));
  let total: number = 0;
  for (let degree: number = 1; degree <= blockCount; degree += 1) {
    let rho: number = degree === 1 ? 1 / blockCount : 1 / (degree * (degree - 1));
    let tau: number = 0;
    if (degree < spike) {
      tau = robustValue / (degree * blockCount);
    } else if (degree === spike) {
      tau = robustValue * Math.max(0, deterministicLog(robustValue / SOLITON_DELTA)) / blockCount;
    }
    total += rho + tau;
    cdf[degree - 1] = total;
  }
  for (let index: number = 0; index < blockCount; index += 1) {
    cdf[index] = cdf[index] / total;
  }
  cdf[blockCount - 1] = 1;
  return cdf;
}

class OpticalRandom {
  private state: number = 0;

  constructor(seed: number) {
    this.state = seed | 0;
  }

  next(): number {
    this.state = (this.state + 0x9E3779B9) | 0;
    let value: number = this.state ^ (this.state >>> 16);
    value = Math.imul(value, 0x21F0AAAD);
    value ^= value >>> 15;
    value = Math.imul(value, 0x735A2D97);
    value ^= value >>> 15;
    return value >>> 0;
  }
}

function frameSeed(sessionId: number, sequence: number): number {
  let hash: number = (Math.imul(sessionId + 1, 0x9E3779B1) ^ (sequence + 0x85EBCA6B)) | 0;
  hash = Math.imul(hash ^ (hash >>> 13), 0xC2B2AE35);
  return (hash ^ (hash >>> 16)) | 0;
}

function frameIndices(blockCount: number, cdf: Float64Array, sessionId: number,
  sequence: number): number[] {
  let random: OpticalRandom = new OpticalRandom(frameSeed(sessionId, sequence));
  let sample: number = random.next() * Math.pow(2, -32);
  let low: number = 0;
  let high: number = blockCount - 1;
  while (low < high) {
    let middle: number = (low + high) >> 1;
    if (cdf[middle] >= sample) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }
  let degree: number = Math.min(blockCount, low + 1);
  let selected: boolean[] = new Array<boolean>(blockCount).fill(false);
  let output: number[] = [];
  while (output.length < degree) {
    let index: number = random.next() % blockCount;
    if (!selected[index]) {
      selected[index] = true;
      output.push(index);
    }
  }
  return output;
}

function xorBytes(destination: Uint8Array, source: Uint8Array): void {
  for (let index: number = 0; index < destination.length; index += 1) {
    destination[index] = destination[index] ^ source[index];
  }
}

export function opticalFnv1a(bytes: Uint8Array): number {
  let hash: number = 0x811C9DC5;
  for (let index: number = 0; index < bytes.length; index += 1) {
    hash ^= bytes[index];
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

export function packOpticalEnvelope(kind: string, name: string, data: Uint8Array): Uint8Array {
  let encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  let nameBytes: Uint8Array = encoder.encodeInto(name);
  if (nameBytes.length > 65535) {
    throw new Error('optical transfer name is too long');
  }
  let kindCode: number = kind === 'Image' ? 2 : kind === 'File' ? 3 : 1;
  let output: Uint8Array = new Uint8Array(7 + nameBytes.length + data.length);
  output[0] = ENVELOPE_MAGIC_0;
  output[1] = ENVELOPE_MAGIC_1;
  output[2] = ENVELOPE_MAGIC_2;
  output[3] = ENVELOPE_MAGIC_3;
  output[4] = kindCode;
  output[5] = nameBytes.length & 0xFF;
  output[6] = (nameBytes.length >>> 8) & 0xFF;
  output.set(nameBytes, 7);
  output.set(data, 7 + nameBytes.length);
  return output;
}

export function unpackOpticalEnvelope(bytes: Uint8Array): OpticalTransferEnvelope | null {
  if (bytes.length < 7 || bytes[0] !== ENVELOPE_MAGIC_0 || bytes[1] !== ENVELOPE_MAGIC_1 ||
    bytes[2] !== ENVELOPE_MAGIC_2 || bytes[3] !== ENVELOPE_MAGIC_3) {
    return null;
  }
  let kindCode: number = bytes[4];
  if (kindCode < 1 || kindCode > 3) {
    return null;
  }
  let nameLength: number = bytes[5] | (bytes[6] << 8);
  if (7 + nameLength > bytes.length) {
    return null;
  }
  let decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true });
  let name: string = decoder.decodeToString(bytes.subarray(7, 7 + nameLength));
  let data: Uint8Array = bytes.slice(7 + nameLength);
  let kind: string = kindCode === 2 ? 'Image' : kindCode === 3 ? 'File' : 'Text';
  return new OpticalTransferEnvelope(kind, name, data);
}

export class OpticalFountainEncoder {
  readonly blockCount: number;
  readonly blockLength: number;
  readonly sessionId: number;
  readonly totalLength: number;
  readonly payloadHash: number;
  private blocks: Uint8Array[] = [];
  private cdf: Float64Array;

  constructor(payload: Uint8Array, blockLength: number, sessionId: number) {
    this.blockLength = blockLength;
    this.sessionId = sessionId;
    this.totalLength = payload.length;
    this.payloadHash = opticalFnv1a(payload);
    this.blockCount = Math.max(1, Math.ceil(payload.length / blockLength));
    for (let blockIndex: number = 0; blockIndex < this.blockCount; blockIndex += 1) {
      let block: Uint8Array = new Uint8Array(blockLength);
      let start: number = blockIndex * blockLength;
      let end: number = Math.min(start + blockLength, payload.length);
      block.set(payload.subarray(start, end));
      this.blocks.push(block);
    }
    this.cdf = createSolitonCdf(this.blockCount);
  }

  encode(sequence: number): Uint8Array {
    let indices: number[] = frameIndices(this.blockCount, this.cdf, this.sessionId, sequence);
    let output: Uint8Array = new Uint8Array(this.blockLength);
    for (let index: number = 0; index < indices.length; index += 1) {
      xorBytes(output, this.blocks[indices[index]]);
    }
    return output;
  }

  frameText(sequence: number): string {
    let frameBytes: Uint8Array = new Uint8Array(HEADER_LENGTH + this.blockLength);
    let dataView: DataView = new DataView(frameBytes.buffer);
    dataView.setUint8(0, MAGIC_0);
    dataView.setUint8(1, MAGIC_1);
    dataView.setUint16(2, this.sessionId, true);
    dataView.setUint32(4, sequence, true);
    dataView.setUint16(8, this.blockCount, true);
    dataView.setUint16(10, this.blockLength, true);
    dataView.setUint32(12, this.totalLength, true);
    dataView.setUint32(16, this.payloadHash, true);
    frameBytes.set(this.encode(sequence), HEADER_LENGTH);
    let base64: util.Base64Helper = new util.Base64Helper();
    return FRAME_PREFIX + base64.encodeToStringSync(frameBytes, util.Type.BASIC);
  }
}

export function parseOpticalFrame(value: string): OpticalFrame | null {
  if (!value.startsWith(FRAME_PREFIX)) {
    return null;
  }
  try {
    let base64: util.Base64Helper = new util.Base64Helper();
    let bytes: Uint8Array = base64.decodeSync(value.substring(FRAME_PREFIX.length), util.Type.BASIC);
    if (bytes.length <= HEADER_LENGTH || bytes[0] !== MAGIC_0 || bytes[1] !== MAGIC_1) {
      return null;
    }
    let dataView: DataView = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let frame: OpticalFrame = new OpticalFrame();
    frame.sessionId = dataView.getUint16(2, true);
    frame.sequence = dataView.getUint32(4, true);
    frame.blockCount = dataView.getUint16(8, true);
    frame.blockLength = dataView.getUint16(10, true);
    frame.totalLength = dataView.getUint32(12, true);
    frame.payloadHash = dataView.getUint32(16, true);
    if (frame.blockCount === 0 || frame.blockLength === 0 || frame.totalLength === 0 ||
      frame.totalLength > OPTICAL_MAX_PAYLOAD_BYTES || bytes.length !== HEADER_LENGTH + frame.blockLength) {
      return null;
    }
    frame.block = bytes.slice(HEADER_LENGTH);
    return frame;
  } catch (error) {
    return null;
  }
}

export class OpticalFountainDecoder {
  readonly blockCount: number;
  readonly blockLength: number;
  readonly sessionId: number;
  readonly totalLength: number;
  readonly payloadHash: number;
  solvedCount: number = 0;
  framesNew: number = 0;
  framesDuplicate: number = 0;
  private cdf: Float64Array;
  private solved: Array<Uint8Array | null> = [];
  private byBlock: OpticalPendingFrame[][] = [];
  private seen: Set<number> = new Set<number>();

  constructor(frame: OpticalFrame) {
    this.blockCount = frame.blockCount;
    this.blockLength = frame.blockLength;
    this.sessionId = frame.sessionId;
    this.totalLength = frame.totalLength;
    this.payloadHash = frame.payloadHash;
    this.cdf = createSolitonCdf(this.blockCount);
    for (let index: number = 0; index < this.blockCount; index += 1) {
      this.solved.push(null);
      this.byBlock.push([]);
    }
  }

  isCompatible(frame: OpticalFrame): boolean {
    return frame.sessionId === this.sessionId && frame.blockCount === this.blockCount &&
      frame.blockLength === this.blockLength && frame.totalLength === this.totalLength &&
      frame.payloadHash === this.payloadHash;
  }

  isComplete(): boolean {
    return this.solvedCount >= this.blockCount;
  }

  addFrame(frame: OpticalFrame): void {
    if (!this.isCompatible(frame)) {
      return;
    }
    if (this.seen.has(frame.sequence)) {
      this.framesDuplicate += 1;
      return;
    }
    this.seen.add(frame.sequence);
    this.framesNew += 1;
    if (this.isComplete()) {
      return;
    }
    let indices: number[] = frameIndices(this.blockCount, this.cdf, this.sessionId, frame.sequence);
    let bytes: Uint8Array = frame.block.slice();
    for (let index: number = indices.length - 1; index >= 0; index -= 1) {
      let solvedBlock: Uint8Array | null = this.solved[indices[index]];
      if (solvedBlock !== null) {
        xorBytes(bytes, solvedBlock);
        indices.splice(index, 1);
      }
    }
    if (indices.length === 0) {
      return;
    }
    if (indices.length === 1) {
      this.resolve(indices[0], bytes);
      return;
    }
    let pending: OpticalPendingFrame = new OpticalPendingFrame(indices, bytes);
    for (let index: number = 0; index < indices.length; index += 1) {
      this.byBlock[indices[index]].push(pending);
    }
  }

  private resolve(firstBlock: number, firstBytes: Uint8Array): void {
    let blockQueue: number[] = [firstBlock];
    let byteQueue: Uint8Array[] = [firstBytes];
    while (blockQueue.length > 0) {
      let blockIndex: number = blockQueue.pop() as number;
      let blockBytes: Uint8Array = byteQueue.pop() as Uint8Array;
      if (this.solved[blockIndex] !== null) {
        continue;
      }
      this.solved[blockIndex] = blockBytes;
      this.solvedCount += 1;
      let waiting: OpticalPendingFrame[] = this.byBlock[blockIndex];
      this.byBlock[blockIndex] = [];
      for (let pendingIndex: number = 0; pendingIndex < waiting.length; pendingIndex += 1) {
        let pending: OpticalPendingFrame = waiting[pendingIndex];
        if (!pending.active) {
          continue;
        }
        xorBytes(pending.bytes, blockBytes);
        let removeAt: number = pending.indices.indexOf(blockIndex);
        if (removeAt >= 0) {
          pending.indices.splice(removeAt, 1);
        }
        if (pending.indices.length === 0) {
          pending.active = false;
        } else if (pending.indices.length === 1) {
          pending.active = false;
          blockQueue.push(pending.indices[0]);
          byteQueue.push(pending.bytes);
        }
      }
    }
  }

  assemble(): Uint8Array | null {
    if (!this.isComplete()) {
      return null;
    }
    let output: Uint8Array = new Uint8Array(this.totalLength);
    for (let blockIndex: number = 0; blockIndex < this.blockCount; blockIndex += 1) {
      let block: Uint8Array | null = this.solved[blockIndex];
      if (block === null) {
        return null;
      }
      let start: number = blockIndex * this.blockLength;
      let length: number = Math.min(this.blockLength, this.totalLength - start);
      output.set(block.subarray(0, length), start);
    }
    if (opticalFnv1a(output) !== this.payloadHash) {
      return null;
    }
    return output;
  }
}
