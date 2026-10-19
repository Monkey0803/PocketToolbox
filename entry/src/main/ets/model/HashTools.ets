/**
 * 消息摘要（纯逻辑，可参与单元测试）：MD5、SHA-1、SHA-256，输出大写十六进制。
 *
 * 全部按 UTF-8 字节在本机手写实现，不依赖 `cryptoFramework` 等系统能力，
 * 因此可被 `tests/run-unit-tests.mjs` 直接加载，并用 Node 的 `node:crypto` 交叉验证。
 * 这三者都是摘要而非加密，界面与文档不要把它说成「加密」（密码请用「密码生成」工具）。
 */
import { utf8Bytes, hexText } from './EncodingTools';

const MD5_SHIFTS: number[] = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
];

const MD5_CONSTANTS: number[] = [
  0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
  0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
  0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
  0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
  0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
  0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
  0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
  0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
];

const SHA256_CONSTANTS: number[] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

function rotl(value: number, bits: number): number {
  return ((value << bits) | (value >>> (32 - bits))) >>> 0;
}

function bytesOf(value: string | number[]): number[] {
  return typeof value === 'string' ? utf8Bytes(value) : value;
}

/** 填充后的字节（big-endian，SHA-1/SHA-256 用）。 */
function padBigEndian(bytes: number[]): number[] {
  const padded: number[] = bytes.slice();
  padded.push(0x80);
  while (padded.length % 64 !== 56) { padded.push(0); }
  const bitLength: number = bytes.length * 8;
  const high: number = Math.floor(bitLength / 4294967296);
  const low: number = bitLength % 4294967296;
  padded.push((high >>> 24) & 0xFF, (high >>> 16) & 0xFF, (high >>> 8) & 0xFF, high & 0xFF);
  padded.push((low >>> 24) & 0xFF, (low >>> 16) & 0xFF, (low >>> 8) & 0xFF, low & 0xFF);
  return padded;
}

/** 填充后的字节（little-endian 长度字段，MD5 用）。 */
function padLittleEndian(bytes: number[]): number[] {
  const padded: number[] = bytes.slice();
  padded.push(0x80);
  while (padded.length % 64 !== 56) { padded.push(0); }
  const bitLength: number = bytes.length * 8;
  const low: number = bitLength % 4294967296;
  const high: number = Math.floor(bitLength / 4294967296);
  padded.push(low & 0xFF, (low >>> 8) & 0xFF, (low >>> 16) & 0xFF, (low >>> 24) & 0xFF);
  padded.push(high & 0xFF, (high >>> 8) & 0xFF, (high >>> 16) & 0xFF, (high >>> 24) & 0xFF);
  return padded;
}

function wordAt(bytes: number[], offset: number, littleEndian: boolean): number {
  if (littleEndian) {
    return (bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24)) >>> 0;
  }
  return ((bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) |
    bytes[offset + 3]) >>> 0;
}

function wordsOf(hex: string): number[] {
  const words: number[] = [];
  for (let index: number = 0; index < hex.length; index += 8) {
    words.push(parseInt(hex.substring(index, index + 8), 16) >>> 0);
  }
  return words;
}

function toString32(words: number[], littleEndian: boolean): string {
  const bytes: number[] = [];
  words.forEach((word: number) => {
    if (littleEndian) {
      bytes.push(word & 0xFF, (word >>> 8) & 0xFF, (word >>> 16) & 0xFF, (word >>> 24) & 0xFF);
    } else {
      bytes.push((word >>> 24) & 0xFF, (word >>> 16) & 0xFF, (word >>> 8) & 0xFF, word & 0xFF);
    }
  });
  return hexText(bytes);
}

export function md5(value: string | number[]): string {
  const padded: number[] = padLittleEndian(bytesOf(value));
  const state: number[] = wordsOf('67452301efcdab8998badcfe10325476');
  for (let chunk: number = 0; chunk < padded.length; chunk += 64) {
    const words: number[] = [];
    for (let index: number = 0; index < 16; index++) {
      words.push(wordAt(padded, chunk + index * 4, true));
    }
    let a: number = state[0];
    let b: number = state[1];
    let c: number = state[2];
    let d: number = state[3];
    for (let round: number = 0; round < 64; round++) {
      let mixed: number = 0;
      let wordIndex: number = 0;
      if (round < 16) {
        mixed = ((b & c) | (~b & d)) >>> 0;
        wordIndex = round;
      } else if (round < 32) {
        mixed = ((d & b) | (~d & c)) >>> 0;
        wordIndex = (5 * round + 1) % 16;
      } else if (round < 48) {
        mixed = (b ^ c ^ d) >>> 0;
        wordIndex = (3 * round + 5) % 16;
      } else {
        mixed = (c ^ (b | (~d))) >>> 0;
        wordIndex = (7 * round) % 16;
      }
      const temp: number = d;
      d = c;
      c = b;
      const sum: number = (a + mixed + MD5_CONSTANTS[round] + words[wordIndex]) >>> 0;
      b = (b + rotl(sum, MD5_SHIFTS[round])) >>> 0;
      a = temp;
    }
    state[0] = (state[0] + a) >>> 0;
    state[1] = (state[1] + b) >>> 0;
    state[2] = (state[2] + c) >>> 0;
    state[3] = (state[3] + d) >>> 0;
  }
  return toString32(state, true);
}

