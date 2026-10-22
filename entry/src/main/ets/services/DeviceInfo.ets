import { deviceInfo } from '@kit.BasicServicesKit';
import { bundleManager } from '@kit.AbilityKit';

/**
 * 设备与应用信息（系统能力层）：读取本机型号、系统与 API 版本，以及本应用的版本号。
 *
 * 全部是**只读**系统信息，不申请任何权限、不联网；只在设置页展示，不落盘、不上传。
 * 取不到的字段统一返回空串，由界面跳过该行（不要显示「未知」以外的臆测值）。
 */

export class InfoRow {
  readonly zh: string;
  readonly en: string;
  readonly value: string;

  constructor(zh: string, en: string, value: string) {
    this.zh = zh;
    this.en = en;
    this.value = value;
  }
}

/** 应用版本号（`versionName (versionCode)`）；取不到时返回空串。 */
export function appVersionText(): string {
  try {
    const info: bundleManager.BundleInfo =
      bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    return info.versionName + ' (' + info.versionCode + ')';
  } catch (err) {
    return '';
  }
}

/**
 * 只要 `versionName`（不带 `versionCode`）：应用内更新检查拿它与远端清单比较。
 *
 * 与 `appVersionText()` 分开是**刻意**的：`'1.0.0 (1000000)'` 直接喂进版本比较会在第二段就断掉
 * （`'1000000...'` 不是纯数字段），两个版本会永远「相等」。
 */
export function appVersionName(): string {
  try {
    const info: bundleManager.BundleInfo =
      bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    return info.versionName === undefined ? '' : info.versionName;
  } catch (err) {
    return '';
  }
}

/**
 * 设备信息行：型号、系统版本、API 版本、应用版本。
 * 数量与顺序稳定，界面按数组渲染即可；空值行由界面过滤。
 */
export function deviceInfoRows(): InfoRow[] {
  const rows: InfoRow[] = [];
  const model: string = deviceInfo.productModel ?? '';
  if (model.length > 0) { rows.push(new InfoRow('设备型号', 'Device model', model)); }
  const market: string = deviceInfo.marketName ?? '';
  if (market.length > 0 && market !== model) {
    rows.push(new InfoRow('产品名称', 'Product name', market));
  }
  const os: string = deviceInfo.osFullName ?? '';
  if (os.length > 0) { rows.push(new InfoRow('系统版本', 'System version', os)); }
  rows.push(new InfoRow('API 版本', 'API level', deviceInfo.sdkApiVersion.toString()));
  const version: string = appVersionText();
  if (version.length > 0) { rows.push(new InfoRow('应用版本', 'App version', version)); }
  const deviceType: string = deviceInfo.deviceType ?? '';
  if (deviceType.length > 0) { rows.push(new InfoRow('设备类型', 'Device type', deviceType)); }
  return rows;
}
