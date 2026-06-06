import { image } from '@kit.ImageKit';
import { AppConstants } from '../common/Constants';

const BAYER_4X4: number[] = [
  0, 8, 2, 10,
  12, 4, 14, 6,
  3, 11, 1, 9,
  15, 7, 13, 5
];

function paletteSampleBudget(pixelCount: number, frameCount: number, quality: number): number {
  if (quality === AppConstants.QUALITY_ULTRA) {
    return pixelCount;
  }
  if (quality === AppConstants.QUALITY_WECHAT) {
    return Math.max(1, Math.floor(26000 / Math.max(frameCount, 1)));
  }
  return Math.max(1, Math.floor(70000 / Math.max(frameCount, 1)));
}

function clampColor(value: number): number {
  if (value < 0) {
    return 0;
  }
  if (value > 255) {
    return 255;
  }
  return value;
}

function buildPalette(frames: Uint8Array[], width: number, height: number, quality: number): Uint8Array {
  let hist: Uint32Array = new Uint32Array(32768);
  let pixelsPerFrame: number = width * height;
  let sampleBudget: number = paletteSampleBudget(pixelsPerFrame, frames.length, quality);

  for (let frame of frames) {
    let step: number = Math.max(1, Math.floor(pixelsPerFrame / sampleBudget));
    for (let p: number = 0; p < pixelsPerFrame; p += step) {
      let off: number = p * 4;
      let key: number = ((frame[off] >> 3) << 10) | ((frame[off + 1] >> 3) << 5) | (frame[off + 2] >> 3);
      hist[key]++;
    }
  }

  let keys: number[] = [];
  for (let i: number = 0; i < hist.length; i++) {
    if (hist[i] > 0) {
      keys.push(i);
    }
  }
  keys.sort((a: number, b: number): number => hist[b] - hist[a]);

  let palette: Uint8Array = new Uint8Array(768);
  let count: number = Math.min(256, keys.length);
  for (let i: number = 0; i < count; i++) {
    let key: number = keys[i];
    palette[i * 3] = ((key >> 10) & 0x1F) * 8 + 4;
    palette[i * 3 + 1] = ((key >> 5) & 0x1F) * 8 + 4;
    palette[i * 3 + 2] = (key & 0x1F) * 8 + 4;
  }
  return palette;
}

function nearestPaletteIndex(key: number, palette: Uint8Array, cache: Int16Array): number {
  let cached: number = cache[key];
  if (cached >= 0) {
    return cached;
  }

  let r: number = ((key >> 10) & 0x1F) * 8 + 4;
  let g: number = ((key >> 5) & 0x1F) * 8 + 4;
  let b: number = (key & 0x1F) * 8 + 4;
  let best: number = 0;
  let bestDist: number = 2147483647;
  for (let i: number = 0; i < 256; i++) {
    let dr: number = r - palette[i * 3];
    let dg: number = g - palette[i * 3 + 1];
    let db: number = b - palette[i * 3 + 2];
    let dist: number = dr * dr + dg * dg + db * db;
    if (dist < bestDist) {
      bestDist = dist;
      best = i;
      if (dist === 0) {
        break;
      }
    }
  }
  cache[key] = best;
  return best;
}

function mapPixels(frame: Uint8Array, palette: Uint8Array, cache: Int16Array, pixelCount: number, width: number,
  quality: number): Uint8Array {
  let indices: Uint8Array = new Uint8Array(pixelCount);
  for (let p: number = 0; p < pixelCount; p++) {
    let off: number = p * 4;
    let r: number = frame[off];
    let g: number = frame[off + 1];
    let b: number = frame[off + 2];
    if (quality === AppConstants.QUALITY_ULTRA) {
      let x: number = p % width;
      let y: number = Math.floor(p / width);
      let delta: number = (BAYER_4X4[(y & 3) * 4 + (x & 3)] - 8) * 2;
      r = clampColor(r + delta);
      g = clampColor(g + delta);
      b = clampColor(b + delta);
    }
    let key: number = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
    indices[p] = nearestPaletteIndex(key, palette, cache);
  }
  return indices;
}

class BitWriter {
  bytes: number[] = [];
  bits: number = 0;
  bitCount: number = 0;
  codeSize: number;
  minCodeSize: number;
  clearCode: number;
  endCode: number;
  nextCode: number;
  limit: number;

  constructor(minCodeSize: number) {
    this.minCodeSize = minCodeSize;
    this.clearCode = 1 << minCodeSize;
    this.endCode = this.clearCode + 1;
    this.nextCode = this.endCode + 1;
    this.codeSize = minCodeSize + 1;
    this.limit = 1 << this.codeSize;
  }

  write(code: number): void {
    this.bits |= code << this.bitCount;
    this.bitCount += this.codeSize;
    while (this.bitCount >= 8) {
      this.bytes.push(this.bits & 0xFF);
      this.bits >>= 8;
      this.bitCount -= 8;
    }
  }

  reset(): void {
    this.nextCode = this.endCode + 1;
    this.codeSize = this.minCodeSize + 1;
    this.limit = 1 << this.codeSize;
  }

  growIfNeeded(): void {
    if (this.nextCode >= this.limit && this.codeSize < 12) {
      this.codeSize++;
      this.limit = 1 << this.codeSize;
    }
  }

