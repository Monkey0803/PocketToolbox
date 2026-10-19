/**
 * 二维码内容模板（纯逻辑，可参与单元测试）。
 *
 * 生成「载荷文本」的函数都是 `输入 -> QrPayload`，不涉及 `$r`、`@kit.*` 与 UI 装饰器；
 * 界面用同一份模板构建二维码载荷，扫描/历史/保存/分享链路完全不受影响。
 *
 * 模板遵循通行约定：
 * - WiFi：`WIFI:T:WPA;S:<ssid>;P:<password>;H:false;;`（`;`、`,`、`:`、`"`、`\` 需转义）
 * - 名片：vCard 3.0
 * - 电话：`tel:`；短信：`SMSTO:<号码>:<内容>`；邮件：`mailto:` 带 `subject`/`body`
 * - 位置：`geo:<纬度>,<经度>`
 */

export class QrPayload {
  ok: boolean = false;
  // 失败原因码：'empty' | 'url' | 'email' | 'phone' | 'range' | 'wifi'；界面用 errorText 转成双语提示。
  error: string = 'empty';
  text: string = '';
}

/** 二维码内容类型登记表：界面下拉框直接用它，新增类型只需加登记项与构建函数。 */
export class QrKindEntry {
  readonly id: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

export const QR_KINDS: QrKindEntry[] = [
  new QrKindEntry('text', '文本', 'Text'),
  new QrKindEntry('url', '网址', 'URL'),
  new QrKindEntry('wifi', 'WiFi', 'WiFi'),
  new QrKindEntry('card', '名片', 'Contact'),
  new QrKindEntry('tel', '电话', 'Phone'),
  new QrKindEntry('sms', '短信', 'SMS'),
  new QrKindEntry('mail', '邮件', 'Email'),
  new QrKindEntry('geo', '位置', 'Location')
];

/** WiFi 加密方式登记表。 */
export class WifiSecurityEntry {
  readonly id: string;
  readonly zh: string;
  readonly en: string;

