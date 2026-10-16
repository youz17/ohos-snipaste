import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'ImageDiff';

/** 单通道色差超过该值即判为"非背景"/"有差异" */
const TOLERANCE: number = 16;
/** 差异图底图压暗系数 */
const BASE_DIM: number = 0.45;

export interface DiffResult {
  /** 差异可视化图：底图是当前截图压暗，差异像素标红 */
  pixelMap: image.PixelMap;
  width: number;
  height: number;
  /** 差异像素数 */
  diffCount: number;
  /** 参与比对的像素数（两图对齐后的重叠区域） */
  comparedCount: number;
  /** 当前图相对参考图的位移（对齐基点后） */
  offsetX: number;
  offsetY: number;
  refAnchorX: number;
  refAnchorY: number;
  curAnchorX: number;
  curAnchorY: number;
  /** 差异包围盒 [left, top, right, bottom]，无差异时为空数组 */
  box: number[];
  /** 一句话结论，给差异窗口显示 */
  summary: string;
}

interface Rgba {
  data: Uint8Array;
  width: number;
  height: number;
}

/**
 * 两张图对齐后逐像素比较。
 *
 * 对齐规则（按需求）：各自以**左上角像素**作为背景色，按行优先找到
 * **第一个非背景色的像素**作为基点，再把两个基点重合，然后在重叠区域内比对。
 * 这样即使两次截图的框选位置有几像素偏差，也能对上内容。
 */
export class ImageDiff {
  private static async readRgba(pixelMap: image.PixelMap): Promise<Rgba> {
    const info: image.ImageInfo = await pixelMap.getImageInfo();
    const width: number = info.size.width;
    const height: number = info.size.height;
    const buffer: ArrayBuffer = new ArrayBuffer(width * height * 4);
    await pixelMap.readPixelsToBuffer(buffer);
    return { data: new Uint8Array(buffer), width: width, height: height };
  }

  /** 取左上角为背景色，行优先找第一个非背景像素：[x, y, bgR, bgG, bgB] */
  private static findAnchor(img: Rgba): number[] {
    const d: Uint8Array = img.data;
    const bgR: number = d[0];
    const bgG: number = d[1];
    const bgB: number = d[2];
    for (let y = 0; y < img.height; y++) {
      for (let x = 0; x < img.width; x++) {
        const i: number = (y * img.width + x) * 4;
        if (Math.abs(d[i] - bgR) > TOLERANCE || Math.abs(d[i + 1] - bgG) > TOLERANCE ||
          Math.abs(d[i + 2] - bgB) > TOLERANCE) {
          return [x, y, bgR, bgG, bgB];
        }
      }
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'no non-background pixel, fallback to (0,0)');
    return [0, 0, bgR, bgG, bgB];
  }

  static async compare(refPixelMap: image.PixelMap, curPixelMap: image.PixelMap): Promise<DiffResult> {
    const ref: Rgba = await ImageDiff.readRgba(refPixelMap);
    const cur: Rgba = await ImageDiff.readRgba(curPixelMap);
    const anchorRef: number[] = ImageDiff.findAnchor(ref);
    const anchorCur: number[] = ImageDiff.findAnchor(cur);
    // 让两个基点重合：当前图相对参考图的位移
    const offsetX: number = anchorRef[0] - anchorCur[0];
    const offsetY: number = anchorRef[1] - anchorCur[1];
    hilog.info(DOMAIN, TAG,
      'ref %{public}dx%{public}d anchor(%{public}d,%{public}d) bg(%{public}d,%{public}d,%{public}d) | cur %{public}dx%{public}d anchor(%{public}d,%{public}d) | offset(%{public}d,%{public}d)',
      ref.width, ref.height, anchorRef[0], anchorRef[1], anchorRef[2], anchorRef[3], anchorRef[4],
      cur.width, cur.height, anchorCur[0], anchorCur[1], offsetX, offsetY);

    const out: Uint8Array = new Uint8Array(ref.width * ref.height * 4);
    // 底图：当前截图压暗（当前图没覆盖到的地方留黑）
    for (let y = 0; y < ref.height; y++) {
      for (let x = 0; x < ref.width; x++) {
        const i: number = (y * ref.width + x) * 4;
        const cx: number = x - offsetX;
        const cy: number = y - offsetY;
        if (cx >= 0 && cx < cur.width && cy >= 0 && cy < cur.height) {
          const j: number = (cy * cur.width + cx) * 4;
          out[i] = Math.round(cur.data[j] * BASE_DIM);
          out[i + 1] = Math.round(cur.data[j + 1] * BASE_DIM);
          out[i + 2] = Math.round(cur.data[j + 2] * BASE_DIM);
        } else {
          out[i] = 0;
          out[i + 1] = 0;
          out[i + 2] = 0;
        }
        out[i + 3] = 255;
      }
    }

    const left: number = Math.max(0, offsetX);
    const top: number = Math.max(0, offsetY);
    const right: number = Math.min(ref.width, cur.width + offsetX);
    const bottom: number = Math.min(ref.height, cur.height + offsetY);
    let diffCount: number = 0;
    let compared: number = 0;
    let boxLeft: number = ref.width;
    let boxTop: number = ref.height;
    let boxRight: number = -1;
    let boxBottom: number = -1;
    for (let y = top; y < bottom; y++) {
      for (let x = left; x < right; x++) {
        const i: number = (y * ref.width + x) * 4;
        const j: number = ((y - offsetY) * cur.width + (x - offsetX)) * 4;
        compared++;
        if (Math.abs(ref.data[i] - cur.data[j]) > TOLERANCE ||
          Math.abs(ref.data[i + 1] - cur.data[j + 1]) > TOLERANCE ||
          Math.abs(ref.data[i + 2] - cur.data[j + 2]) > TOLERANCE) {
          diffCount++;
          out[i] = 255;
          out[i + 1] = 40;
          out[i + 2] = 40;
          if (x < boxLeft) {
            boxLeft = x;
          }
          if (y < boxTop) {
            boxTop = y;
          }
          if (x > boxRight) {
            boxRight = x;
          }
          if (y > boxBottom) {
            boxBottom = y;
          }
        }
      }
    }

    const ratio: number = compared > 0 ? diffCount * 100 / compared : 0;
    const box: number[] = boxRight >= 0 ? [boxLeft, boxTop, boxRight + 1, boxBottom + 1] : [];
    let summary: string = `差异 ${diffCount} px / 比对 ${compared} px (${ratio.toFixed(2)}%)`;
    if (box.length === 4) {
      summary += ` · 区域 ${box[2] - box[0]}×${box[3] - box[1]} @(${box[0]},${box[1]})`;
    }
    summary += ` · 基点偏移 (${offsetX},${offsetY})`;
    hilog.info(DOMAIN, TAG, '%{public}s', summary);

    const pixelMap: image.PixelMap = await image.createPixelMap(out.buffer, {
      size: { width: ref.width, height: ref.height },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888
    });
    return {
      pixelMap: pixelMap,
      width: ref.width,
      height: ref.height,
      diffCount: diffCount,
      comparedCount: compared,
      offsetX: offsetX,
      offsetY: offsetY,
      refAnchorX: anchorRef[0],
      refAnchorY: anchorRef[1],
      curAnchorX: anchorCur[0],
      curAnchorY: anchorCur[1],
      box: box,
      summary: summary
    };
  }
}
