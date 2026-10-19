import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DEFAULT_HOTKEY,
  HotkeyCombo,
  hotkeyLabel,
  isModifier,
  isValidCombo,
  keyLabel,
  readHotkey,
  saveHotkey
} from '../common/Hotkey';
import { ScreenCapturer } from '../common/ScreenCapturer';
import { HotkeyApplyResult, listenHotkeyResult, requestHotkeyChange } from '../tray/HotkeySignal';

const DOMAIN = 0x0000;
const TAG = 'Welcome';

/** 147 = KEYCODE_ESCAPE */
const KEY_ESCAPE: number = 2070;
/** 常驻进程没回结果时的兜底：此时设置已经落盘，下次启动会生效 */
const APPLY_TIMEOUT_MS: number = 3000;

/**
 * 首次启动的欢迎窗口（`EntryAbility` 的主窗口）。
 *
 * 只负责"说清楚这是什么 + 改全局快捷键"：不加载任何截图链路。
 * Esc 关闭；关闭后 EntryAbility 自己 `terminateSelf`，应用回到"只有托盘图标"的状态。
 */
@Entry
@Component
struct Welcome {
  @State private combo: HotkeyCombo = DEFAULT_HOTKEY;
  @State private capturing: boolean = false;
  @State private hint: string = '';
  @State private hintOk: boolean = false;
  @State private busy: boolean = false;
  @State private permissionGranted: boolean = false;

  /** 捕获过程中已按下的修饰键（不参与渲染，所以不做成 @State） */
  private pressed: number[] = [];
  /** 改键前的组合：常驻进程注册失败时回滚到它 */
  private previous: HotkeyCombo = DEFAULT_HOTKEY;
  /** 本次请求的组合 */
  private pending: HotkeyCombo = DEFAULT_HOTKEY;
  private resultTimer: number = -1;
  private alive: boolean = true;

  private ctx(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    this.combo = readHotkey(this.ctx());
    this.previous = this.combo;
    this.pending = this.combo;
    this.permissionGranted = ScreenCapturer.isGranted(this.ctx());
    listenHotkeyResult((result: HotkeyApplyResult) => {
      if (!this.alive) {
        return;
      }
      this.clearTimer();
      this.busy = false;
      if (result.ok) {
        this.combo = this.pending;
        this.previous = this.combo;
        this.note(`已生效：${hotkeyLabel(this.combo)}`, true);
        hilog.info(DOMAIN, TAG, 'hotkey applied: %{public}s', hotkeyLabel(this.combo));
        return;
      }
      // 常驻进程没能注册新组合（多半是被占用），内存与磁盘都回到旧组合
      this.combo = this.previous;
      saveHotkey(this.ctx(), this.combo);
      this.note(`该组合不可用（错误码 ${result.code}），已恢复 ${hotkeyLabel(this.combo)}`);
      hilog.warn(DOMAIN, TAG, 'hotkey apply failed: %{public}d', result.code);
    });
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.clearTimer();
  }

  private clearTimer(): void {
    if (this.resultTimer >= 0) {
      clearTimeout(this.resultTimer);
      this.resultTimer = -1;
    }
  }

