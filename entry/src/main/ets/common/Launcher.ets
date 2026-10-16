import { common, Want } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { PinStore } from './PinStore';
import { PinRegistry } from './PinRegistry';

/** 打开其它 Ability（选区窗口 / 贴图窗口）的统一入口。 */
export class Launcher {
  /** 打开全屏选区窗口，对已经冻结的整屏截图做框选。 */
  static async openSelection(context: common.UIAbilityContext, imagePath: string,
    width: number, height: number): Promise<void> {
    const want: Want = {
      bundleName: context.abilityInfo.bundleName,
      abilityName: 'SelectionAbility',
      parameters: {
        imagePath: imagePath,
        imageWidth: width,
        imageHeight: height
      }
    };
    await context.startAbility(want);
  }

  /** 把 PixelMap 落盘并作为贴图窗口显示，返回落盘路径。 */
  static async pinPixelMap(context: common.UIAbilityContext, pixelMap: image.PixelMap,
    filesDir: string, width: number, height: number, note: string = ''): Promise<string> {
    const isDiff: boolean = note.length > 0;
    const path: string = await PinStore.saveAsPng(pixelMap, filesDir, isDiff ? 'diff' : 'pin');
    if (!isDiff) {
      // 只登记真正的贴图：差异图不是"上一张图片"的比较基准
      PinRegistry.add(path);
    }
    await Launcher.showImage(context, path, width, height, note);
    return path;
  }

  /** 打开一个贴图/差异窗口显示已经落盘的图片。 */
  static async showImage(context: common.UIAbilityContext, imagePath: string,
    width: number, height: number, note: string = ''): Promise<void> {
    const want: Want = {
      bundleName: context.abilityInfo.bundleName,
      abilityName: 'PasteAbility',
      parameters: {
        imagePath: imagePath,
        imageWidth: width,
        imageHeight: height,
        note: note
      }
    };
    await context.startAbility(want);
  }
}
