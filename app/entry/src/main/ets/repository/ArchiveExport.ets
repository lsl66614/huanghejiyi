// repository/ArchiveExport.ets —— 把导出的文本交给系统文件选择器落盘
//
// 放在 repository 层而不是页面里：这一段碰的是系统 API（picker / fileIo），
// 页面只该决定「导什么、导成什么格式」。落盘失败的原因要能原样回给用户，
// 所以这里不吞异常，只把它翻成一句人话。
//
// 为什么不用应用沙箱目录 + 分享：用户要的是「我能拿到这个文件」。
// 沙箱里的文件在卸载应用时一起消失，且真机上找起来费劲；系统保存框
// 让用户自己选位置（下载目录、网盘、U 盘），这才算导出。
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

const DOMAIN = 0x0001;
const TAG = 'ArchiveExport';

// 读取上限（字节）：档案只含用户文本，正常几十 KB。超过它就不是本应用的
// 导出文件——读前 2MB 截断即可让解析器给出 schema 报错，不必整份读入。
const IMPORT_READ_CAP = 2 * 1024 * 1024;

export class SaveResult {
  ok: boolean = false;
  cancelled: boolean = false;
  message: string = '';
}

function messageOf(e: Object): string {
  const err = e as Error;
  // 系统抛的常常是 BusinessError：它有 message，但类型上是两套对象，
  // 这里只认「有没有一句能读的话」，认不出就退回原文。
  if (typeof err.message === 'string' && err.message !== '') {
    return err.message;
  }
  return JSON.stringify(e);
}

export async function saveTextFile(context: common.UIAbilityContext, fileName: string,
  suffix: string, content: string): Promise<SaveResult> {
  const res = new SaveResult();
  let uris: string[] = [];
  try {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    options.fileSuffixChoices = [suffix];
    const viewPicker = new picker.DocumentViewPicker(context);
    uris = await viewPicker.save(options);
  } catch (e) {
    // 取消在部分版本上会以异常形式返回，不能一律当成故障。
    const msg = messageOf(e);
    if (msg.indexOf('cancel') >= 0 || msg.indexOf('取消') >= 0) {
      res.cancelled = true;
      return res;
    }
    res.message = `打开保存对话框失败：${msg}`;
    return res;
  }

  if (uris === undefined || uris.length === 0 || uris[0] === '') {
    res.cancelled = true;
    return res;
  }

  const uri: string = uris[0];
  let file: fs.File | null = null;
  try {
    file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, content);
    res.ok = true;
    res.message = '已导出。';
  } catch (e) {
    res.message = `写入文件失败：${messageOf(e)}`;
  } finally {
    // 关闭失败不该覆盖「已写入」这个结论：文件已经在用户选的位置上了。
    if (file !== null) {
      try {
        fs.closeSync(file);
      } catch (_e) {
        hilog.error(DOMAIN, TAG, 'close failed');
      }
    }
  }
  return res;
}

// 导出落盘的逆操作：让用户从系统文件选择框里挑一份档案 JSON 读回来。
// 与 saveTextFile 对称地放在 repository 层——同样只碰系统 API，错误翻成人话。
export class ReadResult {
  ok: boolean = false;
  cancelled: boolean = false;
  message: string = '';
  content: string = '';
}

// 上限在调用方（ExportPage）用 IMPORT_MAX_BYTES 判断；这里只管读。
export async function readTextFile(context: common.UIAbilityContext): Promise<ReadResult> {
  const res = new ReadResult();
  let uris: string[] = [];
  try {
    const options = new picker.DocumentSelectOptions();
    // SDK 字段名是 maxSelectNumber（不是 maxFileNumber——后者只存在于
    // 旧版 PhotoSelectOptions），写错会编译报 "Property does not exist"。
    options.maxSelectNumber = 1;
    const viewPicker = new picker.DocumentViewPicker(context);
    uris = await viewPicker.select(options);
  } catch (e) {
    // 与保存框同口径：取消可能以异常形式返回，不当成故障
    const msg = messageOf(e);
    if (msg.indexOf('cancel') >= 0 || msg.indexOf('取消') >= 0) {
      res.cancelled = true;
      return res;
    }
    res.message = `打开文件选择框失败：${msg}`;
    return res;
  }

  if (uris === undefined || uris.length === 0 || uris[0] === '') {
    res.cancelled = true;
    return res;
  }

  const uri: string = uris[0];
  let file: fs.File | null = null;
  try {
    file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const buf = new ArrayBuffer(IMPORT_READ_CAP);
    const read = fs.readSync(file.fd, buf);
    // 只读前 IMPORT_READ_CAP 字节；更大的文件不是本应用的档案
    res.content = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf, 0, read));
    res.ok = true;
  } catch (e) {
    res.message = `读取文件失败：${messageOf(e)}`;
  } finally {
    if (file !== null) {
      try {
        fs.closeSync(file);
      } catch (_e) {
        hilog.error(DOMAIN, TAG, 'close failed');
      }
    }
  }
  return res;
}