  private exit(): void {
    this.ctx().terminateSelf().catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'terminateSelf failed: %{public}d %{public}s', err.code, err.message);
    });
  }

  /** 提示行：`ok` 为真时是"成功"，用绿色；其余（含错误、进行中）用琥珀色。 */
  private note(text: string, ok: boolean = false): void {
    this.hintOk = ok;
    this.hint = text;
  }

  private startCapture(): void {
    this.capturing = true;
    this.pressed = [];
    this.note('请按住 Ctrl / Shift / Alt 再按一个键（Esc 取消）');
  }

  private cancelCapture(): void {
    this.capturing = false;
    this.pressed = [];
    this.note('');
  }

  /** 组合落盘 → 通知常驻进程重新注册 → 等结果（成功才算生效）。 */
  private async applyCombo(combo: HotkeyCombo): Promise<void> {
    if (this.busy || !isValidCombo(combo)) {
      return;
    }
    this.busy = true;
    this.pending = combo;
    this.note(`正在应用 ${hotkeyLabel(combo)} …`);
    await saveHotkey(this.ctx(), combo);
    try {
      await requestHotkeyChange(combo.preKeys, combo.finalKey);
    } catch (err) {
      const e = err as BusinessError;
      this.busy = false;
      this.note(`通知常驻进程失败（${e.code}），快捷键未改变`);
      saveHotkey(this.ctx(), this.previous);
      return;
    }
    this.resultTimer = setTimeout(() => {
      this.resultTimer = -1;
      if (!this.alive) {
        return;
      }
      this.busy = false;
      this.combo = combo;
      this.previous = combo;
      this.note('常驻进程未回执，新快捷键将在下次启动时生效');
    }, APPLY_TIMEOUT_MS);
  }

  /** 申请截屏权限。必须在这里发起：本窗口是唯一带窗口的 UIAbility，常驻进程申请不会弹窗。 */
  private async askPermission(): Promise<void> {
    this.busy = true;
    const ok: boolean = await ScreenCapturer.ensurePermission(this.ctx());
    this.busy = false;
    this.permissionGranted = ok;
    this.note(ok ? '截屏权限已授予' : '未授予：截图会退化为系统截图选择器', ok);
  }

  private handleKey(event: KeyEvent): boolean {
    const code: number = event.keyCode;
    const down: boolean = event.type === KeyType.Down;
    if (this.capturing) {
      if (code === KEY_ESCAPE) {
        if (down) {
          this.cancelCapture();
          this.note('已取消修改');
        }
        return true;
      }
      if (isModifier(code)) {
        if (down) {
          if (this.pressed.indexOf(code) < 0) {
            this.pressed = this.pressed.concat([code]);
          }
        } else {
          this.pressed = this.pressed.filter((k: number) => k !== code);
        }
        return true;
      }
      if (!down) {
        return true;
      }
      if (this.pressed.length === 0) {
        this.note(`「${keyLabel(code)}」不带修饰键，全局快捷键必须带 Ctrl / Shift / Alt`);
        return true;
      }
      const combo: HotkeyCombo = { preKeys: this.pressed.slice(), finalKey: code };
      this.capturing = false;
      this.pressed = [];
      this.applyCombo(combo);
      return true;
    }
    if (down && code === KEY_ESCAPE) {
      this.exit();
      return true;
    }
    return false;
  }

  build() {
    Column() {
      // 名字
      Row({ space: 12 }) {
        Image($r('app.media.panel_icon'))
          .width(48)
          .height(48)
        Column({ space: 4 }) {
          Text('截图贴图')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1F2328')
          Text('Snipaste 式截图、贴图与图片对比')
            .fontSize(12)
            .fontColor('#6B7280')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 16 })

      Divider().color('#E5E7EB')

      // 快捷键：介绍 + 设置
      Column({ space: 8 }) {
        Text('全局快捷键')
          .fontSize(13)
          .fontColor('#6B7280')
          .width('100%')
        Row({ space: 10 }) {
          Text(hotkeyLabel(this.combo))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1F2328')
            .layoutWeight(1)
          Button(this.capturing ? '取消' : '修改')
            .type(ButtonType.Normal)
            .height(32)
            .fontSize(13)
            .fontColor(this.capturing ? '#6B7280' : Color.White)
            .backgroundColor(this.capturing ? '#E8EAED' : '#2563EB')
            .borderRadius(8)
            .enabled(!this.busy)
            .onClick(() => {
              if (this.busy) {
                return;
              }
              if (this.capturing) {
                this.cancelCapture();
              } else {
                this.startCapture();
              }
            })
        }
        .width('100%')

        if (this.hint.length > 0) {
          Text(this.hint)
            .fontSize(12)
            .fontColor(this.hintOk ? '#15803D' : '#B45309')
            .width('100%')
        }
        Text('在任何窗口下按下即开始截图：拖拽框选，然后在操作条上选 复制 / 保存 / 贴图 / 比较。')
          .fontSize(12)
          .fontColor('#4B5563')
          .width('100%')
          .lineHeight(18)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 14, bottom: 14 })

      Divider().color('#E5E7EB')

      // 截屏权限：授权后快捷键是"整屏冻结 + 自绘框选"，未授权只能退化到系统选择器
      Column({ space: 8 }) {
        Text('截屏权限')
          .fontSize(13)
          .fontColor('#6B7280')
          .width('100%')
        Row({ space: 10 }) {
          Text(this.permissionGranted ? '已授权：可直接整屏截图' : '未授权：只能走系统截图选择器')
            .fontSize(14)
            .fontColor(this.permissionGranted ? '#15803D' : '#B45309')
            .layoutWeight(1)
          Button(this.permissionGranted ? '已授权' : '去授权')
            .type(ButtonType.Normal)
            .height(32)
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor(this.permissionGranted ? '#9CA3AF' : '#2563EB')
            .borderRadius(8)
            .enabled(!this.permissionGranted && !this.busy)
            .onClick(() => {
              this.askPermission();
            })
        }
        .width('100%')

        Text('系统只允许"有窗口的应用"申请这个权限，所以必须在当前窗口里点一次「去授权」。')
          .fontSize(12)
          .fontColor('#4B5563')
          .width('100%')
          .lineHeight(18)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 14, bottom: 14 })

      Divider().color('#E5E7EB')

      // 对比功能
      Column({ space: 8 }) {
        Text('图片对比')
          .fontSize(13)
          .fontColor('#6B7280')
          .width('100%')
        Text('会把上一张贴图当作基准：再框选同一块区域点「比较」，两张图对齐后逐像素比对，' +
          '差异处标红，并给出差异像素数与差异区域。')
          .fontSize(12)
          .fontColor('#4B5563')
          .width('100%')
          .lineHeight(18)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 14, bottom: 14 })

      Divider().color('#E5E7EB')

      Text('按 Esc 关闭本窗口。本窗口只在首次启动时自动弹出，之后可在状态栏托盘图标 →「使用说明」重新打开。')
        .fontSize(12)
        .fontColor('#9CA3AF')
        .width('100%')
        .lineHeight(18)
        .margin({ top: 14 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 22, bottom: 22 })
    .backgroundColor('#F5F6F7')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent) => {
      this.handleKey(event);
    })
  }
}
