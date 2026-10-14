export type BarcodeKind = 'code128' | 'ean13' | 'ean8';

function eanCheckDigit(digits: string): string {
  let sum: number = 0;
  for (let index: number = 0; index < digits.length; index++) {
    let digit: number = Number(digits[index]);
    sum += digit * (index % 2 === digits.length % 2 ? 1 : 3);
  }
  return ((10 - sum % 10) % 10).toString();
}

// Scan Kit expects EAN data without its check digit and adds that digit to the image.
export function barcodeInput(kind: BarcodeKind, raw: string): string | undefined {
  if (kind === 'code128') {
    return raw.length > 0 && raw.length <= 80 && /^[\x20-\x7E]+$/.test(raw) ? raw : undefined;
  }
  let value: string = raw.trim();
  let dataLength: number = kind === 'ean13' ? 12 : 7;
  if (!/^\d+$/.test(value) || (value.length !== dataLength && value.length !== dataLength + 1)) {
    return undefined;
  }
  if (kind === 'ean13' && value[0] === '0') { return undefined; }
  let data: string = value.slice(0, dataLength);
  if (value.length === dataLength + 1 && value[dataLength] !== eanCheckDigit(data)) { return undefined; }
  return data;
}

export function barcodeDisplayValue(kind: BarcodeKind, data: string): string {
  return kind === 'code128' ? data : data + eanCheckDigit(data);
}
