import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 媒体 URI → `image.ImageSource` 的**唯一入口**。
 *
 * ## 为什么必须有这一层（2026-10-22 真机实测缺陷）
 *
 * 系统相册选择器（`photoAccessHelper.PhotoViewPicker`）返回的 `photoUris` **不能直接喂给
 * `image.createImageSource(uri)`**：在 PLR-AL00 / HarmonyOS 7.0.0.109 上，选择器会正常返回 URI，
 * 但紧接着解码必然失败——用户看到的现象是「二维码选了图没反应」「证件照选不了图」，而日志只有
 * `pickQrLogo failed: {}`（`BusinessError` 的可枚举属性是空的，连错误码都看不到）。
 *
 * 正确姿势是**先 `fs.openSync(uri, READ_ONLY)` 拿到 fd，再 `image.createImageSource(fd)`**——
 * 文档扫描的 OCR 路径（`services/OcrTools.ets` 的 `decodePage()`）一直就是这么做的，所以它没这个问题。
 *
 * ## 口径
 *
 * - **fd 与 source 同生共死**：`ImageSource` 是惰性读取，fd 必须在它整个生命周期内保持打开，
 *   因此把两者包在一个对象里，`release()` 时先 `source.release()` 再 `closeSync(fd)`。
 * - **保留 URI 兜底**：fd 打不开时（个别实现/非媒体 URI）回退到直接用 URI 构造，失败才抛。
 * - **日志只记错误码与阶段**：不记 URI（它是用户相册里的路径），与其它服务同一取舍。
 */

const DOMAIN: number = 0x0000;
const TAG: string = 'MediaSource';

function logFailure(phase: string, error: Object): void {
  const failure: BusinessError = error as BusinessError;
  const code: number = failure === undefined || failure.code === undefined ? -1 : failure.code;
  const message: string = failure === undefined || failure.message === undefined ? '' : failure.message;
  hilog.error(DOMAIN, TAG, '%{public}s failed: code=%{public}d message=%{public}s', phase, code, message);
}

/** 打开后的媒体源：调用方用完必须 `release()`（页面离开、重新选图、渲染结束都要释放）。 */
export class MediaSource {
  readonly source: image.ImageSource;
  /**
   * 源文件字节数；拿不到（fd 打不开、stat 失败）时 `-1`。
   *
   * 图片工具的「压缩前体积」用它——**不拿不到就显示占位，不显示 0**（0 会被读成「文件是空的」）。
   */
  readonly byteSize: number;
  private file: fs.File | undefined = undefined;

  constructor(source: image.ImageSource, file: fs.File | undefined, byteSize: number = -1) {
    this.source = source;
    this.file = file;
    this.byteSize = byteSize;
  }

  /** 释放 `ImageSource` 与底层 fd（**顺序不能反**：先释放 source，它可能还在用 fd）。 */
  async release(): Promise<void> {
    try {
      await this.source.release();
    } catch (_) {
      // 已经释放过、或底层已失效时忽略。
    }
    const opened: fs.File | undefined = this.file;
    this.file = undefined;
    if (opened !== undefined) {
      try {
        fs.closeSync(opened);
      } catch (_) {
        // 关不掉不影响调用方（进程退出会回收）。
      }
    }
  }
}

/**
 * 打开一个媒体 URI（相册选择器返回的 `file://media/...`、扫描控件的临时 URI 都可以）。
 *
 * 失败时**抛出**原始错误（码在 `code` 上），由调用方决定文案；本函数只保证「能打开的都用 fd 打开」。
 */
export async function openMediaSource(uri: string): Promise<MediaSource> {
  const target: string = typeof uri === 'string' ? uri.trim() : '';
  if (target.length === 0) {
    throw new Error('empty media uri');
  }
  let file: fs.File | undefined = undefined;
  try {
    file = fs.openSync(target, fs.OpenMode.READ_ONLY);
    return new MediaSource(image.createImageSource(file.fd), file, readableSize(file.fd));
  } catch (error) {
    // fd 打不开才回退 URI 构造；打不开时 file 可能已创建，先关掉避免泄漏。
    if (file !== undefined) {
      try { fs.closeSync(file); } catch (_) {}
      file = undefined;
    }
    try {
      return new MediaSource(image.createImageSource(target), undefined, -1);
    } catch (fallbackError) {
      // 两种都失败：记一次码，把**回退**的错误抛出去（它才是调用方真正遇到的那次失败）。
      logFailure('openMediaSource', fallbackError as Object);
      throw fallbackError as Error;
    }
  }
}

/** fd 对应的文件字节数；stat 失败返回 `-1`（调用方据此不显示体积，而不是显示 0）。 */
function readableSize(fd: number): number {
  try {
    const info: fs.Stat = fs.statSync(fd);
    return Number.isFinite(info.size) && info.size >= 0 ? info.size : -1;
  } catch (_) {
    return -1;
  }
}
