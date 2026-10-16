import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PinPayload } from '../common/PinPayload';

const DOMAIN = 0x0000;
const TAG = 'SelectionAbility';

/**
 * 区域截图窗口：铺满整屏显示冻结的截图，由页面自绘遮罩与选区。
 * 因为画面已被冻结，所以不需要系统级悬浮窗权限。
 */
export default class SelectionAbility extends UIAbility {
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
    hilog.info(DOMAIN, TAG, 'onCreate size=%{public}dx%{public}d pathLen=%{public}d',
      this.imageWidth, this.imageHeight, this.imagePath.length);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const win = windowStage.getMainWindowSync();
    PinPayload.save(win.getWindowProperties().id, this.imagePath);
    windowStage.loadContent('pages/SelectionPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      this.setupFullScreenWindow(windowStage);
    });
  }

  /** 去掉边框、铺满屏幕，让冻结画面盖住整个显示器。 */
  private setupFullScreenWindow(windowStage: window.WindowStage): void {
    const win = windowStage.getMainWindowSync();
    try {
      win.setWindowDecorVisible(false);
      win.setWindowTitleButtonVisible(false, false, false);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'hide decor failed: %{public}d %{public}s', e.code, e.message);
    }
    win.setWindowLayoutFullScreen(true).then(() => {
      return win.maximize();
    }).then(() => {
      hilog.info(DOMAIN, TAG, '%{public}s', 'selection window fullscreen');
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'fullscreen failed: %{public}d %{public}s', err.code, err.message);
    });
  }
}
