import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Launcher } from '../common/Launcher';
import { PinPayload } from '../common/PinPayload';
import { PinStore } from '../common/PinStore';

const DOMAIN = 0x0000;
const TAG = 'SelectionPage';

/** 遮罩颜色：压暗未选中区域 */
const MASK_COLOR: string = '#66000000';
/** 选区边框颜色 */
const FRAME_COLOR: string = '#00A0FF';
/** 放大镜边长（vp）与放大倍率 */
const MAG_SIZE: number = 120;
const MAG_ZOOM: number = 4;
/** 小于该边长（vp）视为误触，不生成贴图 */
const MIN_SELECTION: number = 4;

/**
 * Snipaste 式区域选区：底图是截图那一刻冻结的屏幕画面，
 * 拖拽框选，带放大镜与像素尺寸，确认后裁剪成贴图。
 */
@Entry
@Component
struct SelectionPage {
  @State imagePath: string = '';
  @State imageWidth: number = 0;
  @State imageHeight: number = 0;

  @State winWidth: number = 0;
  @State winHeight: number = 0;
  @State selLeft: number = 0;
  @State selTop: number = 0;
  @State selWidth: number = 0;
  @State selHeight: number = 0;
  @State dragging: boolean = false;
  @State cursorX: number = 0;
  @State cursorY: number = 0;
  @State busy: boolean = false;
  /** 冻结画面是否已解码可用（用标志位驱动重绘，图片本体放在普通字段里） */
  @State hasPreview: boolean = false;

