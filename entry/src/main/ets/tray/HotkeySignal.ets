import { commonEventManager, BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'HotkeySignal';

/**
 * 欢迎窗口（`EntryAbility` 进程）→ 常驻进程（`<bundle>:entry:TrayAbility:0`）的改键通道。
 *
 * 为什么必须跨进程：全局快捷键注册在常驻进程（`TrayAbility`）里，窗口进程改完设置
 * 自己也活不久。走同应用自定义公共事件，和 `tray/CaptureSignal.ets` 同一套手法 —— 不启动
 * 任何 ability，因而不会把应用拉进任务栏。
 *
 * 参数一律用字符串/数字传（`CommonEventData.parameters` 是弱类型，跨进程别塞复杂对象）。
 */
const CHANGE_EVENT = 'com.youz.ohsnipaste.action.HOTKEY_CHANGE';
/** 常驻进程 → 窗口进程：改键结果，失败时窗口据此回滚。 */
const RESULT_EVENT = 'com.youz.ohsnipaste.action.HOTKEY_RESULT';

const PARAM_PRE_KEYS = 'preKeys';
const PARAM_FINAL_KEY = 'finalKey';
const PARAM_OK = 'ok';
const PARAM_CODE = 'code';

export interface HotkeyChangeParams {
  preKeys: number[];
  finalKey: number;
}

export interface HotkeyApplyResult {
  ok: boolean;
  code: number;
}

/** 订阅者必须留引用：局部变量出作用域后会被回收，事件就收不到了。 */
let changeSubscriber: commonEventManager.CommonEventSubscriber | undefined = undefined;
let resultSubscriber: commonEventManager.CommonEventSubscriber | undefined = undefined;

function param(data: commonEventManager.CommonEventData, key: string): Object | undefined {
  const params: Record<string, Object> | undefined = data.parameters;
  return params === undefined ? undefined : params[key];
}

/** 常驻进程侧：订阅"改快捷键"请求（在 `TrayAbility.onCreate` 里调用一次）。 */
export function listenHotkeyChange(onChange: (params: HotkeyChangeParams) => void): void {
  if (changeSubscriber !== undefined) {
    return;
  }
  const info: commonEventManager.CommonEventSubscribeInfo = {
    events: [CHANGE_EVENT],
    publisherBundleName: 'com.youz.ohsnipaste'
  };
  commonEventManager.createSubscriber(info).then((created: commonEventManager.CommonEventSubscriber) => {
    changeSubscriber = created;
    commonEventManager.subscribe(created, (err: BusinessError, data: commonEventManager.CommonEventData) => {
      if (err) {
        hilog.error(DOMAIN, TAG, 'change callback error: %{public}d %{public}s', err.code, err.message);
        return;
      }
      const pre: Object | undefined = param(data, PARAM_PRE_KEYS);
      const fin: Object | undefined = param(data, PARAM_FINAL_KEY);
      if (typeof pre !== 'string' || typeof fin !== 'number') {
        hilog.warn(DOMAIN, TAG, '%{public}s', 'hotkey change: bad params');
        return;
      }
      const preKeys: number[] = [];
      for (const part of pre.split(',')) {
        const n: number = Number(part);
        if (!Number.isNaN(n) && n > 0) {
          preKeys.push(Math.trunc(n));
        }
      }
      if (preKeys.length === 0) {
        hilog.warn(DOMAIN, TAG, '%{public}s', 'hotkey change: empty preKeys');
        return;
      }
      onChange({ preKeys: preKeys, finalKey: Math.trunc(fin) });
    });
    hilog.info(DOMAIN, TAG, '%{public}s', 'hotkey change subscribed');
  }).catch((err: BusinessError) => {
    hilog.error(DOMAIN, TAG, 'createSubscriber failed: %{public}d %{public}s', err.code, err.message);
  });
}

/** 窗口侧：请求改全局快捷键。 */
export function requestHotkeyChange(preKeys: number[], finalKey: number): Promise<void> {
  return new Promise<void>((resolve: () => void, reject: (e: BusinessError) => void) => {
    const data: commonEventManager.CommonEventPublishData = {
      parameters: {
        preKeys: preKeys.join(','),
        finalKey: finalKey
      }
    };
    commonEventManager.publish(CHANGE_EVENT, data, (err: BusinessError) => {
      if (err) {
        reject(err);
        return;
      }
      hilog.info(DOMAIN, TAG, 'hotkey change published');
      resolve();
    });
  });
}

/** 常驻进程侧：回报注册结果。 */
export function reportHotkeyResult(ok: boolean, code: number): void {
  const data: commonEventManager.CommonEventPublishData = {
    parameters: {
      ok: ok,
      code: code
    }
  };
  commonEventManager.publish(RESULT_EVENT, data, (err: BusinessError) => {
    if (err) {
      hilog.warn(DOMAIN, TAG, 'report result failed: %{public}d %{public}s', err.code, err.message);
    }
  });
}

/** 窗口侧：等常驻进程的结果（成功即生效；失败则回滚）。 */
export function listenHotkeyResult(onResult: (result: HotkeyApplyResult) => void): void {
  if (resultSubscriber !== undefined) {
    return;
  }
  const info: commonEventManager.CommonEventSubscribeInfo = {
    events: [RESULT_EVENT],
    publisherBundleName: 'com.youz.ohsnipaste'
  };
  commonEventManager.createSubscriber(info).then((created: commonEventManager.CommonEventSubscriber) => {
    resultSubscriber = created;
    commonEventManager.subscribe(created, (err: BusinessError, data: commonEventManager.CommonEventData) => {
      if (err) {
        hilog.error(DOMAIN, TAG, 'result callback error: %{public}d %{public}s', err.code, err.message);
        return;
      }
      const ok: Object | undefined = param(data, PARAM_OK);
      const code: Object | undefined = param(data, PARAM_CODE);
      if (typeof ok !== 'boolean' || typeof code !== 'number') {
        return;
      }
      onResult({ ok: ok, code: Math.trunc(code) });
    });
    hilog.info(DOMAIN, TAG, '%{public}s', 'hotkey result subscribed');
  }).catch((err: BusinessError) => {
    hilog.error(DOMAIN, TAG, 'createSubscriber failed: %{public}d %{public}s', err.code, err.message);
  });
}
