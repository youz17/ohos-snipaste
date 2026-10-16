import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { statusBarManager } from '@kit.DeskTopExtensionKit';

const DOMAIN = 0x0000;
const TAG = 'TrayEntry';

/** 左键面板的内容高度（vp）。宽度由系统决定（本机实测 361vp）。 */
const PANEL_HEIGHT_VP = 176;

/** 资源图 → PixelMap。状态栏只收 PixelMap，不收资源引用。 */
async function pixelMapOf(ctx: common.Context, resId: number): Promise<image.PixelMap> {
  const data: Uint8Array = await ctx.resourceManager.getMediaContent(resId);
  const src: image.ImageSource = image.createImageSource(data.buffer as ArrayBuffer);
  return await src.createPixelMap();
}

/**
 * 注册状态栏托盘图标；左键点击由 TrayStatusBarExt 弹出面板。
 *
 * `icons.white` 用于深色背景、`black` 用于浅色背景，两者必须是同一字形的两种颜色，
 * 所以线稿 SVG 已离屏光栅化成两份 PNG（见 SPEC-AND-TRUTH 3.3）。
 */
export async function registerTray(ctx: common.Context): Promise<void> {
  try {
    const white: image.PixelMap = await pixelMapOf(ctx, $r('app.media.tray_icon_white').id);
    const black: image.PixelMap = await pixelMapOf(ctx, $r('app.media.tray_icon_black').id);
    const item: statusBarManager.StatusBarItem = {
      icons: { white: white, black: black },
      quickOperation: {
        title: '截图贴图',
        height: PANEL_HEIGHT_VP,
        abilityName: 'TrayStatusBarExt',
        moduleName: 'entry'
      }
    };
    statusBarManager.addToStatusBar(ctx, item);
    hilog.info(DOMAIN, TAG, '%{public}s', 'tray icon registered');
  } catch (err) {
    const e = err as BusinessError;
    hilog.error(DOMAIN, TAG, 'registerTray failed: %{public}d %{public}s', e.code, e.message);
  }
}

/** 摘掉托盘图标。没有前台窗口时系统会拒绝（1010710004），属预期情况。 */
export function unregisterTray(ctx: common.Context): void {
  try {
    statusBarManager.removeFromStatusBar(ctx);
    hilog.info(DOMAIN, TAG, '%{public}s', 'tray icon removed');
  } catch (err) {
    const e = err as BusinessError;
    hilog.warn(DOMAIN, TAG, 'unregisterTray failed: %{public}d %{public}s', e.code, e.message);
  }
}