  private preview: image.PixelMap | undefined = undefined;
  private startX: number = 0;
  private startY: number = 0;

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    this.loadPreview();
  }

  /** 用本窗口 id 取回冻结截图路径并解码（loadContent 传 LocalStorage 在页面里取不到值）。 */
  private async loadPreview(): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(this.context());
      const windowId: number = win.getWindowProperties().id;
      this.imagePath = PinPayload.load(windowId);
      hilog.info(DOMAIN, TAG, 'windowId=%{public}d imagePath len=%{public}d "%{public}s"',
        windowId, this.imagePath.length, this.imagePath);
      if (this.imagePath.length === 0) {
        return;
      }
      this.preview = await PinStore.decode(this.imagePath);
      const info: image.ImageInfo = await this.preview.getImageInfo();
      this.imageWidth = info.size.width;
      this.imageHeight = info.size.height;
      this.hasPreview = true;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'load preview failed: %{public}d %{public}s', e.code, e.message);
    }
  }

  private toNumber(value: Length): number {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      return Number.parseFloat(value);
    }
    return 0;
  }

  private clamp(value: number, low: number, high: number): number {
    return Math.min(Math.max(value, low), high);
  }

  /** 窗口 vp → 图片像素的换算比例（两轴分别算，避免非等比拉伸时选错区域） */
  private toPixelX(vp: number): number {
    return this.winWidth > 0 ? Math.round(vp * this.imageWidth / this.winWidth) : 0;
  }

  private toPixelY(vp: number): number {
    return this.winHeight > 0 ? Math.round(vp * this.imageHeight / this.winHeight) : 0;
  }

  private hasSelection(): boolean {
    return this.selWidth >= MIN_SELECTION && this.selHeight >= MIN_SELECTION;
  }

  private beginSelection(x: number, y: number): void {
    this.startX = this.clamp(x, 0, this.winWidth);
    this.startY = this.clamp(y, 0, this.winHeight);
    this.dragging = true;
    this.selLeft = this.startX;
    this.selTop = this.startY;
    this.selWidth = 0;
    this.selHeight = 0;
    this.cursorX = this.startX;
    this.cursorY = this.startY;
  }

  private updateSelectionTo(curX: number, curY: number): void {
    const x: number = this.clamp(curX, 0, this.winWidth);
    const y: number = this.clamp(curY, 0, this.winHeight);
    this.selLeft = Math.min(this.startX, x);
    this.selTop = Math.min(this.startY, y);
    this.selWidth = Math.abs(x - this.startX);
    this.selHeight = Math.abs(y - this.startY);
    this.cursorX = x;
    this.cursorY = y;
  }

  /** 按选区裁剪冻结截图，返回裁剪后的 PixelMap。 */
  private async cropSelection(): Promise<image.PixelMap | undefined> {
    if (!this.hasSelection()) {
      return undefined;
    }
    const x: number = this.clamp(this.toPixelX(this.selLeft), 0, this.imageWidth - 1);
    const y: number = this.clamp(this.toPixelY(this.selTop), 0, this.imageHeight - 1);
    const width: number = this.clamp(this.toPixelX(this.selWidth), 1, this.imageWidth - x);
    const height: number = this.clamp(this.toPixelY(this.selHeight), 1, this.imageHeight - y);
    // 重新解码一份再裁剪：crop() 是原地修改，不能动正在显示的 preview
    const pixelMap: image.PixelMap = await PinStore.decode(this.imagePath);
    const region: image.Region = {
      x: x,
      y: y,
      size: {
        width: width,
        height: height
      }
    };
    await pixelMap.crop(region);
    hilog.info(DOMAIN, TAG, 'crop x=%{public}d y=%{public}d %{public}dx%{public}d', x, y, width, height);
    return pixelMap;
  }

  private async confirmPin(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const pixelMap: image.PixelMap | undefined = await this.cropSelection();
      if (pixelMap === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '请先拖拽框选一块区域' });
        return;
      }
      const info: image.ImageInfo = await pixelMap.getImageInfo();
      const ctx: common.UIAbilityContext = this.context();
      await Launcher.pinPixelMap(ctx, pixelMap, ctx.filesDir, info.size.width, info.size.height);
      ctx.terminateSelf();
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'confirmPin failed: %{public}d %{public}s', e.code, e.message);
      this.getUIContext().getPromptAction().showToast({ message: `贴图失败：${e.message}` });
    } finally {
      this.busy = false;
    }
  }

  private cancel(): void {
    this.context().terminateSelf();
  }

  /** 尺寸标签：显示裁剪后的真实像素尺寸 */
  private sizeLabel(): string {
    const width: number = this.toPixelX(this.selWidth);
    const height: number = this.toPixelY(this.selHeight);
    return `${width} × ${height}`;
  }

  @Builder
  magnifier() {
    Stack() {
      if (this.preview !== undefined) {
        Image(this.preview)
          .width(this.winWidth * MAG_ZOOM)
          .height(this.winHeight * MAG_ZOOM)
          .objectFit(ImageFit.Fill)
          .draggable(false)
          .translate({
            x: MAG_SIZE / 2 - this.cursorX * MAG_ZOOM,
            y: MAG_SIZE / 2 - this.cursorY * MAG_ZOOM
          })
      }
    }
    .width(MAG_SIZE)
    .height(MAG_SIZE)
    .clip(true)
    .border({ width: 1, color: '#FFFFFF' })
    .backgroundColor('#000000')
    .position({
      x: this.cursorX + MAG_SIZE + 24 <= this.winWidth ? this.cursorX + 24 : this.cursorX - MAG_SIZE - 24,
      y: this.cursorY + MAG_SIZE + 24 <= this.winHeight ? this.cursorY + 24 : this.cursorY - MAG_SIZE - 24
    })
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 互动层：冻结画面铺满窗口，并独占框选手势。
      // 所有覆盖层（遮罩/边框/标签/放大镜）都设为不吃事件，否则
      // 点工具栏按钮时父层的 Down 会先把选区重置成 0×0，按钮随即消失、click 不触发。
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.hasPreview && this.preview !== undefined) {
          Image(this.preview)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Fill)
            .draggable(false)
            .interpolation(ImageInterpolation.None)
        } else {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#101010')
        }
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.winWidth = this.toNumber(newArea.width);
        this.winHeight = this.toNumber(newArea.height);
      })
      // 用 onTouch 而不是 PanGesture：PanGesture 有约 5vp 的激活阈值，
      // 会让选区起点比实际按下点偏十几 vp，裁出来的区域和框选的不一致。
      .onTouch((event: TouchEvent) => {
        const touch: TouchObject = event.touches[0];
        if (touch === undefined) {
          return;
        }
        if (event.type === TouchType.Down) {
          this.beginSelection(touch.x, touch.y);
        } else if (event.type === TouchType.Move && this.dragging) {
          this.updateSelectionTo(touch.x, touch.y);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.dragging = false;
        }
      })

      if (this.hasSelection()) {
        // 遮罩：四条矩形围出选区。
        // 必须直接写在 build 里：@Builder 按值传参不具备刷新能力，
        // 用 @Builder 会把遮罩冻结在选区刚成形（4×4）时的尺寸，导致选区内部也被压暗。
        Column()
          .width(this.winWidth)
          .height(this.selTop)
          .backgroundColor(MASK_COLOR)
          .position({ x: 0, y: 0 })
          .hitTestBehavior(HitTestMode.None)
        Column()
          .width(this.winWidth)
          .height(this.winHeight - this.selTop - this.selHeight)
          .backgroundColor(MASK_COLOR)
          .position({ x: 0, y: this.selTop + this.selHeight })
          .hitTestBehavior(HitTestMode.None)
        Column()
          .width(this.selLeft)
          .height(this.selHeight)
          .backgroundColor(MASK_COLOR)
          .position({ x: 0, y: this.selTop })
          .hitTestBehavior(HitTestMode.None)
        Column()
          .width(this.winWidth - this.selLeft - this.selWidth)
          .height(this.selHeight)
          .backgroundColor(MASK_COLOR)
          .position({ x: this.selLeft + this.selWidth, y: this.selTop })
          .hitTestBehavior(HitTestMode.None)

        Column()
          .width(this.selWidth)
          .height(this.selHeight)
          .border({ width: 1, color: FRAME_COLOR })
          .position({ x: this.selLeft, y: this.selTop })
          .hitTestBehavior(HitTestMode.None)

        Text(this.sizeLabel())
          .fontSize(12)
          .fontColor('#FFFFFF')
          .backgroundColor('#CC000000')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .position({
            x: this.selLeft,
            y: this.selTop > 26 ? this.selTop - 24 : this.selTop + 4
          })
          .hitTestBehavior(HitTestMode.None)

        if (this.dragging) {
          this.magnifier()
        }

        Row({ space: 8 }) {
          Button(`贴图 ${this.sizeLabel()}`)
            .fontSize(14)
            .height(36)
            .enabled(!this.busy)
            .onClick(() => {
              this.confirmPin();
            })
          Button('取消')
            .fontSize(14)
            .height(36)
            .backgroundColor('#666666')
            .onClick(() => {
              this.cancel();
            })
        }
        .position({
          x: Math.max(0, this.winWidth / 2 - 110),
          y: Math.max(0, this.winHeight - 64)
        })
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(MASK_COLOR)
          .hitTestBehavior(HitTestMode.None)

        Text('拖拽框选区域，松开后点「贴图」')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#CC000000')
          .padding(8)
          .position({ x: Math.max(0, this.winWidth / 2 - 130), y: 40 })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
  }
}
