import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import {
  PasswordOptions, generatePassword, generatePin, validBatchCount, validPasswordOptions
} from '../model/PasswordTools';

// 安全随机字节的取法只此一份（与原实现一致：首次异步取一整块，随后按需同步补满）；
// 模型层的生成函数只通过 `nextByte()` 拿到 0–255 的整数。
async function byteSource(random: cryptoFramework.Random): Promise<() => number> {
  let bytes: Uint8Array = (await random.generateRandom(256)).data;
  let position: number = 0;
  return (): number => {
    if (position >= bytes.length) {
      bytes = random.generateRandomSync(256).data;
      position = 0;
    }
    return bytes[position++];
  };
}

/**
 * 生成完整密码。
 *
 * 返回空串表示「无法生成」（选项非法或系统随机源给出异常字节）——模型层不再抛异常，页面据此给
 * 明确提示，而不是让异常冒到页面变成一句笼统的「安全随机数不可用」（2026-10-20 审计 §3.23①）。
 */
export async function createPassword(options: PasswordOptions): Promise<string> {
  const random: cryptoFramework.Random = cryptoFramework.createRandom();
  const nextByte: () => number = await byteSource(random);
  const value: string | undefined = generatePassword(options, nextByte);
  return value === undefined ? '' : value;
}

/** 生成 PIN；无法生成时返回空串（位数不在 `PIN_LENGTHS` 内或随机源异常）。 */
export async function createPin(length: number): Promise<string> {
  const random: cryptoFramework.Random = cryptoFramework.createRandom();
  const nextByte: () => number = await byteSource(random);
  const value: string | undefined = generatePin(length, nextByte);
  return value === undefined ? '' : value;
}

/**
 * 一次生成多条完整密码（2026-10-22 新增）。
 *
 * 口径：
 * - 只建**一个**安全随机源，循环调用同一个 `generatePassword()`——每条仍逐条独立、无偏，且不会为 10 条
 *   密码建 10 个 `Random`；
 * - 返回 `string[]`：`[]` 表示**整批失败**（数量不在 `PASSWORD_BATCH_COUNTS`/选项非法/任意一条返回
 *   `undefined`），成功则必定是 `count` 条非空值——页面按 `[]` 给一次失败提示，不出现「一半成功」；
 * - 与单条同一口径：**不抛异常**，「无法生成」只以返回值表达。
 */
export async function createPasswords(options: PasswordOptions, count: number): Promise<string[]> {
  if (!validBatchCount(count) || !validPasswordOptions(options)) { return []; }
  const random: cryptoFramework.Random = cryptoFramework.createRandom();
  const nextByte: () => number = await byteSource(random);
  const values: string[] = [];
  for (let index: number = 0; index < count; index++) {
    const value: string | undefined = generatePassword(options, nextByte);
    if (value === undefined) { return []; }
    values.push(value);
  }
  return values;
}

/** 一次生成多条 PIN；`[]` 的含义与 `createPasswords()` 相同（位数非法也返回 `[]`）。 */
export async function createPins(length: number, count: number): Promise<string[]> {
  if (!validBatchCount(count)) { return []; }
  const random: cryptoFramework.Random = cryptoFramework.createRandom();
  const nextByte: () => number = await byteSource(random);
  const values: string[] = [];
  for (let index: number = 0; index < count; index++) {
    const value: string | undefined = generatePin(length, nextByte);
    if (value === undefined) { return []; }
    values.push(value);
  }
  return values;
}
