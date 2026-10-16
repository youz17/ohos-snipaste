import { AbilityConstant, ConfigurationConstant, StartOptions, UIAbility, Want, contextConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { registerTray } from '../tray/TrayEntry';
import { READY_MARKER } from '../tray/TrayAbility';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

/** 挂载进程启动重试：等服务端把 (accessTokenId, instanceKey) 写进自己的集合 */
const RETRY_MAX = 6;
const RETRY_INTERVAL_MS = 400;
/** 等挂载进程落就绪标记：它是异步起来的，不确认就退出会被当成"应用退出"而整包被杀 */
const READY_WAIT_MAX = 20;
const READY_WAIT_INTERVAL_MS = 300;

/**
 * 引导 Ability。它**不参与业务**：注册托盘图标 → 拉起常驻的 TrayAbility → 自己退出。
 *
 * 为什么要退出：应用的窗口是任务栏图标的来源（`excludeFromDock` 实测无效），
 * 而托盘图标由挂在状态栏项上的 TrayAbility 所在进程持有 —— 主窗口消失后图标仍在。
 * 这样应用常态下**没有任何窗口**，任务栏也就不占位。
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    hilog.info(DOMAIN, TAG, '%{public}s', 'onCreate -> bootstrap tray');
    this.bootstrap();
  }

  private async bootstrap(): Promise<void> {
    await registerTray(this.context);
    if (await this.attachTrayAbility()) {
      if (!await this.waitForTrayReady()) {
        hilog.error(DOMAIN, TAG, '%{public}s', 'tray not ready, keep main ability alive');
        return;
      }
      try {
        await this.context.terminateSelf();
        hilog.info(DOMAIN, TAG, '%{public}s', 'bootstrap done, main ability terminated (no window left)');
      } catch (err) {
        const e = err as BusinessError;
        hilog.error(DOMAIN, TAG, 'terminateSelf failed: %{public}d %{public}s', e.code, e.message);
      }
    }
  }

  /**
   * 等 TrayAbility 把自己的窗口建起来（它落一个标记文件）。
   * 不能只等 `startAbility` 返回 —— 那时候 AMS 还没把新 ability 记进去，
   * 立刻 `terminateSelf` 会被判定成"应用最后一个 ability 退出"，整个应用被杀（实测）。
   */
  private async waitForTrayReady(): Promise<boolean> {
    const path = `${this.context.filesDir}/${READY_MARKER}`;
    for (let i = 0; i < READY_WAIT_MAX; i++) {
      // 注意：accessSync 是**返回 boolean**，不是"不存在就抛异常"
      const exists: boolean = fs.accessSync(path);
      if (exists) {
        hilog.info(DOMAIN, TAG, 'tray ready after ~%{public}d ms', i * READY_WAIT_INTERVAL_MS);
        return true;
      }
      await EntryAbility.sleep(READY_WAIT_INTERVAL_MS);
    }
    return false;
  }

  /**
   * 拉起挂在状态栏项上的常驻进程。顺序不能反：系统要求**先** `addToStatusBar`（在 registerTray 里）
   * 再以 `NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM` 启动，否则报 `16000067 StartOptions check failed`。
   * 那个校验查的是服务侧回调 `CreateTrayForApp` 填的 (accessTokenId, instanceKey) 集合，
   * 而 `addToStatusBar` 只是把请求投递过去就返回了 —— 所以要有界重试等服务端就绪，别用固定 sleep。
   */
  private async attachTrayAbility(): Promise<boolean> {
    const opts: StartOptions = {
      processMode: contextConstant.ProcessMode.NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM,
      startupVisibility: contextConstant.StartupVisibility.STARTUP_HIDE
    };
    const want: Want = {
      bundleName: this.context.abilityInfo.bundleName,
      moduleName: 'entry',
      abilityName: 'TrayAbility'
    };
    // 清掉上一轮可能残留的标记，保证下面等到的"就绪"是本次的
    try {
      fs.unlinkSync(`${this.context.filesDir}/${READY_MARKER}`);
    } catch (err) {
      // 文件不在属正常情况，忽略
    }
    for (let attempt = 0; attempt < RETRY_MAX; attempt++) {
      try {
        await this.context.startAbility(want, opts);
        hilog.info(DOMAIN, TAG, 'TrayAbility attached (attempt %{public}d)', attempt + 1);
        return true;
      } catch (err) {
        const e = err as BusinessError;
        // 16000068：常驻进程早就起好了（例如应用图标被点了第二次），按成功处理
        if (e.code === 16000068) {
          hilog.info(DOMAIN, TAG, '%{public}s', 'TrayAbility already running');
          return true;
        }
        hilog.warn(DOMAIN, TAG, 'attach attempt %{public}d failed: %{public}d %{public}s',
          attempt + 1, e.code, e.message);
        if (attempt < RETRY_MAX - 1) {
          await EntryAbility.sleep(RETRY_INTERVAL_MS);
        }
      }
    }
    hilog.error(DOMAIN, TAG, '%{public}s', 'attach gave up, keep main ability alive');
    return false;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onDestroy');
  }
}
