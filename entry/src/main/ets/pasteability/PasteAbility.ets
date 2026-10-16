import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PinPayload } from '../common/PinPayload';

const DOMAIN = 0x0000;
const TAG = 'PasteAbility';

/** 贴图窗口初始落点（px） */
const PIN_ORIGIN_X: number = 160;
const PIN_ORIGIN_Y: number = 160;

/**
 * 贴图窗口。声明为 multiton，因此每张贴图都是一个独立窗口，互不覆盖。
 * 窗口无装饰、无阴影、背景透明，尺寸与截图区域 1:1（不做缩放）。
 */
export default class PasteAbility extends UIAbility {
  private imagePath: string = '';
  private imageWidth: number = 0;
  private imageHeight: number = 0;
  private note: string = '';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const params = want.parameters;
    if (params !== undefined) {
      this.imagePath = params.imagePath as string;
      this.imageWidth = params.imageWidth as number;
      this.imageHeight = params.imageHeight as number;
      this.note = (params.note as string) ?? '';
    }
    hilog.info(DOMAIN, TAG, 'onCreate size=%{public}dx%{public}d pathLen=%{public}d noteLen=%{public}d',
      this.imageWidth, this.imageHeight, this.imagePath.length, this.note.length);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const mainWindow = windowStage.getMainWindowSync();
    const windowId: number = mainWindow.getWindowProperties().id;
    PinPayload.save(windowId, this.imagePath);
    PinPayload.saveNote(windowId, this.note);
    windowStage.loadContent('pages/PastePage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      this.setupPinWindow(windowStage);
    });
  }

  /** 去装饰、去阴影、置顶，并按图片像素尺寸调整窗口。 */
  private setupPinWindow(windowStage: window.WindowStage): void {
    const win = windowStage.getMainWindowSync();
    try {
      win.setWindowDecorVisible(false);
      win.setWindowTitleButtonVisible(false, false, false);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'hide decor failed: %{public}d %{public}s', e.code, e.message);
    }
    win.setWindowShadowEnabled(false).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'setWindowShadowEnabled failed: %{public}d %{public}s', err.code, err.message);
    });
    win.setWindowTopmost(true).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'setWindowTopmost failed: %{public}d %{public}s', err.code, err.message);
    });
    this.fitWindowToImage(win);
  }

  /**
   * 窗口尺寸 = 截图区域的像素尺寸（1:1，不缩放），超过屏幕时按屏幕裁到上限。
   *
   * 已知限制：窗口四角会被系统裁成约 40px 圆角，而 setWindowCornerRadius 对主窗口
   * 直接报 1300004「This is not sub window or float window」（只有子窗口/悬浮窗能改）。
   * 试过"窗口四周留透明边距把圆角藏进边距"的绕法：主窗口画布改不成透明
   * （实测 setWindowBackgroundColor('#01000000') 前后、resize 前后，边距恒为
   * 不透明浅灰 (228,227,232)），所以该绕法会露出一圈灰框，已放弃。
   * 想真正去掉圆角只能换 TYPE_FLOAT 悬浮窗（需 SYSTEM_FLOAT_WINDOW 受限权限）。
   */
  private fitWindowToImage(win: window.Window): void {
    if (this.imageWidth <= 0 || this.imageHeight <= 0) {
      return;
    }
    const screen = display.getDefaultDisplaySync();
    const width: number = Math.min(this.imageWidth, screen.width);
    const height: number = Math.min(this.imageHeight, screen.height);
    hilog.info(DOMAIN, TAG, 'pin window %{public}dx%{public}d for image %{public}dx%{public}d',
      width, height, this.imageWidth, this.imageHeight);
    win.resize(width, height).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'resize failed: %{public}d %{public}s', err.code, err.message);
    });
    win.moveWindowTo(PIN_ORIGIN_X, PIN_ORIGIN_Y).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'moveWindowTo failed: %{public}d %{public}s', err.code, err.message);
    });
  }
}
