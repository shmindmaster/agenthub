/**
 * A minimal PNG reader for frame measurement, and a matching writer for
 * fixtures.
 *
 * Why not a dependency: Media Studio's gates run offline on a render box with
 * no install step, and the measurement only needs what the kit itself emits —
 * 8-bit, non-interlaced, RGB or RGBA, no palette. Anything else is refused by
 * name rather than decoded into wrong pixels, because a frame metric computed
 * from a mis-read buffer is worse than a gate that says it cannot read the
 * frame.
 *
 * encodePng exists so tests and fixtures can round-trip without a dependency.
 * It is test support, not a general encoder: one filter, colour type 6, 8-bit.
 */
import { deflateSync, inflateSync } from 'node:zlib';

export class PngError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'PngError';
    this.code = code;
  }
}

const SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const CHANNELS = { 2: 3, 6: 4 };
const MAX_RGBA_BYTES = 256 * 1024 * 1024;

/* ------------------------------------------------------------------ crc32 -- */

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

/** PNG's CRC-32 (IEEE 802.3, reflected, init/xor 0xFFFFFFFF). */
export const crc32 = (bytes) => {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i += 1) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};

/* ---------------------------------------------------------------- reading -- */

const asBuffer = (buffer) => {
  if (buffer instanceof Uint8Array) return Buffer.isBuffer(buffer) ? buffer : Buffer.from(buffer.buffer, buffer.byteOffset, buffer.byteLength);
  throw new PngError('not-png', 'decodePng expects a Buffer or Uint8Array');
};

const readUInt32 = (bytes, offset) =>
  ((bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]) >>> 0;

const chunkType = (bytes, offset) => Buffer.from(bytes.subarray(offset, offset + 4)).toString('latin1');

const parseHeader = (data) => {
  if (data.length !== 13) throw new PngError('corrupt', `IHDR is ${data.length} bytes, not 13`);
  const width = readUInt32(data, 0);
  const height = readUInt32(data, 4);
  const bitDepth = data[8];
  const colourType = data[9];
  const compression = data[10];
  const filter = data[11];
  const interlace = data[12];
  if (!width || !height) throw new PngError('corrupt', `IHDR declares ${width}x${height}`);
  if (bitDepth !== 8) {
    throw new PngError('unsupported-bit-depth', `bit depth ${bitDepth} is not supported; only 8-bit frames are measured`);
  }
  if (!CHANNELS[colourType]) {
    throw new PngError(
      'unsupported-colour-type',
      `colour type ${colourType} is not supported; only 2 (RGB) and 6 (RGBA) are read`,
    );
  }
  if (compression !== 0) throw new PngError('unsupported-compression', `compression method ${compression} is not deflate`);
  if (filter !== 0) throw new PngError('unsupported-filter-method', `filter method ${filter} is not 0`);
  if (interlace !== 0) throw new PngError('unsupported-interlace', `interlace method ${interlace} is not supported`);
  if (width * height * 4 > MAX_RGBA_BYTES) {
    throw new PngError('unsupported-size', `${width}x${height} is larger than this reader keeps in memory`);
  }
  return { width, height, colourType, channels: CHANNELS[colourType] };
};

const paeth = (a, b, c) => {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
};

/** Undo the five scanline filters into one packed pixel buffer. */
const unfilter = (raw, width, height, channels) => {
  const stride = width * channels;
  const expected = height * (stride + 1);
  if (raw.length !== expected) {
    throw new PngError('corrupt', `inflated ${raw.length} bytes; ${width}x${height} needs ${expected}`);
  }
  const out = Buffer.alloc(height * stride);
  for (let y = 0; y < height; y += 1) {
    const filter = raw[y * (stride + 1)];
    const src = y * (stride + 1) + 1;
    const dst = y * stride;
    const prior = dst - stride;
    switch (filter) {
      case 0:
        raw.copy(out, dst, src, src + stride);
        break;
      case 1:
        for (let i = 0; i < stride; i += 1) {
          const left = i >= channels ? out[dst + i - channels] : 0;
          out[dst + i] = (raw[src + i] + left) & 0xff;
        }
        break;
      case 2:
        for (let i = 0; i < stride; i += 1) {
          const up = y > 0 ? out[prior + i] : 0;
          out[dst + i] = (raw[src + i] + up) & 0xff;
        }
        break;
      case 3:
        for (let i = 0; i < stride; i += 1) {
          const left = i >= channels ? out[dst + i - channels] : 0;
          const up = y > 0 ? out[prior + i] : 0;
          out[dst + i] = (raw[src + i] + ((left + up) >> 1)) & 0xff;
        }
        break;
      case 4:
        for (let i = 0; i < stride; i += 1) {
          const left = i >= channels ? out[dst + i - channels] : 0;
          const up = y > 0 ? out[prior + i] : 0;
          const upLeft = y > 0 && i >= channels ? out[prior + i - channels] : 0;
          out[dst + i] = (raw[src + i] + paeth(left, up, upLeft)) & 0xff;
        }
        break;
      default:
        throw new PngError('corrupt', `scanline ${y} declares filter ${filter}; PNG defines 0-4`);
    }
  }
  return out;
};

