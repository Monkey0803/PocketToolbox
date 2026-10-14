import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { PasswordOptions, generatePassword } from '../model/PasswordTools';

export async function createPassword(options: PasswordOptions): Promise<string> {
  const random: cryptoFramework.Random = cryptoFramework.createRandom();
  let bytes: Uint8Array = (await random.generateRandom(256)).data;
  let position: number = 0;
  return generatePassword(options, (): number => {
    if (position >= bytes.length) {
      bytes = random.generateRandomSync(256).data;
      position = 0;
    }
    return bytes[position++];
  });
}
