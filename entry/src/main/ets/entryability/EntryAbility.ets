import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

/**
 * 应用的入口 Ability。它本身不显示界面：窗口去边框 + 全透明，
 * 页面内容为空，激活应用即开始截图（类 Snipaste 的常驻托盘式用法）。
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    hilog.info(DOMAIN, TAG, '%{public}s', 'onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onDestroy');
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

  /** 主窗口不可见：去装饰、去阴影、背景全透明。 */
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
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onBackground');
  }
}
