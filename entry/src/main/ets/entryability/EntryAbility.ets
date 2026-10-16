import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CaptureFlow } from '../common/CaptureFlow';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

/**
 * 应用入口。窗口存在，但被做成**完全不可见**：去装饰、去阴影、背景近全透明，
 * 页面本身也是空的。用户全程只看得到选区窗口和贴图窗口。
 *
 * 为什么不能干脆不加载页面（"没有窗口"）：系统的启动窗口（start window）要等
 * 窗口内容绘制完成才消失，不 loadContent 的话启动窗口会一直挂屏幕上。
 * 所以页面必须加载，但可以通过 `start_window_background`（已改为近全透明）
 * 和下面的窗口配置让它看不见。
 *
 * 截图由 onCreate（冷启动）与 onNewWant（应用已在运行时再次被激活，例如再点一次
 * 任务栏图标）触发；刻意不放在页面的 onPageShow，避免与两者重复触发。
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    hilog.info(DOMAIN, TAG, '%{public}s', 'onCreate (首次启动不截图，等下一次激活)');
    CaptureFlow.run(this.context);
  }

  /** 应用还在运行时又被激活一次走这里。 */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onNewWant -> capture');
    CaptureFlow.run(this.context);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      this.setupInvisibleWindow(windowStage);
    });
  }

  /**
   * 主窗口：不可见（去装饰、去阴影、背景近全透明），并且**缩到最小、挪到右下角**，
   * 万一透明没生效也不会占着屏幕中间。
   */
  private setupInvisibleWindow(windowStage: window.WindowStage): void {
    const win = windowStage.getMainWindowSync();
    try {
      win.setWindowDecorVisible(false);
      win.setWindowBackgroundColor('#01000000');
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'invisible window failed: %{public}d %{public}s', e.code, e.message);
    }
    win.setWindowShadowEnabled(false).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'setWindowShadowEnabled failed: %{public}d %{public}s', err.code, err.message);
    });
    this.shrinkToCorner(win);
  }

  /**
   * 缩到系统允许的最小尺寸、贴右下角，然后**最小化**：屏幕上看不到任何我们的常驻窗口。
   * 注意单位不一致（实测踩过）：`resize` 收 vp，`moveWindowTo` 收 px，
   * 之前两处都按 vp 传，结果窗口落在屏幕中间。
   */
  private shrinkToCorner(win: window.Window): void {
    try {
      const dpy = display.getDefaultDisplaySync();
      const densityPx: number = dpy.densityPixels;
      const wVp: number = 320;
      const hVp: number = 72;
      const marginPx: number = Math.round(8 * densityPx);
      const dockPx: number = Math.round(46 * densityPx);
      const xPx: number = Math.max(0, dpy.width - Math.round(wVp * densityPx) - marginPx);
      const yPx: number = Math.max(0, dpy.height - dockPx - Math.round(hVp * densityPx) - marginPx);
      hilog.info(DOMAIN, TAG, 'shrink to %{public}dx%{public}dvp at %{public}d,%{public}dpx',
        wVp, hVp, xPx, yPx);
      win.resize(wVp, hVp)
        .then(() => win.moveWindowTo(xPx, yPx))
        .then(() => win.minimize())
        .catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'shrinkToCorner failed: %{public}d %{public}s', err.code, err.message);
        });
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'shrinkToCorner failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onBackground');
  }
}
