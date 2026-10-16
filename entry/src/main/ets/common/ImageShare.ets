import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'ImageShare';

/** 复制到剪贴板 / 保存成图片文件，选区页和贴图页共用。 */
export class ImageShare {
  static async copyToClipboard(pixelMap: image.PixelMap): Promise<void> {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, pixelMap);
    await pasteboard.getSystemPasteboard().setData(data);
    hilog.info(DOMAIN, TAG, '%{public}s', 'copied to clipboard');
  }

  /**
   * 弹系统保存对话框，把图片写到用户选定的位置。
   * 返回落盘 URI；用户取消时返回空串。
   */
  static async saveAs(context: common.UIAbilityContext, pixelMap: image.PixelMap,
    suggestedName: string): Promise<string> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [suggestedName];
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris: string[] = await documentPicker.save(options);
    if (uris === undefined || uris.length === 0 || uris[0].length === 0) {
      hilog.info(DOMAIN, TAG, '%{public}s', 'save cancelled');
      return '';
    }
    const packer = image.createImagePacker();
    let file: fs.File | undefined = undefined;
    try {
      const buffer: ArrayBuffer = await packer.packing(pixelMap, { format: 'image/png', quality: 100 });
      file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, buffer);
      hilog.info(DOMAIN, TAG, 'saved to %{public}s', uris[0]);
      return uris[0];
    } finally {
      packer.release();
      if (file !== undefined) {
        fs.closeSync(file);
      }
    }
  }

  /** 形如 20261016-122530，作为保存对话框里的建议文件名。 */
  static suggestedName(): string {
    const now = new Date();
    const pad = (v: number): string => v < 10 ? `0${v}` : `${v}`;
    return `snipaste_${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}_` +
      `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}.png`;
  }
}
