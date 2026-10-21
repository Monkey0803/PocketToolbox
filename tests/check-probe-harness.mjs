// 验证 tests/probe.mjs 自身可用：装载三个模块并核对已知口径（含「注释提到 @kit」的 HistoryKinds）。
import { loadModel, createChecker } from './probe.mjs';

const { check, summary } = createChecker();

const TimerMath = await loadModel('TimerMath');
check('TimerMath 可装载且端点正确', TimerMath.timerDurationWithinLimits(1000) &&
  !TimerMath.timerDurationWithinLimits(999));

// 这一条正是共用装载器要解决的问题：HistoryKinds 只在注释里提到 `@kit.*`
const HistoryKinds = await loadModel('HistoryKinds');
check('HistoryKinds 可装载（注释里的 @kit 不应被当成依赖）',
  typeof HistoryKinds.normalizeHistoryItems === 'function');

// DataExport 依赖 HistoryKinds，装载器必须把依赖链一起铺好
const DataExport = await loadModel('DataExport');
const DataImport = await loadModel('DataImport');
const values = new Map([['k', '值"含引号\n换行']]);
const envelope = DataExport.buildBackupJson(values, 1750000000000);
const parsed = DataImport.parseBackupJson(envelope, ['k']);
check('DataExport → DataImport 往返保真', parsed.error === '' && parsed.values.get('k') === '值"含引号\n换行');

// 含 @kit 的模块必须被跳过（否则装载即失败）
let skippedOk = false;
try {
  await loadModel('LocalData');
} catch (_) {
  skippedOk = true;
}
check('含 @kit 的 LocalData 被跳过（装载会失败）', skippedOk);

// describeModel：类要列出**真实字段名**（这正是写探针时最容易猜错的地方），
// 而「返回对象的函数」不能被误标成 class。
const { describeModel } = await import('./probe.mjs');
const kinText = (await describeModel('KinshipMath')).split('\n');
check('describeModel 列出 KinOutcome 的真实字段',
  kinText.some((line) => line.startsWith('KinOutcome: class { error, token, result }')));
const loanText = (await describeModel('LoanMath')).split('\n');
check('describeModel 把 calculateLoan 标成 function（不是 class）',
  loanText.some((line) => line.startsWith('calculateLoan: function')));
check('describeModel 列出 LoanResult 的 totalPaymentCents',
  loanText.some((line) => line.indexOf('LoanResult: class') === 0 && line.indexOf('totalPaymentCents') > 0));

// describeModel 还要带上**紧邻的注释首行**（语义类错误的来源）：
// 既要能取到 `//` 行注释（本项目不少函数这样写），也不能把**别的符号**的注释错贴过来。
const { loadModel: load2 } = await import('./probe.mjs');
const dateText = (await describeModel('DateTools')).split('\n');
check('describeModel 带出 workingDaysBetween 的 includeFirst 语义',
  dateText.some((line) => line.startsWith('workingDaysBetween: function') && line.indexOf('includeFirst') > 0));
check('describeModel 带出 workingDaysBetweenWithHolidays 的口径注释',
  dateText.some((line) => line.startsWith('workingDaysBetweenWithHolidays: function') && line.indexOf('调休') > 0));
check('describeModel 不会把相邻符号的注释贴错（addWorkingDays 应拿到自己的注释）',
  dateText.some((line) => line.startsWith('addWorkingDays: function') && line.indexOf('工作日推算') > 0));
check('constants 也带上注释与取值',
  dateText.some((line) => line.startsWith('WORKING_DAYS_SHIFT_LIMIT: number') && line.indexOf('36500') > 0));
check('没有注释的导出不会凭空生成注释（不虚构）',
  dateText.every((line) => line.indexOf('区间过长时的双语提示') < 0 || line.startsWith('workingDaysSpanErrorText')));

// describeModel 还要给出**形参名**（类型被去掉了，但名字留在源码里）：第 31 轮我因为看不出
// `customCharset` 收的是 options 对象还是字符串而误用，加名字后一眼可辨。
const pwText = (await describeModel('PasswordTools')).split('\n');
check('describeModel 打印形参名（customCharset(options)）',
  pwText.some((line) => line.startsWith('customCharset: function(options)')));
check('describeModel 打印多形参名（generatePassword(options, nextByte)）',
  pwText.some((line) => line.startsWith('generatePassword: function(options, nextByte)')));
check('describeModel 打印无参函数（todayDate()）',
  (await describeModel('DateTools')).split('\n').some((line) => line.startsWith('todayDate: function()')));
void load2;

process.exit(summary() === 0 ? 0 : 1);
