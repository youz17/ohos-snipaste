import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CaptureResult, ScreenCapturer } from '../common/ScreenCapturer';
import { Launcher } from '../common/Launcher';
import { PinStore } from '../common/PinStore';

const DOMAIN = 0x0000;
const TAG = 'Index';
/** 清空界面后等待重绘，再做截图 */
const BLANK_SETTLE_MS: number = 300;

@Entry
@Component
struct Index {
  @State status: string = '就绪';
  @State lastPinPath: string = '';
  @State busy: boolean = false;
  /** 截图期间置为 true：界面清空，窗口透明，自己才不会出现在截图里 */
  @State blank: boolean = false;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /**
   * 主链路：申请权限 → 自身窗口透明化 → 截整屏 → 还原窗口 →
   * 在冻结画面上框选 → 贴图。
   * 无权限或整屏截图失败时降级为系统截图选择器，直接得到已选区域。
   */
  private async captureAndPin(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    const ctx: common.UIAbilityContext = this.context();
    try {
      const granted: boolean = await ScreenCapturer.ensurePermission(ctx);
      if (granted) {
        this.status = '正在截图…';
        await this.hideSelfWindow(ctx);
        let shot: CaptureResult | undefined = undefined;
        try {
          shot = await ScreenCapturer.captureScreen();
        } finally {
          await this.showSelfWindow(ctx);
        }
        if (shot !== undefined) {
          const path: string = await PinStore.saveAsPng(shot.pixelMap, ctx.filesDir);
          this.status = '请在冻结画面上拖拽框选区域';
          await Launcher.openSelection(ctx, path, shot.width, shot.height);
          return;
        }
      }

      this.status = '改用系统截图选择器…';
      const picked: CaptureResult | undefined = await ScreenCapturer.pickBySystem();
      if (picked === undefined) {
        this.status = '截图失败或被取消';
        return;
      }
      this.lastPinPath = await Launcher.pinPixelMap(ctx, picked.pixelMap, ctx.filesDir,
        picked.width, picked.height);
      this.status = `已贴图 ${picked.width}×${picked.height}`;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'captureAndPin failed: %{public}d %{public}s', e.code, e.message);
      this.status = `出错：${e.code} ${e.message}`;
    } finally {
      this.busy = false;
    }
  }

  /**
   * 让自身窗口从屏幕上"消失"：清空页面内容、去掉窗口装饰、把窗口背景设为全透明。
   * 不使用 minimize()，因为最小化会让应用退到后台，而截图之后还要 startAbility
   * 打开选区窗口，后台启动需要 system_basic 级的权限（实测报 201），且
   * restore() 在最小化后返回 1300004 无法恢复。
   */
  private async hideSelfWindow(ctx: common.UIAbilityContext): Promise<void> {
    this.blank = true;
    try {
      const win: window.Window = await window.getLastWindow(ctx);
      win.setWindowDecorVisible(false);
      win.setWindowBackgroundColor('#00000000');
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'transparent self window failed: %{public}d %{public}s', e.code, e.message);
    }
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), BLANK_SETTLE_MS);
    });
  }

  /** 还原窗口外观。 */
  private async showSelfWindow(ctx: common.UIAbilityContext): Promise<void> {
    this.blank = false;
    try {
      const win: window.Window = await window.getLastWindow(ctx);
      win.setWindowBackgroundColor('#FFFFFF');
      win.setWindowDecorVisible(true);
      hilog.info(DOMAIN, TAG, '%{public}s', 'self window restored');
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'restore self window failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  @Builder
  mainPanel() {
    Column({ space: 16 }) {
      Text('截图贴图')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
      Text('Snipaste 风格：截取屏幕 → 框选区域 → 贴图置顶悬浮')
        .fontSize(14)
        .fontColor('#666666')

      Button(this.busy ? '处理中…' : '截取屏幕并贴图')
        .width('100%')
        .enabled(!this.busy)
        .onClick(() => {
          this.captureAndPin();
        })

      Text(this.status)
        .fontSize(14)
        .fontColor('#333333')
        .textAlign(TextAlign.Center)

      if (this.lastPinPath.length > 0) {
        Text(`最近贴图：${this.lastPinPath}`)
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      if (!this.blank) {
        this.mainPanel()
      }
    }
    .width('100%')
    .height('100%')
  }
}
