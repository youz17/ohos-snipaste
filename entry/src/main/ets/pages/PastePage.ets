import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PinPayload } from '../common/PinPayload';
import { PinStore } from '../common/PinStore';
import { PinRegistry } from '../common/PinRegistry';
import { ImageShare } from '../common/ImageShare';

const DOMAIN = 0x0000;
const TAG = 'PastePage';
/**
 * 近全透明：不能写 '#00000000'，ArkUI 会把它当作"未设置背景"，
 * 反而露出主题的窗口底色（实测是一层浅灰，会把圆角边距暴露出来）。
 * alpha=1/255 视觉上不可见，但会真正参与绘制。
 */
const NEARLY_TRANSPARENT: string = '#01000000';

/**
 * 贴图窗口内容：按原始像素 1:1 显示图片（窗口大小即图片大小）。
 * 界面上**不放任何按钮**——复制/保存/关闭都放在右键菜单里，
 * 以免按钮挡住图片；按住图片拖动可移动窗口。
 */
@Entry
@Component
struct PastePage {
  @State imagePath: string = '';
  /** 说明文字：差异窗口用来显示比较结论 */
  @State note: string = '';
  @State hasPreview: boolean = false;
  @State imgWidthPx: number = 0;
  @State imgHeightPx: number = 0;
  /** 窗口实际尺寸（vp），与图片尺寸不一致说明被系统最小窗口尺寸撑大了 */
  @State winW: number = 0;
  @State winH: number = 0;

  private preview: image.PixelMap | undefined = undefined;
  private win: window.Window | undefined = undefined;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    this.init();
  }

  /** 用本窗口 id 取回图片路径并解码（loadContent 传 LocalStorage 在页面里取不到值）。 */
  private async init(): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(this.context());
      this.win = win;
      const windowId: number = win.getWindowProperties().id;
      this.imagePath = PinPayload.load(windowId);
      this.note = PinPayload.loadNote(windowId);
      hilog.info(DOMAIN, TAG, 'windowId=%{public}d imagePath len=%{public}d note=%{public}s',
        windowId, this.imagePath.length, this.note);
      if (this.imagePath.length === 0) {
        return;
      }
      this.preview = await PinStore.decode(this.imagePath);
      const info: image.ImageInfo = await this.preview.getImageInfo();
      this.imgWidthPx = info.size.width;
      this.imgHeightPx = info.size.height;
      this.hasPreview = true;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'init failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  /**
   * 拖动窗口：交给系统窗口管理器（`window.startMoving`），窗口自己跟手。
   *
   * 早前这里是自己算的：`target = 上次目标 + (touch.windowX - 按下时 windowX)`，再串行发
   * `moveWindowTo`。那是个**积分器**，而 `moveWindowTo` 是异步生效的：每次事件都把"上一步
   * 还没追上的差值"再累加一遍，窗口于是越过光标、下一条事件又反向修正 —— 正反馈震荡，
   * 观感就是抖。实测真机同一手法拖 200px，窗口走了 365px（×1.83，见 docs/archive/HISTORY.md）。
   * `startMoving` 由窗口管理器直接接管光标跟随，没有这个环：实测拖 400px 窗口正好走 400px。
   *
   * 约束（SDK）：只有在本回调里、事件类型为 TouchType.Down 时调用，窗口才会跟随光标；
   * 偏移量单位 px，取按下点相对窗口左上角的位置，超出窗口范围会被判非法。
   */
  private startMovingWindow(touch: TouchObject): void {
    if (this.win === undefined) {
      return;
    }
    const offsetX: number = Math.round(this.getUIContext().vp2px(touch.x));
    const offsetY: number = Math.round(this.getUIContext().vp2px(touch.y));
    this.win.startMoving(offsetX, offsetY).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'startMoving failed: %{public}d %{public}s', err.code, err.message);
    });
  }

  private async copyToClipboard(): Promise<void> {
    if (this.preview === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '图片尚未就绪' });
      return;
    }
    try {
      await ImageShare.copyToClipboard(this.preview);
      this.getUIContext().getPromptAction().showToast({ message: '已复制到剪贴板' });
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'copy failed: %{public}d %{public}s', e.code, e.message);
      this.getUIContext().getPromptAction().showToast({ message: `复制失败：${e.message}` });
    }
  }

  private async saveToFile(): Promise<void> {
    if (this.preview === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '图片尚未就绪' });
      return;
    }
    try {
      const uri: string = await ImageShare.saveAs(this.context(), this.preview, ImageShare.suggestedName());
      if (uri.length > 0) {
        this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      }
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'save failed: %{public}d %{public}s', e.code, e.message);
      this.getUIContext().getPromptAction().showToast({ message: `保存失败：${e.message}` });
    }
  }

  private closeSelf(): void {
    PinRegistry.remove(this.imagePath);
    this.context().terminateSelf();
  }

  /** 右键菜单：贴图窗口上不放按钮，能力都收在这里。 */
  @Builder
  pinMenu() {
    Menu() {
      MenuItem({ content: '复制' })
        .onClick(() => {
          this.copyToClipboard();
        })
      MenuItem({ content: '保存为图片…' })
        .onClick(() => {
          this.saveToFile();
        })
      MenuItem({ content: '关闭' })
        .onClick(() => {
          this.closeSelf();
        })
    }
  }

  /**
   * 窗口被系统撑大了吗？系统对主窗口有最小尺寸限制（实测约 608x136 px），
   * 截图区域比它小时窗口会比图片大，按 1:1 画就会露出一圈灰底。
   */
  private isClamped(): boolean {
    if (this.winW <= 0 || this.winH <= 0) {
      return false;
    }
    return Math.abs(this.getUIContext().px2vp(this.imgWidthPx) - this.winW) > 2 ||
      Math.abs(this.getUIContext().px2vp(this.imgHeightPx) - this.winH) > 2;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 只在被撑大时可见：同一张图放大模糊铺底，避免平白多出一圈灰边
      if (this.hasPreview && this.preview !== undefined && this.isClamped()) {
        Image(this.preview)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(40)
          .draggable(false)
      }

      if (this.hasPreview && this.preview !== undefined) {
        // 显式按像素尺寸换算成 vp，保证 1 图片像素 = 1 屏幕像素
        Image(this.preview)
          .width(this.getUIContext().px2vp(this.imgWidthPx))
          .height(this.getUIContext().px2vp(this.imgHeightPx))
          .objectFit(ImageFit.Fill)
          .draggable(false)
          .interpolation(ImageInterpolation.None)
      }

      if (this.note.length > 0) {
        Text(this.note)
          .fontSize(12)
          .fontColor('#FFFFFF')
          .backgroundColor('#CC000000')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .maxLines(2)
          .position({ x: 4, y: 4 })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(NEARLY_TRANSPARENT)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.winW = typeof newArea.width === 'number' ? newArea.width : Number.parseFloat(`${newArea.width}`);
      this.winH = typeof newArea.height === 'number' ? newArea.height : Number.parseFloat(`${newArea.height}`);
    })
    .onTouch((event: TouchEvent) => {
      const touch: TouchObject = event.touches[0];
      if (touch === undefined) {
        return;
      }
      if (event.type === TouchType.Down) {
        this.startMovingWindow(touch);
      }
    })
    .bindContextMenu(this.pinMenu(), ResponseType.RightClick)
    .focusable(true)
  }
}