  finish(): Uint8Array {
    if (this.bitCount > 0) {
      this.bytes.push(this.bits & 0xFF);
    }
    return new Uint8Array(this.bytes);
  }
}

function lzwEncode(indices: Uint8Array): Uint8Array {
  let writer: BitWriter = new BitWriter(8);
  writer.write(writer.clearCode);

  if (indices.length === 0) {
    writer.write(writer.endCode);
    return writer.finish();
  }

  // Emit literal color-index codes and reset often. This is larger than a full
  // dictionary encoder, but it keeps GIF code-size state simple and reliable.
  let codesAfterClear: number = 0;
  for (let i: number = 0; i < indices.length; i++) {
    writer.write(indices[i]);
    if (codesAfterClear > 0) {
      writer.nextCode++;
      writer.growIfNeeded();
    }
    codesAfterClear++;
    if (codesAfterClear >= 240 && i < indices.length - 1) {
      writer.write(writer.clearCode);
      writer.reset();
      codesAfterClear = 0;
    }
  }

  writer.write(writer.endCode);
  return writer.finish();
}

function subBlocks(data: Uint8Array): Uint8Array {
  let blocks: number[] = [];
  let offset: number = 0;
  while (offset < data.length) {
    let len: number = Math.min(255, data.length - offset);
    blocks.push(len);
    for (let i: number = 0; i < len; i++) {
      blocks.push(data[offset + i]);
    }
    offset += len;
  }
  blocks.push(0);
  return new Uint8Array(blocks);
}

function pushShort(out: number[], value: number): void {
  out.push(value & 0xFF, (value >> 8) & 0xFF);
}

export class GifBinaryEncoder {
  static encode(frames: Uint8Array[], width: number, height: number, frameDelayCs: number, loop: boolean,
    quality: number): ArrayBuffer {
    let out: number[] = [];
    let delay: number = Math.max(2, Math.min(65535, Math.round(frameDelayCs)));
    let pixelCount: number = width * height;
    let palette: Uint8Array = buildPalette(frames, width, height, quality);
    let cache: Int16Array = new Int16Array(32768);
    for (let i: number = 0; i < cache.length; i++) {
      cache[i] = -1;
    }

    out.push(0x47, 0x49, 0x46, 0x38, 0x39, 0x61);
    pushShort(out, width);
    pushShort(out, height);
    out.push(0xF7, 0x00, 0x00);
    for (let b of palette) {
      out.push(b);
    }

    if (loop) {
      out.push(0x21, 0xFF, 0x0B);
      for (let c of 'NETSCAPE2.0') {
        out.push(c.charCodeAt(0));
      }
      out.push(0x03, 0x01, 0x00, 0x00, 0x00);
    }

    for (let frame of frames) {
      out.push(0x21, 0xF9, 0x04, 0x00);
      pushShort(out, delay);
      out.push(0x00, 0x00);
      out.push(0x2C);
      pushShort(out, 0);
      pushShort(out, 0);
      pushShort(out, width);
      pushShort(out, height);
      out.push(0x00);
      out.push(0x08);

      let encoded: Uint8Array = lzwEncode(mapPixels(frame, palette, cache, pixelCount, width, quality));
      let blocks: Uint8Array = subBlocks(encoded);
      for (let b of blocks) {
        out.push(b);
      }
    }

    out.push(0x3B);
    return new Uint8Array(out).buffer;
  }
}

export async function readPixelMapRgba(pixelMap: image.PixelMap, width: number, height: number): Promise<Uint8Array> {
  let info: image.ImageInfo = await pixelMap.getImageInfo();
  if (info.pixelFormat !== image.PixelMapFormat.RGBA_8888) {
    try {
      await pixelMap.convertPixelFormat(image.PixelMapFormat.RGBA_8888);
      info = await pixelMap.getImageInfo();
    } catch (_err) {
    }
  }
  let actualW: number = info.size.width;
  let actualH: number = info.size.height;
  let rowStride: number = pixelMap.getBytesNumberPerRow();
  let pixelBytes: number = pixelMap.getPixelBytesNumber();
  let raw: ArrayBuffer = new ArrayBuffer(Math.max(pixelBytes, rowStride * actualH));
  await pixelMap.readPixelsToBuffer(raw);
  let bytes: Uint8Array = new Uint8Array(raw);
  let bgra: boolean = info.pixelFormat === image.PixelMapFormat.BGRA_8888;

  if (!bgra && actualW === width && actualH === height && rowStride === actualW * 4) {
    return bytes.slice(0, width * height * 4);
  }

  let result: Uint8Array = new Uint8Array(width * height * 4);
  for (let y: number = 0; y < height; y++) {
    let sy: number = Math.min(actualH - 1, Math.floor(y * actualH / height));
    for (let x: number = 0; x < width; x++) {
      let sx: number = Math.min(actualW - 1, Math.floor(x * actualW / width));
      let src: number = sy * rowStride + sx * 4;
      let dst: number = (y * width + x) * 4;
      result[dst] = bgra ? bytes[src + 2] : bytes[src];
      result[dst + 1] = bytes[src + 1];
      result[dst + 2] = bgra ? bytes[src] : bytes[src + 2];
      result[dst + 3] = bytes[src + 3];
    }
  }
  return result;
}
