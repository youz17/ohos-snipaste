import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PinPayload } from '../common/PinPayload';
import { PinStore } from '../common/PinStore';

const DOMAIN = 0x0000;
const TAG = 'PastePage';

/** 一张贴图窗口的内容：图片 + 复制/关闭 + 拖动窗口。 */
@Entry
@Component
struct PastePage {
  @State imagePath: string = '';
  @State copied: boolean = false;
  /** 图片是否已解码可用（用标志位驱动重绘，图片本体放在普通字段里） */
  @State hasPreview: boolean = false;

  private preview: image.PixelMap | undefined = undefined;
  private win: window.Window | undefined = undefined;
  private originX: number = 0;
  private originY: number = 0;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    window.getLastWindow(this.context()).then((win: window.Window) => {
      this.win = win;
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'getLastWindow failed: %{public}d %{public}s', err.code, err.message);
    });
    this.loadPreview();
  }

  /** 用本窗口 id 取回图片路径并解码（loadContent 传 LocalStorage 在页面里取不到值）。 */
  private async loadPreview(): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(this.context());
      const windowId: number = win.getWindowProperties().id;
      this.imagePath = PinPayload.load(windowId);
      hilog.info(DOMAIN, TAG, 'windowId=%{public}d imagePath len=%{public}d',
        windowId, this.imagePath.length);
      if (this.imagePath.length === 0) {
        return;
      }
      this.preview = await PinStore.decode(this.imagePath);
      this.hasPreview = true;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'load preview failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  /** 记住拖动前的窗口位置，后续用「起点 + 累计偏移」计算新位置。 */
  private rememberWindowOrigin(): void {
    if (this.win === undefined) {
      return;
    }
    const rect = this.win.getWindowProperties().windowRect;
    this.originX = rect.left;
    this.originY = rect.top;
  }

  private moveWindowBy(offsetX: number, offsetY: number): void {
    if (this.win === undefined) {
      return;
    }
    const x: number = this.originX + Math.round(this.getUIContext().vp2px(offsetX));
    const y: number = this.originY + Math.round(this.getUIContext().vp2px(offsetY));
    this.win.moveWindowTo(x, y).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'moveWindowTo failed: %{public}d %{public}s', err.code, err.message);
    });
  }

  private async copyToClipboard(): Promise<void> {
    if (this.preview === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '图片尚未就绪' });
      return;
    }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, this.preview);
      await pasteboard.getSystemPasteboard().setData(data);
      this.copied = true;
      this.getUIContext().getPromptAction().showToast({ message: '已复制到剪贴板' });
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'copy failed: %{public}d %{public}s', e.code, e.message);
      this.getUIContext().getPromptAction().showToast({ message: `复制失败：${e.message}` });
    }
  }

  private closeSelf(): void {
    this.context().terminateSelf();
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.hasPreview && this.preview !== undefined) {
        Image(this.preview)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
          .draggable(false)
          .interpolation(ImageInterpolation.High)
      }

      Row({ space: 8 }) {
        Button(this.copied ? '已复制' : '复制')
          .fontSize(12)
          .height(28)
          .onClick(() => {
            this.copyToClipboard();
          })
        Button('关闭')
          .fontSize(12)
          .height(28)
          .onClick(() => {
            this.closeSelf();
          })
      }
      .padding(6)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F2F2F2')
    .gesture(
      PanGesture()
        .onActionStart(() => {
          this.rememberWindowOrigin();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.moveWindowBy(event.offsetX, event.offsetY);
        })
    )
  }
}
