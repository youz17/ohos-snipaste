import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CaptureResult, ScreenCapturer } from './ScreenCapturer';
import { Launcher } from './Launcher';
import { PinStore } from './PinStore';

const DOMAIN = 0x0000;
const TAG = 'CaptureFlow';

/**
 * 主链路：申请权限 → 截整屏（自身窗口已透明，不进截图）→
 * 冻结画面里框选 → 贴图。失败时降级为系统截图选择器。
 *
 * 触发入口有两个：页面的 onPageShow（点任务栏图标）和全局快捷键，
 * 所以流程放在这里共用；busy 防止两者同时触发跑出两套窗口。
 */
export class CaptureFlow {
  private static busy: boolean = false;

  static async run(ctx: common.UIAbilityContext): Promise<void> {
    if (CaptureFlow.busy) {
      return;
    }
    CaptureFlow.busy = true;
    try {
      const granted: boolean = await ScreenCapturer.ensurePermission(ctx);
      if (granted) {
        const shot: CaptureResult | undefined = await ScreenCapturer.captureScreen();
        if (shot !== undefined) {
          // 前缀用 shot：冻结整屏图不能和"贴图"混在一起，
          // 否则比较功能按 pin_ 找基准时会找到刚截的整屏图
          const path: string = await PinStore.saveAsPng(shot.pixelMap, ctx.filesDir, 'shot');
          await Launcher.openSelection(ctx, path, shot.width, shot.height);
          // 选区窗口已在前台，把主窗口收起来：主窗口虽然不可见，但仍会吃掉它范围内的点击
          await CaptureFlow.hideSelfWindow(ctx);
          return;
        }
      }
      await CaptureFlow.pickAndPin(ctx);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'run failed: %{public}d %{public}s', e.code, e.message);
    } finally {
      CaptureFlow.busy = false;
    }
  }

  /** 降级路径：系统截图选择器，无需权限，直接把选区结果贴出来。 */
  private static async pickAndPin(ctx: common.UIAbilityContext): Promise<void> {
    const picked: CaptureResult | undefined = await ScreenCapturer.pickBySystem();
    if (picked === undefined) {
      hilog.warn(DOMAIN, TAG, '%{public}s', 'screenshot cancelled');
      return;
    }
    await Launcher.pinPixelMap(ctx, picked.pixelMap, ctx.filesDir, picked.width, picked.height);
  }

  private static async hideSelfWindow(ctx: common.UIAbilityContext): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(ctx);
      await win.minimize();
      hilog.info(DOMAIN, TAG, '%{public}s', 'main window hidden');
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'minimize failed: %{public}d %{public}s', e.code, e.message);
    }
  }
}
