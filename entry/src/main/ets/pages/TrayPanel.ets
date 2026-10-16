import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
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

  /** 拉起 EntryAbility —— 它被激活即走截图链路（onNewWant → CaptureFlow）。 */
  private async capture(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const ctx = this.ctx();
    try {
      await ctx.startAbility({
        bundleName: ctx.extensionAbilityInfo.bundleName,
        moduleName: 'entry',
        abilityName: 'EntryAbility'
      });
      hilog.info(DOMAIN, TAG, '%{public}s', 'startAbility EntryAbility ok');
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'startAbility failed: %{public}d %{public}s', e.code, e.message);
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
