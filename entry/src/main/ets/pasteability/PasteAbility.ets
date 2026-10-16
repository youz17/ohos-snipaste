import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PinPayload } from '../common/PinPayload';

const DOMAIN = 0x0000;
const TAG = 'PasteAbility';

/** 贴图窗口的最大边长（px），避免整屏截图时窗口超出屏幕。 */
const MAX_PIN_SIDE: number = 900;
/** 贴图窗口初始落点（px）。 */
const PIN_ORIGIN_X: number = 160;
const PIN_ORIGIN_Y: number = 160;

/**
 * 贴图窗口。声明为 multiton，因此每张贴图都是一个独立窗口，互不覆盖。
 * 通过 setWindowTopmost 让窗口浮在其它应用之上（WINDOW_TOPMOST 是 normal 级
 * system_grant 权限，普通应用声明即得，无需 ACL）。
 */
export default class PasteAbility extends UIAbility {
  private imagePath: string = '';
  private imageWidth: number = 0;
  private imageHeight: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const params = want.parameters;
    if (params !== undefined) {
      this.imagePath = params.imagePath as string;
      this.imageWidth = params.imageWidth as number;
      this.imageHeight = params.imageHeight as number;
    }
    hilog.info(DOMAIN, TAG, 'onCreate path=%{public}s size=%{public}dx%{public}d',
      this.imagePath, this.imageWidth, this.imageHeight);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const mainWindow = windowStage.getMainWindowSync();
    PinPayload.save(mainWindow.getWindowProperties().id, this.imagePath);
    windowStage.loadContent('pages/PastePage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      this.setupPinWindow(windowStage);
    });
  }

  /** 去边框、置顶、按图片比例调整窗口大小与位置。 */
  private setupPinWindow(windowStage: window.WindowStage): void {
    const win = windowStage.getMainWindowSync();
    try {
      win.setWindowDecorVisible(false);
      win.setWindowTitleButtonVisible(false, false, false);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'hide decor failed: %{public}d %{public}s', e.code, e.message);
    }
    win.setWindowTopmost(true).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'setWindowTopmost failed: %{public}d %{public}s', err.code, err.message);
    });
    this.fitWindowToImage(win);
  }

  private fitWindowToImage(win: window.Window): void {
    if (this.imageWidth <= 0 || this.imageHeight <= 0) {
      return;
    }
    const scale: number = Math.min(1, MAX_PIN_SIDE / Math.max(this.imageWidth, this.imageHeight));
    const width: number = Math.max(160, Math.round(this.imageWidth * scale));
    const height: number = Math.max(120, Math.round(this.imageHeight * scale));
    win.resize(width, height).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'resize failed: %{public}d %{public}s', err.code, err.message);
    });
    win.moveWindowTo(PIN_ORIGIN_X, PIN_ORIGIN_Y).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'moveWindowTo failed: %{public}d %{public}s', err.code, err.message);
    });
  }
}
