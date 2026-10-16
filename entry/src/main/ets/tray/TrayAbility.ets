import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CaptureFlow } from '../common/CaptureFlow';

const DOMAIN = 0x0000;
const TAG = 'TrayAbility';

/** 面板按「开始截图」时带过来的动作标记，用于区分"引导启动"和"要截图" */
export const ACTION_CAPTURE = 'capture';

/**
 * 引导进程是否就绪的握手文件（在 filesDir 下）。
 *
 * 为什么需要它：EntryAbility 拉起本 Ability 后立刻 `terminateSelf`，此刻 AMS 眼里
 * 本 Ability 还没建起来，会把"最后一个 ability 退出"当成应用退出而**杀掉整个应用**
 * （实测日志：`ProcessMgr: terminate isLast:1 → Terminate last → app died`）。
 * 所以本 Ability 在自己的窗口起来后落一个文件，EntryAbility 轮询到它才退出。
 * 本 Ability 销毁时删掉它，避免下次引导误判为"已就绪"。
 */
export const READY_MARKER = 'tray-ready';

/**
 * 触发截图前先等的毫秒数。
 *
 * 面板是 sceneboard 的普通窗口，**不属于"自身窗口"、不会被排除在截图之外**。
 * 点面板按钮后面板要靠焦点转移才收起，而这个收起是异步的：实测等待 0ms 时冻结图里
 * 常带着面板（能看到变暗的面板与蓝按钮），等 500ms 才稳定干净。
 */
const PANEL_SETTLE_MS = 500;

/**
 * 常驻 Ability：托盘的载体。
 *
 * 由 EntryAbility 以 `processMode: NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM` +
 * `startupVisibility: STARTUP_HIDE` 启动，因此：
 * 1. 它跑在**独立进程**里（`...:entry:TrayAbility:0`），EntryAbility 退出后它还在，
 *    状态栏图标得以在应用没有任何窗口时继续存在 —— 这就是"去掉主窗口/任务栏图标"的前提。
 * 2. 它的窗口一起步就是隐藏的，不会在任务栏占位。
 *
 * 截图链路挂在这里（而不是 EntryAbility）：主窗口已经不需要存在，
 * 面板点「开始截图」直接拉起本 Ability 走 CaptureFlow。
 */
export default class TrayAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate, action=%{public}s', String(want.parameters?.['action']));
    this.captureIfAsked(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onNewWant, action=%{public}s', String(want.parameters?.['action']));
    this.captureIfAsked(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 必须 loadContent：不加载的话系统启动窗口会一直挂着（EntryAbility 的历史踩坑）。
    // 本 Ability 一起步就是 STARTUP_HIDE，页面内容用户看不到。
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      this.markReady();
    });
  }

  /** 落握手文件，通知引导 Ability"我起来了，你可以退出了"。 */
  private markReady(): void {
    const path = `${this.context.filesDir}/${READY_MARKER}`;
    try {
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      fs.closeSync(file);
      hilog.info(DOMAIN, TAG, 'ready marker written: %{public}s', path);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'markReady failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  private captureIfAsked(want: Want): void {
    if (want.parameters?.['action'] !== ACTION_CAPTURE) {
      return;
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'capture requested -> settle then CaptureFlow');
    setTimeout(() => {
      CaptureFlow.run(this.context).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'CaptureFlow failed: %{public}d %{public}s', err.code, err.message);
      });
    }, PANEL_SETTLE_MS);
  }

  onDestroy(): void {
    try {
      fs.unlinkSync(`${this.context.filesDir}/${READY_MARKER}`);
    } catch (err) {
      // 文件不在属正常情况，忽略
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'onDestroy');
  }
}
