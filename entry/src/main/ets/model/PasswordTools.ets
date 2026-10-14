const UPPER: string = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const LOWER: string = 'abcdefghijkmnopqrstuvwxyz';
const DIGITS: string = '23456789';
const SYMBOLS: string = '!@#$%^&*()-_=+?';

export class PasswordOptions {
  length: number = 16;
  upper: boolean = true;
  lower: boolean = true;
  digits: boolean = true;
  symbols: boolean = true;
}

export function passwordGroups(options: PasswordOptions): string[] {
  const groups: string[] = [];
  if (options.upper) { groups.push(UPPER); }
  if (options.lower) { groups.push(LOWER); }
  if (options.digits) { groups.push(DIGITS); }
  if (options.symbols) { groups.push(SYMBOLS); }
  return groups;
}

export function validPasswordOptions(options: PasswordOptions): boolean {
  return Number.isInteger(options.length) && options.length >= 8 && options.length <= 64 &&
    passwordGroups(options).length > 0;
}

export function unbiasedIndex(bound: number, nextByte: () => number): number {
  if (!Number.isInteger(bound) || bound < 1 || bound > 256) { throw new Error('Invalid range'); }
  const limit: number = Math.floor(256 / bound) * bound;
  while (true) {
    const byte: number = nextByte();
    if (!Number.isInteger(byte) || byte < 0 || byte > 255) { throw new Error('Invalid random byte'); }
    if (byte < limit) { return byte % bound; }
  }
}

export function generatePassword(options: PasswordOptions, nextByte: () => number): string {
  if (!validPasswordOptions(options)) { throw new Error('Invalid password options'); }
  const groups: string[] = passwordGroups(options);
  const all: string = groups.join('');
  const result: string[] = [];
  groups.forEach((group: string) => result.push(group.charAt(unbiasedIndex(group.length, nextByte))));
  while (result.length < options.length) {
    result.push(all.charAt(unbiasedIndex(all.length, nextByte)));
  }
  for (let index: number = result.length - 1; index > 0; index--) {
    const swap: number = unbiasedIndex(index + 1, nextByte);
    const previous: string = result[index];
    result[index] = result[swap];
    result[swap] = previous;
  }
  return result.join('');
}
