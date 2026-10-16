import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Launcher } from '../common/Launcher';
import { PinPayload } from '../common/PinPayload';
import { PinStore } from '../common/PinStore';
import { PinRegistry } from '../common/PinRegistry';
import { ImageShare } from '../common/ImageShare';
import { DiffResult, ImageDiff } from '../common/ImageDiff';

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
/** 操作条尺寸（vp）与它和选区边缘的间距：复制 / 保存 / 贴图 / 比较 / 取消 */
const TOOLBAR_W: number = 356;
const TOOLBAR_H: number = 36;
const TOOLBAR_GAP: number = 8;
/** 选区调整把手：边长与命中容差（vp） */
const HANDLE_SIZE: number = 8;
const HANDLE_HIT: number = 10;
/** 触摸意图 */
const MODE_IDLE: number = 0;
const MODE_CREATE: number = 1;
const MODE_MOVE: number = 2;
const MODE_RESIZE: number = 3;
/** 方向键 */
const KEY_DPAD_UP: number = 2012;
const KEY_DPAD_DOWN: number = 2013;
const KEY_DPAD_LEFT: number = 2014;
const KEY_DPAD_RIGHT: number = 2015;
const KEY_SHIFT_LEFT: number = 2047;
const KEY_SHIFT_RIGHT: number = 2048;
const KEY_ESCAPE: number = 2070;

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
  /** 当前触摸意图：新建 / 移动 / 调整大小 */
  private mode: number = MODE_IDLE;
  private activeHandle: number = -1;
  /** 按下瞬间的选区边界，移动与缩放都基于它算，避免逐帧累积误差 */
  private snapLeft: number = 0;
  private snapTop: number = 0;
  private snapRight: number = 0;
  private snapBottom: number = 0;
  private shiftDown: boolean = false;

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

  /** 8 个调整把手的位置 [left, top]：NW, N, NE, W, E, SW, S, SE */
  private handlePoints(): number[][] {
    const left: number = this.selLeft;
    const top: number = this.selTop;
    const right: number = this.selLeft + this.selWidth;
    const bottom: number = this.selTop + this.selHeight;
    const midX: number = (left + right) / 2;
    const midY: number = (top + bottom) / 2;
    return [
      [left, top], [midX, top], [right, top],
      [left, midY], [right, midY],
      [left, bottom], [midX, bottom], [right, bottom]
    ];
  }

  /** 命中哪个把手（-1 表示没命中） */
  private hitHandle(x: number, y: number): number {
    if (!this.hasSelection()) {
      return -1;
    }
    const points: number[][] = this.handlePoints();
    for (let i = 0; i < points.length; i++) {
      if (Math.abs(x - points[i][0]) <= HANDLE_HIT && Math.abs(y - points[i][1]) <= HANDLE_HIT) {
        return i;
      }
    }
    return -1;
  }

  /**
   * 按下：把手 → 调整大小；选区内 → 整体移动；选区外 → 重新框选。
   * 这三种意图让"框完还能继续微调"。
   */
  private beginTouch(x: number, y: number): void {
    const px: number = this.clamp(x, 0, this.winWidth);
    const py: number = this.clamp(y, 0, this.winHeight);
    this.cursorX = px;
    this.cursorY = py;
    this.startX = px;
    this.startY = py;
    this.dragging = true;
    const handle: number = this.hitHandle(px, py);
    if (handle >= 0) {
      this.mode = MODE_RESIZE;
      this.activeHandle = handle;
    } else if (this.hasSelection() && px >= this.selLeft && px <= this.selLeft + this.selWidth &&
      py >= this.selTop && py <= this.selTop + this.selHeight) {
      this.mode = MODE_MOVE;
    } else {
      this.mode = MODE_CREATE;
      this.selLeft = px;
      this.selTop = py;
      this.selWidth = 0;
      this.selHeight = 0;
    }
    this.snapLeft = this.selLeft;
    this.snapTop = this.selTop;
    this.snapRight = this.selLeft + this.selWidth;
    this.snapBottom = this.selTop + this.selHeight;
  }

  private updateTouch(x: number, y: number): void {
    const px: number = this.clamp(x, 0, this.winWidth);
    const py: number = this.clamp(y, 0, this.winHeight);
    this.cursorX = px;
    this.cursorY = py;
    if (this.mode === MODE_CREATE) {
      this.selLeft = Math.min(this.startX, px);
      this.selTop = Math.min(this.startY, py);
      this.selWidth = Math.abs(px - this.startX);
      this.selHeight = Math.abs(py - this.startY);
      return;
    }
    if (this.mode === MODE_MOVE) {
      this.selLeft = this.clamp(this.snapLeft + (px - this.startX), 0, Math.max(0, this.winWidth - this.selWidth));
      this.selTop = this.clamp(this.snapTop + (py - this.startY), 0, Math.max(0, this.winHeight - this.selHeight));
      return;
    }
    if (this.mode === MODE_RESIZE) {
      let left: number = this.snapLeft;
      let top: number = this.snapTop;
      let right: number = this.snapRight;
      let bottom: number = this.snapBottom;
      const h: number = this.activeHandle;
      if (h === 0 || h === 3 || h === 5) {
        left = this.clamp(px, 0, right - MIN_SELECTION);
      }
      if (h === 2 || h === 4 || h === 7) {
        right = this.clamp(px, left + MIN_SELECTION, this.winWidth);
      }
      if (h === 0 || h === 1 || h === 2) {
        top = this.clamp(py, 0, bottom - MIN_SELECTION);
      }
      if (h === 5 || h === 6 || h === 7) {
        bottom = this.clamp(py, top + MIN_SELECTION, this.winHeight);
      }
      this.selLeft = left;
      this.selTop = top;
      this.selWidth = right - left;
      this.selHeight = bottom - top;
    }
  }

  /** 1 个图片像素对应多少 vp，方向键按图片像素微调 */
  private stepVp(): number {
    return this.imageWidth > 0 ? this.winWidth / this.imageWidth : 1;
  }

  /** 方向键：默认平移选区，按住 Shift 调整右/下边界，步长都是 1 个截图像素。 */
  private handleKey(event: KeyEvent): void {
    const code: number = event.keyCode;
    if (code === KEY_SHIFT_LEFT || code === KEY_SHIFT_RIGHT) {
      this.shiftDown = event.type === KeyType.Down;
      return;
    }
    if (event.type !== KeyType.Down) {
      return;
    }
    if (code === KEY_ESCAPE) {
      this.cancel();
      return;
    }
    if (!this.hasSelection()) {
      return;
    }
    const d: number = this.stepVp();
    if (this.shiftDown) {
      if (code === KEY_DPAD_RIGHT || code === KEY_DPAD_LEFT) {
        const grow: number = code === KEY_DPAD_RIGHT ? d : -d;
        this.selWidth = this.clamp(this.selWidth + grow, MIN_SELECTION, this.winWidth - this.selLeft);
      } else if (code === KEY_DPAD_DOWN || code === KEY_DPAD_UP) {
        const grow: number = code === KEY_DPAD_DOWN ? d : -d;
        this.selHeight = this.clamp(this.selHeight + grow, MIN_SELECTION, this.winHeight - this.selTop);
      }
      return;
    }
    if (code === KEY_DPAD_LEFT) {
      this.selLeft = this.clamp(this.selLeft - d, 0, this.winWidth - this.selWidth);
    } else if (code === KEY_DPAD_RIGHT) {
      this.selLeft = this.clamp(this.selLeft + d, 0, this.winWidth - this.selWidth);
    } else if (code === KEY_DPAD_UP) {
      this.selTop = this.clamp(this.selTop - d, 0, this.winHeight - this.selHeight);
    } else if (code === KEY_DPAD_DOWN) {
      this.selTop = this.clamp(this.selTop + d, 0, this.winHeight - this.selHeight);
    }
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

  /** 常规复制：把选中的区域写进系统剪贴板。 */
  private async copySelection(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const pixelMap: image.PixelMap | undefined = await this.cropSelection();
      if (pixelMap === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '请先框选一块区域' });
        return;
      }
      await ImageShare.copyToClipboard(pixelMap);
      this.getUIContext().getPromptAction().showToast({ message: '已复制到剪贴板' });
      this.context().terminateSelf();
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'copy failed: %{public}d %{public}s', e.code, e.message);
      this.getUIContext().getPromptAction().showToast({ message: `复制失败：${e.message}` });
    } finally {
      this.busy = false;
    }
  }

  /** 常规保存：弹系统保存对话框写出 PNG。 */
  private async saveSelection(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const pixelMap: image.PixelMap | undefined = await this.cropSelection();
      if (pixelMap === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '请先框选一块区域' });
        return;
      }
      const uri: string = await ImageShare.saveAs(this.context(), pixelMap, ImageShare.suggestedName());
      if (uri.length === 0) {
        return;
      }
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      this.context().terminateSelf();
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'save failed: %{public}d %{public}s', e.code, e.message);
      this.getUIContext().getPromptAction().showToast({ message: `保存失败：${e.message}` });
    } finally {
      this.busy = false;
    }
  }

  /**
   * 与"上一张图片"（当前开着的最后一张贴图）比较：
   * 两张图各自以左上角为背景色、找第一个非背景像素作基点对齐，再逐像素比对，
   * 差异图作为新窗口展示。基准取自进程内登记，不扫沙箱目录。
   */
  private async compareWithPin(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const pixelMap: image.PixelMap | undefined = await this.cropSelection();
      if (pixelMap === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '请先框选一块区域' });
        return;
      }
      const pinPath: string = PinRegistry.latest();
      if (pinPath.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '还没有贴图可以比较' });
        return;
      }
      hilog.info(DOMAIN, TAG, 'compare with %{public}s (registry has %{public}d)',
        pinPath, PinRegistry.count());
      const reference: image.PixelMap = await PinStore.decode(pinPath);
      const result: DiffResult = await ImageDiff.compare(reference, pixelMap);
      await Launcher.pinPixelMap(this.context(), result.pixelMap, this.context().filesDir,
        result.width, result.height, result.summary);
      this.context().terminateSelf();
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'compare failed: %{public}d %{public}s', e.code, e.message);
      this.getUIContext().getPromptAction().showToast({ message: `比较失败：${e.message}` });
    } finally {
      this.busy = false;
    }
  }

  /** 尺寸标签：显示裁剪后的真实像素尺寸 */
  private sizeLabel(): string {
    const width: number = this.toPixelX(this.selWidth);
    const height: number = this.toPixelY(this.selHeight);
    return `${width} × ${height}`;
  }

  /** 操作条贴着选区右下角放，放不下就翻到选区内部/上方。 */
  private toolbarX(): number {
    const rightAligned: number = this.selLeft + this.selWidth - TOOLBAR_W;
    const maxX: number = Math.max(TOOLBAR_GAP, this.winWidth - TOOLBAR_W - TOOLBAR_GAP);
    return Math.min(Math.max(rightAligned, TOOLBAR_GAP), maxX);
  }

  private toolbarY(): number {
    const below: number = this.selTop + this.selHeight + TOOLBAR_GAP;
    if (below + TOOLBAR_H <= this.winHeight - TOOLBAR_GAP) {
      return below;
    }
    const inside: number = this.selTop + this.selHeight - TOOLBAR_H - TOOLBAR_GAP;
    if (inside >= TOOLBAR_GAP) {
      return inside;
    }
    return Math.min(this.selTop + TOOLBAR_GAP, Math.max(TOOLBAR_GAP, this.winHeight - TOOLBAR_H - TOOLBAR_GAP));
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
          this.beginTouch(touch.x, touch.y);
        } else if (event.type === TouchType.Move && this.dragging) {
          this.updateTouch(touch.x, touch.y);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.dragging = false;
          this.mode = MODE_IDLE;
          this.activeHandle = -1;
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

        // 8 个调整把手：拖角/边可以继续改范围，拖选区内部可以整体挪动
        ForEach(this.handlePoints(), (point: number[]) => {
          Column()
            .width(HANDLE_SIZE)
            .height(HANDLE_SIZE)
            .backgroundColor('#FFFFFF')
            .border({ width: 1, color: FRAME_COLOR })
            .position({ x: point[0] - HANDLE_SIZE / 2, y: point[1] - HANDLE_SIZE / 2 })
            .hitTestBehavior(HitTestMode.None)
        }, (point: number[]) => `${point[0]}_${point[1]}`)

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

        Row({ space: 6 }) {
          Button('复制')
            .fontSize(14)
            .height(TOOLBAR_H)
            .layoutWeight(1)
            .enabled(!this.busy)
            .onClick(() => {
              this.copySelection();
            })
          Button('保存')
            .fontSize(14)
            .height(TOOLBAR_H)
            .layoutWeight(1)
            .enabled(!this.busy)
            .onClick(() => {
              this.saveSelection();
            })
          Button('贴图')
            .fontSize(14)
            .height(TOOLBAR_H)
            .layoutWeight(1)
            .enabled(!this.busy)
            .onClick(() => {
              this.confirmPin();
            })
          Button('比较')
            .fontSize(14)
            .height(TOOLBAR_H)
            .layoutWeight(1)
            .enabled(!this.busy)
            .onClick(() => {
              this.compareWithPin();
            })
          Button('取消')
            .fontSize(14)
            .height(TOOLBAR_H)
            .layoutWeight(1)
            .backgroundColor('#666666')
            .onClick(() => {
              this.cancel();
            })
        }
        .width(TOOLBAR_W)
        .height(TOOLBAR_H)
        .position({ x: this.toolbarX(), y: this.toolbarY() })
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(MASK_COLOR)
          .hitTestBehavior(HitTestMode.None)

        Text('拖拽框选区域：拖角/边可继续调整，拖选区内部可整体移动，方向键微调，Shift+方向键改大小，Esc 退出')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#CC000000')
          .padding(8)
          .position({ x: Math.max(0, this.winWidth / 2 - 430), y: 40 })
          .hitTestBehavior(HitTestMode.None)

        Button('取消')
          .fontSize(14)
          .height(TOOLBAR_H)
          .backgroundColor('#666666')
          .position({ x: this.winWidth - 120, y: 36 })
          .onClick(() => {
            this.cancel();
          })
      }
    }
    .width('100%')
    .height('100%')
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((event: KeyEvent) => {
      this.handleKey(event);
    })
  }
}
