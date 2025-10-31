import fs from "fs";
import path from "path";
import zlib from "zlib";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const OUTPUTS = [
  { size: 64, name: "favicon.png", dir: path.join(__dirname, "..", "client", "public") },
  { size: 192, name: "icon-192.png", dir: path.join(__dirname, "..", "client", "public", "icons") },
  { size: 512, name: "icon-512.png", dir: path.join(__dirname, "..", "client", "public", "icons") },
];

function ensureDir(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

function writePng(filePath, width, height, pixels) {
  const bytesPerPixel = 4;
  const stride = width * bytesPerPixel + 1;
  const rawData = Buffer.alloc(stride * height);

  for (let y = 0; y < height; y += 1) {
    const rowOffset = y * stride;
    rawData[rowOffset] = 0; // filter type 0 (None)
    pixels.copy(rawData, rowOffset + 1, y * width * bytesPerPixel, (y + 1) * width * bytesPerPixel);
  }

  const compressed = zlib.deflateSync(rawData, { level: 9 });

  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const chunks = [];

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type RGBA
  ihdr[10] = 0; // compression method
  ihdr[11] = 0; // filter method
  ihdr[12] = 0; // interlace method
  chunks.push(makeChunk("IHDR", ihdr));

  chunks.push(makeChunk("IDAT", compressed));
  chunks.push(makeChunk("IEND", Buffer.alloc(0)));

  const pngBuffer = Buffer.concat([signature, ...chunks]);
  fs.writeFileSync(filePath, pngBuffer);
}

function makeChunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const typeBuffer = Buffer.from(type, "ascii");
  const crcBuffer = Buffer.alloc(4);
  crcBuffer.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])), 0);
  return Buffer.concat([length, typeBuffer, data, crcBuffer]);
}

function crc32(buffer) {
  let crc = ~0;
  for (let i = 0; i < buffer.length; i += 1) {
    crc = CRC_TABLE[(crc ^ buffer[i]) & 0xff] ^ (crc >>> 8);
  }
  return ~crc >>> 0;
}

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let i = 0; i < 256; i += 1) {
    let c = i;
    for (let k = 0; k < 8; k += 1) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[i] = c >>> 0;
  }
  return table;
})();

function createIcon(size) {
  const width = size;
  const height = size;
  const pixels = Buffer.alloc(width * height * 4);

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const idx = (y * width + x) * 4;
      const color = getPixelColor(x, y, width, height);
      pixels[idx + 0] = color[0];
      pixels[idx + 1] = color[1];
      pixels[idx + 2] = color[2];
      pixels[idx + 3] = color[3];
    }
  }

  return pixels;
}

function getPixelColor(x, y, width, height) {
  const nx = (x + 0.5) / width;
  const ny = (y + 0.5) / height;

  const coverage = sampleLetterCoverage(nx, ny, width, height);

  const bg = backgroundColor(nx, ny);

  if (coverage <= 0) {
    return [...bg, 255];
  }

  const letter = letterColor(nx, ny);
  const alpha = Math.max(0, Math.min(1, coverage));

  const r = Math.round(letter[0] * alpha + bg[0] * (1 - alpha));
  const g = Math.round(letter[1] * alpha + bg[1] * (1 - alpha));
  const b = Math.round(letter[2] * alpha + bg[2] * (1 - alpha));

  return [r, g, b, 255];
}

function backgroundColor(nx, ny) {
  const centerDx = nx - 0.5;
  const centerDy = ny - 0.5;
  const dist = Math.sqrt(centerDx * centerDx + centerDy * centerDy);

  const base = 8;
  const falloff = Math.min(1, dist * 1.8);

  const r = base + Math.round(40 * (1 - falloff));
  const g = base + Math.round(45 * (1 - falloff));
  const b = base + Math.round(50 * (1 - falloff));

  return [r, g, b];
}

function letterColor(nx, ny) {
  const top = [255, 227, 142];
  const mid = [237, 192, 80];
  const bottom = [193, 140, 36];

  const gradient = ny < 0.5 ? interpolate(top, mid, ny / 0.5) : interpolate(mid, bottom, (ny - 0.5) / 0.5);

  const highlight = Math.exp(-((nx - 0.5) ** 2) / 0.018 - ((ny - 0.32) ** 2) / 0.05) * 60;
  return clampColor([gradient[0] + highlight, gradient[1] + highlight * 0.7, gradient[2] + highlight * 0.2]);
}

function clampColor(color) {
  return color.map((value) => Math.max(0, Math.min(255, Math.round(value))));
}

function interpolate(a, b, t) {
  return [
    a[0] + (b[0] - a[0]) * t,
    a[1] + (b[1] - a[1]) * t,
    a[2] + (b[2] - a[2]) * t,
  ];
}

function sampleLetterCoverage(nx, ny, width, height) {
  const offsets = [0.211324865, 0.788675134];
  let total = 0;
  const invWidth = 1 / width;
  const invHeight = 1 / height;

  for (const ox of offsets) {
    for (const oy of offsets) {
      total += isInsideLetters(nx + (ox - 0.5) * invWidth, ny + (oy - 0.5) * invHeight) ? 1 : 0;
    }
  }

  return total / (offsets.length * offsets.length);
}

function isInsideLetters(nx, ny) {
  return LETTER_CENTERS.some((center) => isInsideLetter(nx, ny, center));
}

const LETTER_CENTERS = [0.35, 0.65];
const LETTER_WIDTH = 0.28;
const VERTICAL_THICKNESS = 0.18;
const DIAGONAL_BASE = 0.36;
const DIAGONAL_THICKNESS = 0.09;

function isInsideLetter(nx, ny, center) {
  const x0 = center - LETTER_WIDTH / 2;
  const lx = (nx - x0) / LETTER_WIDTH;

  if (lx < 0 || lx > 1 || ny < 0.18 || ny > 0.82) {
    return false;
  }

  const ly = (ny - 0.18) / 0.64;

  if (lx <= VERTICAL_THICKNESS || lx >= 1 - VERTICAL_THICKNESS) {
    return true;
  }

  const dx = Math.abs(lx - 0.5);
  const allowed = DIAGONAL_THICKNESS + (1 - ly) * DIAGONAL_BASE;
  return dx <= allowed;
}

function generate() {
  OUTPUTS.forEach(({ dir, name, size }) => {
    ensureDir(dir);
    const pixels = createIcon(size);
    const filePath = path.join(dir, name);
    writePng(filePath, size, size, pixels);
    console.log(`Generated ${filePath}`);
  });
}

generate();
