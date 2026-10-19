import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'Hotkey';

/** 设置库名。两个进程（引导窗口 / 常驻进程）都从这里读写。 */
const STORE = 'settings';
const KEY_WELCOME_SEEN = 'welcome_seen';
const KEY_HOTKEY = 'hotkey';

/** 全局快捷键组合，语义同 `inputConsumer.HotkeyOptions`。 */
export interface HotkeyCombo {
  preKeys: number[];
  finalKey: number;
}

/** 默认 Ctrl+Shift+A（2072 = Ctrl 左、2047 = Shift 左、2017 = A）。 */
export const DEFAULT_HOTKEY: HotkeyCombo = { preKeys: [2072, 2047], finalKey: 2017 };

/** 修饰键：全局快捷键必须至少带一个，裸键注册不了（见 SPEC-AND-TRUTH 3.2）。 */
const MODIFIERS: number[] = [2045, 2046, 2047, 2048, 2072, 2073];

export function isModifier(code: number): boolean {
  return MODIFIERS.indexOf(code) >= 0;
}

export function modifierLabel(code: number): string {
  if (code === 2072 || code === 2073) {
    return 'Ctrl';
  }
  if (code === 2047 || code === 2048) {
    return 'Shift';
  }
  if (code === 2045 || code === 2046) {
    return 'Alt';
  }
  return '';
}

/** 主键显示名：数字 / 字母 / F1-F12 / 常用符号，其余退回 `#<keyCode>`。 */
export function keyLabel(code: number): string {
  if (code >= 2000 && code <= 2009) {
    return `${code - 2000}`;
  }
  if (code >= 2017 && code <= 2042) {
    return String.fromCharCode(code - 2017 + 65);
  }
  if (code >= 2090 && code <= 2101) {
    return `F${code - 2089}`;
  }
  if (code === 2050) {
    return 'Space';
  }
  if (code === 2049) {
    return 'Tab';
  }
  if (code === 2054) {
    return 'Enter';
  }
  if (code === 2055) {
    return 'Del';
  }
  if (code === 2070) {
    return 'Esc';
  }
  return `#${code}`;
}

export function hotkeyLabel(combo: HotkeyCombo): string {
  const parts: string[] = [];
  for (const code of combo.preKeys) {
    const name: string = modifierLabel(code);
    parts.push(name.length > 0 ? name : keyLabel(code));
  }
  parts.push(keyLabel(combo.finalKey));
  return parts.join(' + ');
}

/** 是否为可用的组合：至少一个修饰键 + 一个主键，修饰键最多 4 个。 */
export function isValidCombo(combo: HotkeyCombo): boolean {
  if (combo.preKeys.length < 1 || combo.preKeys.length > 4) {
    return false;
  }
  if (combo.finalKey <= 0 || isModifier(combo.finalKey)) {
    return false;
  }
  for (const code of combo.preKeys) {
    if (!isModifier(code)) {
      return false;
    }
  }
  return true;
}

function store(ctx: common.Context): preferences.Preferences | undefined {
  try {
    return preferences.getPreferencesSync(ctx, { name: STORE });
  } catch (err) {
    const e = err as BusinessError;
    hilog.error(DOMAIN, TAG, 'open settings failed: %{public}d %{public}s', e.code, e.message);
    return undefined;
  }
}

/** 是否已经看过欢迎窗口（看过之后从桌面/任务栏启动不再弹窗）。 */
export function readWelcomeSeen(ctx: common.Context): boolean {
  const p: preferences.Preferences | undefined = store(ctx);
  if (p === undefined) {
    return false;
  }
  try {
    return p.getSync(KEY_WELCOME_SEEN, false) === true;
  } catch (err) {
    const e = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'read welcome flag failed: %{public}d %{public}s', e.code, e.message);
    return false;
  }
}

/** 记下"已看过"，落盘后即使下次窗口没关干净也不会再自动弹。 */
export function markWelcomeSeen(ctx: common.Context): void {
  const p: preferences.Preferences | undefined = store(ctx);
  if (p === undefined) {
    return;
  }
  try {
    p.putSync(KEY_WELCOME_SEEN, true);
    p.flush().catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'flush welcome flag failed: %{public}d %{public}s', err.code, err.message);
    });
  } catch (err) {
    const e = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'write welcome flag failed: %{public}d %{public}s', e.code, e.message);
  }
}

/** 组合以逗号串落盘（`"2072,2047,2017"` 前几个是修饰键、最后一个是主键）。 */
function encode(combo: HotkeyCombo): string {
  return combo.preKeys.concat([combo.finalKey]).join(',');
}

function decode(raw: string): HotkeyCombo {
  if (raw.length === 0) {
    return DEFAULT_HOTKEY;
  }
  const nums: number[] = [];
  for (const part of raw.split(',')) {
    const n: number = Number(part);
    if (!Number.isNaN(n) && n > 0) {
      nums.push(Math.trunc(n));
    }
  }
  if (nums.length < 2) {
    return DEFAULT_HOTKEY;
  }
  const combo: HotkeyCombo = {
    preKeys: nums.slice(0, nums.length - 1),
    finalKey: nums[nums.length - 1]
  };
  return isValidCombo(combo) ? combo : DEFAULT_HOTKEY;
}

export function readHotkey(ctx: common.Context): HotkeyCombo {
  const p: preferences.Preferences | undefined = store(ctx);
  if (p === undefined) {
    return DEFAULT_HOTKEY;
  }
  try {
    const value = p.getSync(KEY_HOTKEY, '');
    if (typeof value === 'string') {
      return decode(value);
    }
  } catch (err) {
    const e = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'read hotkey failed: %{public}d %{public}s', e.code, e.message);
  }
  return DEFAULT_HOTKEY;
}

/** 保存组合。常驻进程不读这个值（改键时直接用事件里的组合），它只服务于下次冷启动。 */
export function saveHotkey(ctx: common.Context, combo: HotkeyCombo): Promise<void> {
  const p: preferences.Preferences | undefined = store(ctx);
  if (p === undefined) {
    return Promise.resolve();
  }
  try {
    p.putSync(KEY_HOTKEY, encode(combo));
    return p.flush();
  } catch (err) {
    const e = err as BusinessError;
    hilog.error(DOMAIN, TAG, 'save hotkey failed: %{public}d %{public}s', e.code, e.message);
    return Promise.resolve();
  }
}
