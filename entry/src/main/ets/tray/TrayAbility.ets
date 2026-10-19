import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { inputConsumer } from '@kit.InputKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CaptureFlow } from '../common/CaptureFlow';
import { DEFAULT_HOTKEY, HotkeyCombo, hotkeyLabel, readHotkey } from '../common/Hotkey';
import { listenCapture } from './CaptureSignal';
import { HotkeyChangeParams, listenHotkeyChange, reportHotkeyResult } from './HotkeySignal';

const DOMAIN = 0x0000;
const TAG = 'TrayAbility';

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
 * 2. 它**不加载任何页面**，因此压根没有窗口 —— 实测 WindowManagerService 里查不到它的窗口记录，
 *    任务栏自然也不占位。
 *
 * 两条触发链路都挂在这里（而不是 EntryAbility）：主窗口已经不需要存在，
 * 面板点「开始截图」发一个跨进程信号（`CaptureSignal`）唤醒本 Ability 走 CaptureFlow ——
 * 用信号而不是 `startAbility`，否则应用会立刻被重新拉进任务栏（见 `CaptureSignal` 的说明）；
 * 全局快捷键则在 `onCreate` 里一次注册，按键回调直接走同一条 CaptureFlow。
 */
export default class TrayAbility extends UIAbility {
  /** 当前已注册的组合。改键时要按**同一个对象** off，所以留引用。 */
  private current: inputConsumer.HotkeyOptions = TrayAbility.optionsOf(DEFAULT_HOTKEY);

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onCreate (resident, no window to show)');
    this.registerHotkey();
    listenCapture(() => {
      this.capture(PANEL_SETTLE_MS);
    });
    listenHotkeyChange((params: HotkeyChangeParams) => {
      this.applyHotkey(params);
    });
  }

  private static optionsOf(combo: HotkeyCombo): inputConsumer.HotkeyOptions {
    return { preKeys: combo.preKeys.slice(), finalKey: combo.finalKey, isRepeat: false };
  }

  /**
   * 按设置注册截图快捷键（默认 Ctrl+Shift+A：2072 = KEYCODE_CTRL_LEFT，2047 = KEYCODE_SHIFT_LEFT，
   * 2017 = KEYCODE_A；实际组合存在 `common/Hotkey.ets`，欢迎窗口里可改）。
   *
   * `inputConsumer.on('hotkeyChange')` 是**全局**快捷键：官方参考页标题即「全局快捷键」，接口描述是
   * "订阅应用快捷键，获取满足条件的组合按键输入事件"，无权限要求、无前台限定（SDK 注释里的 "change"
   * 是措辞误导）。真机实测：注册在常驻进程、应用没有任何窗口、焦点在别的会话时按下仍回调。
   *
   * 修饰键必填（`preKeys` 至少一个），所以做不出 Snipaste 那种裸 F1。
   * 订阅是**排他**的：系统已占用报 4200002，别的应用已占用报 4200003 —— 同一组合全局只归一家，
   * 因此换键位时先看日志里是否报这两个码（改键失败会回滚并回报给欢迎窗口）。
   */
  private registerHotkey(): void {
    const combo: HotkeyCombo = readHotkey(this.context);
    const opts: inputConsumer.HotkeyOptions = TrayAbility.optionsOf(combo);
    try {
      inputConsumer.on('hotkeyChange', opts, (fired: inputConsumer.HotkeyOptions) => {
        hilog.info(DOMAIN, TAG, 'hotkey fired %{public}s', JSON.stringify(fired));
        this.capture(0);
      });
      this.current = opts;
      hilog.info(DOMAIN, TAG, 'hotkey registered: %{public}s', hotkeyLabel(combo));
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'hotkey register failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  /**
   * 欢迎窗口请求改键：先按旧对象 off，再注册新组合；新组合被占用（4200002 / 4200003）时
   * 把旧组合装回去，并回报给窗口让它回滚设置。
   */
  private applyHotkey(params: HotkeyChangeParams): void {
    const combo: HotkeyCombo = { preKeys: params.preKeys, finalKey: params.finalKey };
    const next: inputConsumer.HotkeyOptions = TrayAbility.optionsOf(combo);
    const previous: inputConsumer.HotkeyOptions = this.current;
    try {
      inputConsumer.off('hotkeyChange', previous);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'hotkey off failed: %{public}d %{public}s', e.code, e.message);
    }
    try {
      inputConsumer.on('hotkeyChange', next, (fired: inputConsumer.HotkeyOptions) => {
        hilog.info(DOMAIN, TAG, 'hotkey fired %{public}s', JSON.stringify(fired));
        this.capture(0);
      });
      this.current = next;
      hilog.info(DOMAIN, TAG, 'hotkey re-registered: %{public}s', hotkeyLabel(combo));
      reportHotkeyResult(true, 0);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'hotkey re-register failed: %{public}d %{public}s (restore previous)',
        e.code, e.message);
      try {
        inputConsumer.on('hotkeyChange', previous, (fired: inputConsumer.HotkeyOptions) => {
          hilog.info(DOMAIN, TAG, 'hotkey fired %{public}s', JSON.stringify(fired));
          this.capture(0);
        });
        this.current = previous;
      } catch (err2) {
        const e2 = err2 as BusinessError;
        hilog.error(DOMAIN, TAG, 'restore hotkey failed: %{public}d %{public}s', e2.code, e2.message);
      }
      reportHotkeyResult(false, e.code);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 刻意不 loadContent：这条常驻 Ability 不需要任何窗口内容（截图由面板信号或全局快捷键触发），
    // 而它的窗口一起步就是 STARTUP_HIDE，之后**再也不会被拉起**，所以不存在"启动窗口挂着不消失"
    // 的问题（那要求窗口会被显示）。实测该 Ability 在 WindowManagerService 里连窗口记录都没有。
    this.markReady();
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

  /** @param delayMs 面板触发要等它收起（`PANEL_SETTLE_MS`）；快捷键触发没有面板，直接 0。 */
  private capture(delayMs: number): void {
    hilog.info(DOMAIN, TAG, 'capture triggered -> CaptureFlow in %{public}dms', delayMs);
    setTimeout(() => {
      CaptureFlow.run(this.context).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'CaptureFlow failed: %{public}d %{public}s', err.code, err.message);
      });
    }, delayMs);
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
