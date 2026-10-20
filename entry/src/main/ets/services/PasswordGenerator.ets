import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { PasswordOptions, generatePassword, generatePin } from '../model/PasswordTools';

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

export async function createPassword(options: PasswordOptions): Promise<string> {
  const random: cryptoFramework.Random = cryptoFramework.createRandom();
  const nextByte: () => number = await byteSource(random);
  return generatePassword(options, nextByte);
}

export async function createPin(length: number): Promise<string> {
  const random: cryptoFramework.Random = cryptoFramework.createRandom();
  const nextByte: () => number = await byteSource(random);
  return generatePin(length, nextByte);
}