  constructor(id: string, zh: string, en: string) {
    this.id = id;
    this.zh = zh;
    this.en = en;
  }
}

export const WIFI_SECURITIES: WifiSecurityEntry[] = [
  new WifiSecurityEntry('WPA', 'WPA/WPA2', 'WPA/WPA2'),
  new WifiSecurityEntry('WEP', 'WEP', 'WEP'),
  new WifiSecurityEntry('nopass', '无密码', 'None')
];

function ok(text: string): QrPayload {
  const payload: QrPayload = new QrPayload();
  payload.ok = true;
  payload.error = '';
  payload.text = text;
  return payload;
}

function fail(error: string): QrPayload {
  const payload: QrPayload = new QrPayload();
  payload.ok = false;
  payload.error = error;
  payload.text = '';
  return payload;
}

function isEmail(value: string): boolean {
  return new RegExp('^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$').test(value.trim());
}

function isPhone(value: string): boolean {
  const trimmed: string = value.trim();
  if (!new RegExp('^[+0-9()\\- ]+$').test(trimmed)) { return false; }
  return trimmed.replace(new RegExp('[^0-9]', 'g'), '').length >= 4;
}

function isGeoNumber(value: string): boolean {
  const trimmed: string = value.trim();
  if (!new RegExp('^-?\\d+(\\.\\d+)?$').test(trimmed)) { return false; }
  return Number.isFinite(Number(trimmed));
}

/** WiFi 载荷转义：反斜杠、分号、逗号、冒号、双引号都要加反斜杠。 */
function escapeWifi(value: string): string {
  let result: string = '';
  Array.from(value).forEach((character: string) => {
    if (character === '\\' || character === ';' || character === ',' || character === ':' || character === '"') {
      result += '\\';
    }
    result += character;
  });
  return result;
}

/** vCard 字段转义：反斜杠、换行、分号、逗号。 */
function escapeVcard(value: string): string {
  const normalized: string = value.replace(new RegExp('\\r\\n', 'g'), '\n');
  let result: string = '';
  Array.from(normalized).forEach((character: string) => {
    if (character === '\\') { result += '\\\\'; }
    else if (character === '\n' || character === '\r') { result += '\\n'; }
    else if (character === ';' || character === ',') { result += '\\' + character; }
    else { result += character; }
  });
  return result;
}

export function errorText(code: string, english: boolean): string {
  if (code === 'url') {
    return english ? 'URL must start with http:// or https://' : '网址需以 http:// 或 https:// 开头';
  }
  if (code === 'email') {
    return english ? 'Enter a valid email address' : '请输入有效的邮箱地址';
  }
  if (code === 'phone') {
    return english ? 'Enter a valid phone number' : '请输入有效的电话号码';
  }
  if (code === 'range') {
    return english ? 'Latitude must be -90 to 90 and longitude -180 to 180' :
      '纬度需在 -90 至 90 之间，经度需在 -180 至 180 之间';
  }
  if (code === 'wifi') {
    return english ? 'Enter the WiFi name (SSID)' : '请输入 WiFi 名称（SSID）';
  }
  return english ? 'Fill in the required fields' : '请填写必填项';
}

export function textPayload(value: string): QrPayload {
  const trimmed: string = value.trim();
  return trimmed.length === 0 ? fail('empty') : ok(trimmed);
}

export function urlPayload(value: string): QrPayload {
  const trimmed: string = value.trim();
  if (trimmed.length === 0) { return fail('empty'); }
  if (!new RegExp('^https?://\\S+$').test(trimmed)) { return fail('url'); }
  return ok(trimmed);
}

export function wifiPayload(ssid: string, password: string, security: string, hidden: boolean): QrPayload {
  const name: string = ssid.trim();
  if (name.length === 0) { return fail('wifi'); }
  const mode: string = security === 'WEP' || security === 'nopass' ? security : 'WPA';
  // 无密码模式不写密码；其余模式密码可以为空（开放但声明了加密的网络确实存在），由用户自行判断。
  const secret: string = mode === 'nopass' ? '' : password;
  return ok('WIFI:T:' + mode + ';S:' + escapeWifi(name) + ';P:' + escapeWifi(secret) +
    ';H:' + (hidden ? 'true' : 'false') + ';;');
}

export function vcardPayload(name: string, phone: string, email: string, org: string, title: string): QrPayload {
  const fullName: string = name.trim();
  if (fullName.length === 0) { return fail('empty'); }
  const phoneText: string = phone.trim();
  if (phoneText.length > 0 && !isPhone(phoneText)) { return fail('phone'); }
  const emailText: string = email.trim();
  if (emailText.length > 0 && !isEmail(emailText)) { return fail('email'); }
  const lines: string[] = ['BEGIN:VCARD', 'VERSION:3.0',
    'N:' + escapeVcard(fullName), 'FN:' + escapeVcard(fullName)];
  if (org.trim().length > 0) { lines.push('ORG:' + escapeVcard(org)); }
  if (title.trim().length > 0) { lines.push('TITLE:' + escapeVcard(title)); }
  if (phoneText.length > 0) { lines.push('TEL;TYPE=CELL:' + escapeVcard(phoneText)); }
  if (emailText.length > 0) { lines.push('EMAIL:' + escapeVcard(emailText)); }
  lines.push('END:VCARD');
  return ok(lines.join('\n'));
}

export function telPayload(number: string): QrPayload {
  const trimmed: string = number.trim();
  if (trimmed.length === 0) { return fail('empty'); }
  if (!isPhone(trimmed)) { return fail('phone'); }
  return ok('tel:' + trimmed);
}

export function smsPayload(number: string, body: string): QrPayload {
  const trimmed: string = number.trim();
  if (trimmed.length === 0) { return fail('empty'); }
  if (!isPhone(trimmed)) { return fail('phone'); }
  return ok('SMSTO:' + trimmed + ':' + body.trim());
}

export function mailPayload(to: string, subject: string, body: string): QrPayload {
  const address: string = to.trim();
  if (address.length === 0) { return fail('empty'); }
  if (!isEmail(address)) { return fail('email'); }
  const parts: string[] = [];
  if (subject.trim().length > 0) { parts.push('subject=' + encodeURIComponent(subject.trim())); }
  if (body.trim().length > 0) { parts.push('body=' + encodeURIComponent(body.trim())); }
  return ok('mailto:' + address + (parts.length > 0 ? '?' + parts.join('&') : ''));
}

export function geoPayload(latitude: string, longitude: string): QrPayload {
  if (latitude.trim().length === 0 || longitude.trim().length === 0) { return fail('empty'); }
  if (!isGeoNumber(latitude) || !isGeoNumber(longitude)) { return fail('range'); }
  const lat: number = Number(latitude.trim());
  const lng: number = Number(longitude.trim());
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) { return fail('range'); }
  return ok('geo:' + lat + ',' + lng);
}
