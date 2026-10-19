import { AbilityConstant, ConfigurationConstant, StartOptions, UIAbility, Want, contextConstant } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { registerTray } from '../tray/TrayEntry';
import { READY_MARKER } from '../tray/TrayAbility';
import { markWelcomeSeen, readWelcomeSeen } from '../common/Hotkey';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

/** 欢迎窗口尺寸（vp）与底色：不透明，否则看起来就是个"幽灵窗口" */
const WELCOME_W_VP = 560;
const WELCOME_H_VP = 520;
const WELCOME_BG = '#F5F6F7';
/** 托盘面板请求打开欢迎窗口时带的参数（值是 '1'） */
const PARAM_ABOUT = 'about';

/** 挂载进程启动重试：等服务端把 (accessTokenId, instanceKey) 写进自己的集合 */
const RETRY_MAX = 6;
const RETRY_INTERVAL_MS = 400;
/** 等挂载进程落就绪标记：它是异步起来的，不确认就退出会被当成"应用退出"而整包被杀 */
const READY_WAIT_MAX = 20;
const READY_WAIT_INTERVAL_MS = 300;

/**
 * 引导 Ability。它**不承载业务**：注册托盘图标 → 拉起常驻的 TrayAbility → 自己退出。
 *
 * 为什么要退出：应用的窗口是任务栏图标的来源（`excludeFromDock` 实测无效），
 * 而托盘图标由挂在状态栏项上的 TrayAbility 所在进程持有 —— 主窗口消失后图标仍在。
 * 这样应用常态下**没有任何窗口**，任务栏也就不占位。
 *
 * 例外是欢迎窗口（`pages/Welcome.ets`）：首次启动（或托盘面板点「使用说明」）时它需要
 * 用户看清楚内容，所以这次不退出；关掉窗口后本 Ability 才 `terminateSelf`。
 * 非首次启动则一上来就把主窗口最小化，避免闪出一个空白/透明窗口。
 */
export default class EntryAbility extends UIAbility {
  /** 本次是否要显示欢迎窗口 */
  private showWelcome: boolean = false;
  private welcomeShown: boolean = false;
  /** 拉起常驻进程时报了 16000068（它本来就在）—— 这时不会有新的握手文件 */
  private trayAlreadyRunning: boolean = false;
  /** 留着给 onNewWant 用：托盘再点「使用说明」时要把已经开着/最小化的窗口唤回前台 */
  private stage: window.WindowStage | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    const forced: boolean = EntryAbility.isAboutRequest(want);
    this.showWelcome = forced || !readWelcomeSeen(this.context);
    hilog.info(DOMAIN, TAG, 'onCreate -> bootstrap tray (welcome=%{public}s, forced=%{public}s)',
      this.showWelcome ? 'yes' : 'no', forced ? 'yes' : 'no');
    this.bootstrap();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.stage = windowStage;
    if (!this.showWelcome) {
      // 首次之后的启动：不弹任何窗口，主窗口一露头就收走
      this.hideMainWindow(windowStage);
      return;
    }
    this.setupWelcome(windowStage);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 窗口已经开着（singleton）时又被请求打开：把它唤回前台，不重复创建
    hilog.info(DOMAIN, TAG, '%{public}s', 'onNewWant -> bring welcome window to front');
    this.showWelcome = true;
    if (!this.welcomeShown && this.stage !== undefined) {
      this.setupWelcome(this.stage);
    }
    this.restoreMainWindow();
  }

  /** 把最小化的欢迎窗口唤回来（点托盘「使用说明」时走这里）。 */
  private restoreMainWindow(): void {
    const stage: window.WindowStage | undefined = this.stage;
    if (stage === undefined) {
      return;
    }
    try {
      const win: window.Window = stage.getMainWindowSync();
      win.show().then(() => {
        hilog.info(DOMAIN, TAG, '%{public}s', 'welcome window restored');
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'show failed: %{public}d %{public}s', err.code, err.message);
      });
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'restoreMainWindow failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  /** 非首次启动：把主窗口最小化，避免"空白透明窗口"一闪而过。 */
  private hideMainWindow(windowStage: window.WindowStage): void {
    try {
      const win: window.Window = windowStage.getMainWindowSync();
      win.minimize().then(() => {
        hilog.info(DOMAIN, TAG, '%{public}s', 'repeat launch: main window minimized');
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'minimize failed: %{public}d %{public}s', err.code, err.message);
      });
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'hideMainWindow failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  /** 首次启动 / 托盘请求：居中显示欢迎窗口。 */
  private setupWelcome(windowStage: window.WindowStage): void {
    if (this.welcomeShown) {
      return;
    }
    this.welcomeShown = true;
    // 先记"已看过"：窗口一旦露过面就不再自动弹，用户随时能从托盘面板重新打开
    markWelcomeSeen(this.context);
    let win: window.Window | undefined = undefined;
    try {
      win = windowStage.getMainWindowSync();
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'getMainWindowSync failed: %{public}d %{public}s', e.code, e.message);
    }
    if (win !== undefined) {
      EntryAbility.centerAndSize(win);
    }
    // 窗口还没进 normal 状态时 setWindowBackgroundColor 会报 1300002，等页面加载完再刷一次
    const painted: window.Window | undefined = win;
    windowStage.loadContent('pages/Welcome').then(() => {
      if (painted !== undefined) {
        EntryAbility.paintBackground(painted);
      }
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}d %{public}s', err.code, err.message);
    });
    hilog.info(DOMAIN, TAG, '%{public}s', 'welcome window shown');
  }

  /** resize 收 px、moveWindowTo 收 px（显式乘 densityPixels）。 */
  private static async centerAndSize(win: window.Window): Promise<void> {
    const screen: display.Display = display.getDefaultDisplaySync();
    const wPx: number = Math.round(WELCOME_W_VP * screen.densityPixels);
    const hPx: number = Math.round(WELCOME_H_VP * screen.densityPixels);
    try {
      await win.resize(wPx, hPx);
      await win.moveWindowTo(Math.round((screen.width - wPx) / 2), Math.round((screen.height - hPx) / 2));
      hilog.info(DOMAIN, TAG, 'welcome window %{public}dx%{public}d px', wPx, hPx);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'welcome resize/move failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  private static paintBackground(win: window.Window): void {
    try {
      win.setWindowBackgroundColor(WELCOME_BG);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'setWindowBackgroundColor failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  private static isAboutRequest(want: Want): boolean {
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined) {
      return false;
    }
    const about: Object | undefined = params[PARAM_ABOUT];
    return typeof about === 'string' && about === '1';
  }

  private async bootstrap(): Promise<void> {
    await registerTray(this.context);
    if (await this.attachTrayAbility()) {
      // 常驻进程本来就在（16000068）时不会再落握手文件，别等它
      if (!this.trayAlreadyRunning && !await this.waitForTrayReady()) {
        hilog.error(DOMAIN, TAG, '%{public}s', 'tray not ready, keep main ability alive');
        return;
      }
      if (this.showWelcome) {
        hilog.info(DOMAIN, TAG, '%{public}s', 'tray ready, keep welcome window open');
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
          this.trayAlreadyRunning = true;
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