/**
 * Decode an 8-bit non-interlaced RGB/RGBA PNG into row-major RGBA8.
 * Every refusal names what the file is, because "unsupported" alone sends the
 * reader back to the renderer without knowing what to change.
 */
export const decodePng = (buffer) => {
  const bytes = asBuffer(buffer);
  if (bytes.length < SIGNATURE.length + 12) throw new PngError('not-png', 'file is too short to be a PNG');
  for (let i = 0; i < SIGNATURE.length; i += 1) {
    if (bytes[i] !== SIGNATURE[i]) throw new PngError('not-png', 'file does not start with the PNG signature');
  }

  let header = null;
  const idat = [];
  let offset = 8;
  let sawEnd = false;
  while (offset + 8 <= bytes.length) {
    const length = readUInt32(bytes, offset);
    const type = chunkType(bytes, offset + 4);
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    if (dataEnd + 4 > bytes.length) {
      throw new PngError('truncated', `chunk ${type} declares ${length} bytes but the file ends first`);
    }
    const stored = readUInt32(bytes, dataEnd);
    if (crc32(bytes.subarray(offset + 4, dataEnd)) !== stored) {
      throw new PngError('corrupt', `${type} chunk CRC does not match its contents`);
    }
    if (type === 'IHDR') header = parseHeader(bytes.subarray(dataStart, dataEnd));
    else if (type === 'IDAT') idat.push(bytes.subarray(dataStart, dataEnd));
    else if (type === 'IEND') {
      sawEnd = true;
      break;
    }
    offset = dataEnd + 4;
  }

  if (!header) throw new PngError('corrupt', 'no IHDR chunk');
  if (!idat.length) throw new PngError('corrupt', 'no IDAT chunk');
  if (!sawEnd) throw new PngError('truncated', 'no IEND chunk');

  const { width, height, channels } = header;
  const expected = height * (width * channels + 1);
  let raw;
  try {
    raw = inflateSync(Buffer.concat(idat), { maxOutputLength: expected });
  } catch (error) {
    throw new PngError('corrupt', `IDAT does not inflate to ${expected} bytes: ${error.message}`);
  }
  const pixels = unfilter(raw, width, height, channels);

  if (channels === 4) return { width, height, rgba: new Uint8Array(pixels.buffer, pixels.byteOffset, pixels.length) };
  const rgba = new Uint8Array(width * height * 4);
  for (let i = 0, j = 0; j < rgba.length; i += 3, j += 4) {
    rgba[j] = pixels[i];
    rgba[j + 1] = pixels[i + 1];
    rgba[j + 2] = pixels[i + 2];
    rgba[j + 3] = 0xff;
  }
  return { width, height, rgba };
};

/* ---------------------------------------------------------------- writing -- */

/* Test support only: filter 0 on every row, colour type 6, no palette, no
 * interlace. A real encoder belongs behind a dependency we do not want here. */

const chunk = (type, data) => {
  const head = Buffer.alloc(4);
  head.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([head, body, crc]);
};

export const encodePng = ({ width, height, rgba }) => {
  if (!Number.isInteger(width) || width <= 0) throw new PngError('bad-input', `width must be a positive integer, got ${width}`);
  if (!Number.isInteger(height) || height <= 0) throw new PngError('bad-input', `height must be a positive integer, got ${height}`);
  if (!(rgba instanceof Uint8Array || rgba instanceof Uint8ClampedArray)) {
    throw new PngError('bad-input', 'rgba must be a Uint8Array of RGBA bytes');
  }
  if (rgba.length !== width * height * 4) {
    throw new PngError('bad-input', `rgba length ${rgba.length} does not match ${width}x${height}x4`);
  }

  const stride = width * 4;
  const raw = Buffer.alloc(height * (stride + 1));
  for (let y = 0; y < height; y += 1) {
    const dst = y * (stride + 1);
    raw[dst] = 0;
    Buffer.from(rgba.buffer, rgba.byteOffset + y * stride, stride).copy(raw, dst + 1);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  return Buffer.concat([
    Buffer.from(SIGNATURE),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
};
