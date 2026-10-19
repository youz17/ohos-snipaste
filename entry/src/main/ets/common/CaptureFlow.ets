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
 * 唯一触发入口是托盘面板的「开始截图」：它发一个跨进程信号（`tray/CaptureSignal.ets`）
 * 唤醒常驻的 `TrayAbility`，由后者调这里的 `run()`；
 * `busy` / 去抖防止同一波触发跑出两套窗口。
 */
export class CaptureFlow {
  private static busy: boolean = false;
  /** 类加载时刻≈应用启动时刻；这段时间内的触发一律忽略 */
  private static readonly startedAt: number = Date.now();
  private static lastRunAt: number = 0;
  /** 首次启动的静默期：启动窗口还没消失、窗口也刚配置，此时截图会把它拍进去 */
  private static readonly FIRST_LAUNCH_QUIET_MS: number = 3000;
  /** 常驻 Ability 里"信号 → 顺手点一下"可能连着来，去抖 */
  private static readonly REPEAT_GUARD_MS: number = 1500;

  static async run(ctx: common.UIAbilityContext): Promise<void> {
    const now: number = Date.now();
    if (now - CaptureFlow.startedAt < CaptureFlow.FIRST_LAUNCH_QUIET_MS) {
      hilog.info(DOMAIN, TAG, '%{public}s', 'skip: first launch (by design)');
      return;
    }
    if (CaptureFlow.busy || now - CaptureFlow.lastRunAt < CaptureFlow.REPEAT_GUARD_MS) {
      hilog.info(DOMAIN, TAG, '%{public}s', 'skip: busy or too soon');
      return;
    }
    CaptureFlow.busy = true;
    CaptureFlow.lastRunAt = now;
    try {
      // 这里只**查**权限，不申请：常驻的 TrayAbility 没有窗口，requestPermissionsFromUser 既不会
      // 弹窗也不会回调（promise 永久挂起，busy 卡死）。授权入口在欢迎窗口的「去授权」。
      const granted: boolean = ScreenCapturer.isGranted(ctx);
      if (!granted) {
        hilog.info(DOMAIN, TAG, '%{public}s',
          'screen capture not granted -> fallback to system picker (授权入口：托盘 → 使用说明)');
      }
      // 这里**不能** minimize：应用一进后台，后面的 startAbility 就报 201，选区窗口起不来
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
