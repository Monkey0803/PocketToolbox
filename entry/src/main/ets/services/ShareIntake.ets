import { Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ShareRecord } from '../model/ShareIntent';

/**
 * 分享接收（服务层）：把系统分享面板交给分享扩展的 `want` 读成纯逻辑记录。
 *
 * 系统侧的形状由 Share Kit 提供：`systemShare.getSharedData(want)` → `SharedData.getRecords()`，
 * 每条记录有 `utd`（数据类型）与 `content`（文本/链接内容）或 `uri`（文件）。
 * 本应用只处理**文本**，因此只镜像 `utd` 与 `content`，文件记录（`uri`）自然落成空内容，
 * 由 `model/ShareIntent.pickSharedText()` 统一挑拣（挑不到就返回空串，页面给「没有文字内容」的说明）。
 *
 * 失败只记日志并返回空数组：分享扩展是别人拉起来的界面，不能因为读数据失败就崩溃或白屏，
 * 页面会显示「没有可用的分享内容」。
 */

const DOMAIN: number = 0x0000;
const TAG: string = 'ShareIntake';

/** 读取分享内容；没有可读记录时返回空数组（不抛异常）。 */
export async function readSharedRecords(want: Want): Promise<ShareRecord[]> {
  try {
    const shared: systemShare.SharedData = await systemShare.getSharedData(want);
    const records: systemShare.SharedRecord[] = shared.getRecords();
    const result: ShareRecord[] = [];
    records.forEach((record: systemShare.SharedRecord) => {
      const utd: string = record.utd === undefined ? '' : record.utd;
      const content: string = record.content === undefined ? '' : record.content;
      result.push(new ShareRecord(utd, content));
    });
    return result;
  } catch (error) {
    hilog.warn(DOMAIN, TAG, 'getSharedData failed: %{public}s', JSON.stringify(error));
    return [];
  }
}