export function sha1(value: string | number[]): string {
  const padded: number[] = padBigEndian(bytesOf(value));
  const state: number[] = wordsOf('67452301efcdab8998badcfe10325476c3d2e1f0');
  for (let chunk: number = 0; chunk < padded.length; chunk += 64) {
    const words: number[] = [];
    for (let index: number = 0; index < 16; index++) {
      words.push(wordAt(padded, chunk + index * 4, false));
    }
    for (let index: number = 16; index < 80; index++) {
      words.push(rotl(words[index - 3] ^ words[index - 8] ^ words[index - 14] ^ words[index - 16], 1));
    }
    let a: number = state[0];
    let b: number = state[1];
    let c: number = state[2];
    let d: number = state[3];
    let e: number = state[4];
    for (let round: number = 0; round < 80; round++) {
      let mixed: number = 0;
      let constant: number = 0;
      if (round < 20) {
        mixed = ((b & c) | (~b & d)) >>> 0;
        constant = 0x5a827999;
      } else if (round < 40) {
        mixed = (b ^ c ^ d) >>> 0;
        constant = 0x6ed9eba1;
      } else if (round < 60) {
        mixed = ((b & c) | (b & d) | (c & d)) >>> 0;
        constant = 0x8f1bbcdc;
      } else {
        mixed = (b ^ c ^ d) >>> 0;
        constant = 0xca62c1d6;
      }
      const temp: number = (rotl(a, 5) + mixed + e + constant + words[round]) >>> 0;
      e = d;
      d = c;
      c = rotl(b, 30);
      b = a;
      a = temp;
    }
    state[0] = (state[0] + a) >>> 0;
    state[1] = (state[1] + b) >>> 0;
    state[2] = (state[2] + c) >>> 0;
    state[3] = (state[3] + d) >>> 0;
    state[4] = (state[4] + e) >>> 0;
  }
  return toString32(state, false);
}

export function sha256(value: string | number[]): string {
  const padded: number[] = padBigEndian(bytesOf(value));
  const state: number[] = wordsOf('6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19');
  const mask: number = 0xFFFFFFFF;
  for (let chunk: number = 0; chunk < padded.length; chunk += 64) {
    const words: number[] = [];
    for (let index: number = 0; index < 16; index++) {
      words.push(wordAt(padded, chunk + index * 4, false));
    }
    for (let index: number = 16; index < 64; index++) {
      const s0: number = (rotl(words[index - 15], 25) ^ rotl(words[index - 15], 14) ^
        (words[index - 15] >>> 3)) >>> 0;
      const s1: number = (rotl(words[index - 2], 15) ^ rotl(words[index - 2], 13) ^
        (words[index - 2] >>> 10)) >>> 0;
      words.push((words[index - 16] + s0 + words[index - 7] + s1) & mask);
    }
    let a: number = state[0];
    let b: number = state[1];
    let c: number = state[2];
    let d: number = state[3];
    let e: number = state[4];
    let f: number = state[5];
    let g: number = state[6];
    let h: number = state[7];
    for (let round: number = 0; round < 64; round++) {
      const bigS1: number = (rotl(e, 26) ^ rotl(e, 21) ^ rotl(e, 7)) >>> 0;
      const choose: number = ((e & f) ^ (~e & g)) >>> 0;
      const temp1: number = (h + bigS1 + choose + SHA256_CONSTANTS[round] + words[round]) & mask;
      const bigS0: number = (rotl(a, 30) ^ rotl(a, 19) ^ rotl(a, 10)) >>> 0;
      const majority: number = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
      const temp2: number = (bigS0 + majority) & mask;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & mask;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & mask;
    }
    state[0] = (state[0] + a) & mask;
    state[1] = (state[1] + b) & mask;
    state[2] = (state[2] + c) & mask;
    state[3] = (state[3] + d) & mask;
    state[4] = (state[4] + e) & mask;
    state[5] = (state[5] + f) & mask;
    state[6] = (state[6] + g) & mask;
    state[7] = (state[7] + h) & mask;
  }
  return toString32(state, false);
}
