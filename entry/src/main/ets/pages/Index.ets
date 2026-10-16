import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CaptureResult, ScreenCapturer } from '../common/ScreenCapturer';
import { Launcher } from '../common/Launcher';
import { PinStore } from '../common/PinStore';

const DOMAIN = 0x0000;
const TAG = 'Index';

/**
 * 入口页面：刻意不放任何界面元素。
 * 应用以"任务栏图标"的形式存在，被激活（onPageShow）就直接开始截图，
 * 用户全程只看到选区窗口和贴图窗口，看不到应用主窗口。
 */
@Entry
@Component
struct Index {
  @State busy: boolean = false;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  onPageShow(): void {
    this.captureAndPin();
  }

  /**
   * 主链路：申请权限 → 截整屏（自身窗口已透明，不进截图）→
   * 冻结画面里框选 → 贴图。失败时降级为系统截图选择器。
   */
  private async captureAndPin(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const ctx: common.UIAbilityContext = this.context();
    try {
      const granted: boolean = await ScreenCapturer.ensurePermission(ctx);
      if (granted) {
        const shot: CaptureResult | undefined = await ScreenCapturer.captureScreen();
        if (shot !== undefined) {
          // 前缀用 shot：冻结整屏图不能和"贴图"混在一起，
          // 否则比较功能按 pin_ 找基准时会找到刚截的整屏图
          const path: string = await PinStore.saveAsPng(shot.pixelMap, ctx.filesDir, 'shot');
          await Launcher.openSelection(ctx, path, shot.width, shot.height);
          // 选区窗口已在前台，把主窗口收起来，避免透明窗口挡住桌面点击
          await this.hideSelfWindow(ctx);
          return;
        }
      }
      await this.pickAndPin(ctx);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'captureAndPin failed: %{public}d %{public}s', e.code, e.message);
    } finally {
      this.busy = false;
    }
  }

  /** 降级路径：系统截图选择器，无需权限，直接把选区结果贴出来。 */
  private async pickAndPin(ctx: common.UIAbilityContext): Promise<void> {
    const picked: CaptureResult | undefined = await ScreenCapturer.pickBySystem();
    if (picked === undefined) {
      hilog.warn(DOMAIN, TAG, '%{public}s', 'screenshot cancelled');
      return;
    }
    await Launcher.pinPixelMap(ctx, picked.pixelMap, ctx.filesDir, picked.width, picked.height);
  }

  private async hideSelfWindow(ctx: common.UIAbilityContext): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(ctx);
      await win.minimize();
      hilog.info(DOMAIN, TAG, '%{public}s', 'main window hidden');
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'minimize failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#01000000')
  }
}
