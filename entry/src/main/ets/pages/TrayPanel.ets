import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { requestCapture } from '../tray/CaptureSignal';
import { unregisterTray } from '../tray/TrayEntry';

const DOMAIN = 0x0000;
const TAG = 'TrayPanel';

/** 托盘图标的面板：点动作后收起面板。 */
@Entry
@Component
struct TrayPanel {
  @State private busy: boolean = false;

  private ctx(): common.UIExtensionContext {
    return getContext(this) as common.UIExtensionContext;
  }

  /** 收起面板。失败也无妨 —— 窗口切换也会把面板挤掉。 */
  private async dismiss(): Promise<void> {
    try {
      await this.ctx().terminateSelf();
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'terminateSelf failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  /**
   * 重新打开欢迎/使用说明窗口。
   *
   * 面板是 UIExtension，`UIExtensionContext.startAbility` 可用，所以直接拉起 EntryAbility，
   * 带上 `about=1` 让它跳过"首次启动"判断。窗口关掉后 EntryAbility 自己退出。
   */
  private async showWelcome(): Promise<void> {
    const ctx = this.ctx();
    try {
      await ctx.startAbility({
        bundleName: ctx.extensionAbilityInfo.bundleName,
        moduleName: 'entry',
        abilityName: 'EntryAbility',
        parameters: { about: '1' }
      });
      hilog.info(DOMAIN, TAG, '%{public}s', 'welcome window requested');
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'startAbility failed: %{public}d %{public}s', e.code, e.message);
    }
    await this.dismiss();
  }

  /**
   * 通知常驻的 TrayAbility"开始截图"。
   *
   * 走跨进程信号而不是 `startAbility`：后者会把 TrayAbility 的场景容器重新激活成前台，
   * 应用立刻在任务栏冒出一个带运行点的图标，而且之后不会自己消失。
   * 详细实测见 `tray/CaptureSignal.ets`。
   */
  private async capture(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      await requestCapture();
      hilog.info(DOMAIN, TAG, '%{public}s', 'capture requested');
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'requestCapture failed: %{public}d %{public}s', e.code, e.message);
      this.busy = false;
      return;
    }
    await this.dismiss();
  }

  /** 退出：先摘图标再杀进程。killAllProcesses 是强制退出，不走正常生命周期。 */
  private async quit(): Promise<void> {
    const ctx = this.ctx();
    unregisterTray(ctx);
    try {
      await ctx.getApplicationContext().killAllProcesses(true);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'killAllProcesses failed: %{public}d %{public}s', e.code, e.message);
      await this.dismiss();
    }
  }

  build() {
    Column({ space: 10 }) {
      Image($r('app.media.panel_icon'))
        .width(40)
        .height(40)
        .margin({ bottom: 2 })
      Button('开始截图')
        .type(ButtonType.Normal)
        .width('100%')
        .height(40)
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor('#2563EB')
        .borderRadius(8)
        .onClick(() => {
          this.capture();
        })
      Button('使用说明')
        .type(ButtonType.Normal)
        .width('100%')
        .height(40)
        .fontSize(14)
        .fontColor('#1F2328')
        .backgroundColor('#E8EAED')
        .borderRadius(8)
        .onClick(() => {
          this.showWelcome();
        })
      Button('退出')
        .type(ButtonType.Normal)
        .width('100%')
        .height(40)
        .fontSize(14)
        .fontColor('#E84026')
        .backgroundColor('#E8EAED')
        .borderRadius(8)
        .onClick(() => {
          this.quit();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 10 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F1F3F5')
  }
}
