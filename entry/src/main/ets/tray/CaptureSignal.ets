import { commonEventManager, BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'CaptureSignal';

/**
 * 面板进程（`<bundle>:statusBarView`）→ 常驻进程（`<bundle>:entry:TrayAbility:0`）的触发通道。
 *
 * 为什么不用 `startAbility(TrayAbility, {action:'capture'})`（本项目试过的写法，含带
 * `StartupVisibility.STARTUP_HIDE` / `ProcessMode.ATTACH_TO_STATUS_BAR_ITEM` 的变体）：
 * 只要是启动 ability，sceneboard 就会把 TrayAbility 的场景容器重新激活成前台 ——
 * 应用立刻在任务栏冒出一个带运行点的图标，而且**关掉选区窗口后也不会消失**
 * （实测 `PCDock-PcSmartDockModel: refreshSCBSceneContainerSession : add: <persistentId>,
 * com.youz.ohsnipaste, , entry, TrayAbility` + `SCBSceneContainer: aboutToAppear`）。
 * 自定义公共事件是同应用内的跨进程通道，不经过 AMS 的场景切换，因此常驻进程可以"被叫醒干活"
 * 而不让应用在任务栏出现。
 */
const CAPTURE_EVENT = 'com.youz.ohsnipaste.action.CAPTURE';

/** 订阅者必须留引用：局部变量出作用域后会被回收，事件就收不到了。 */
let subscriber: commonEventManager.CommonEventSubscriber | undefined = undefined;

/**
 * 常驻进程侧：订阅"开始截图"信号（在 `TrayAbility.onCreate` 里调用一次）。
 * 进程活着就一直在听；进程不在了也就没有托盘图标可点，不需要补偿。
 */
export function listenCapture(onCapture: () => void): void {
  if (subscriber !== undefined) {
    return;
  }
  const info: commonEventManager.CommonEventSubscribeInfo = {
    events: [CAPTURE_EVENT],
    publisherBundleName: 'com.youz.ohsnipaste'
  };
  commonEventManager.createSubscriber(info).then((created: commonEventManager.CommonEventSubscriber) => {
    subscriber = created;
    commonEventManager.subscribe(created, (err: BusinessError) => {
      if (err) {
        hilog.error(DOMAIN, TAG, 'subscribe callback error: %{public}d %{public}s', err.code, err.message);
        return;
      }
      onCapture();
    });
    hilog.info(DOMAIN, TAG, '%{public}s', 'capture signal subscribed');
  }).catch((err: BusinessError) => {
    hilog.error(DOMAIN, TAG, 'createSubscriber failed: %{public}d %{public}s', err.code, err.message);
  });
}

/** 面板侧：发一次"开始截图"信号。 */
export function requestCapture(): Promise<void> {
  return new Promise<void>((resolve: () => void, reject: (e: BusinessError) => void) => {
    commonEventManager.publish(CAPTURE_EVENT, {}, (err: BusinessError) => {
      if (err) {
        reject(err);
        return;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'capture signal published');
      resolve();
    });
  });
}
