import { common, Want } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { PinStore } from './PinStore';

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
    filesDir: string, width: number, height: number): Promise<string> {
    const path: string = await PinStore.saveAsPng(pixelMap, filesDir);
    const want: Want = {
      bundleName: context.abilityInfo.bundleName,
      abilityName: 'PasteAbility',
      parameters: {
        imagePath: path,
        imageWidth: width,
        imageHeight: height
      }
    };
    await context.startAbility(want);
    return path;
  }
}
