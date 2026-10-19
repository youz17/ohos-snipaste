import { screenshot } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'ScreenCapturer';

/**
 * 屏幕截图需要该权限。它属于 normal 级 + user_grant：
 * 普通应用声明后即可在运行时弹窗申请，无需申请华为 ACL 受限权限。
 */
const CAPTURE_PERMISSION: Permissions = 'ohos.permission.CUSTOM_SCREEN_CAPTURE';

export interface CaptureResult {
  pixelMap: image.PixelMap;
  width: number;
  height: number;
}

export class ScreenCapturer {
  /**
   * 只查授权状态，不弹窗；任何能拿到 accessTokenId 的 context 都可以调。
   *
   * 判"能不能直接截屏"必须用它：`requestPermissionsFromUser` 只能由**有窗口**的 UIAbility 发起，
   * 常驻的 `TrayAbility`（`STARTUP_HIDE`、无窗口）调它既不会弹窗也不会回调（实测卡死）。
   */
  static isGranted(context: common.UIAbilityContext): boolean {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const tokenId: number = context.applicationInfo.accessTokenId;
      return atManager.checkAccessTokenSync(tokenId, CAPTURE_PERMISSION) ===
        abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'checkAccessTokenSync failed: %{public}d %{public}s', e.code, e.message);
      return false;
    }
  }

  /**
   * 申请截图权限；**只允许在带窗口的 Ability 里调**（欢迎窗口的「去授权」）。
   * 已授权时不会弹窗，直接返回 true。
   */
  static async ensurePermission(context: common.UIAbilityContext): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    try {
      // 先查已有授权状态，避免"明明已授权却因为请求被拒而误判"
      if (ScreenCapturer.isGranted(context)) {
        hilog.info(DOMAIN, TAG, '%{public}s', 'CUSTOM_SCREEN_CAPTURE already granted');
        return true;
      }
      const result = await atManager.requestPermissionsFromUser(context, [CAPTURE_PERMISSION]);
      const granted = result.authResults.length > 0 && result.authResults[0] === 0;
      hilog.info(DOMAIN, TAG, 'CUSTOM_SCREEN_CAPTURE granted=%{public}s', String(granted));
      return granted;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'requestPermissionsFromUser failed: %{public}d %{public}s', e.code, e.message);
      return false;
    }
  }

  /**
   * 截取整屏。调用方必须先把自身窗口最小化，否则自己的窗口会被拍进截图。
   *
   * 实测（设备 3QC0124C20001630 / HarmonyOS 7.0.0.23）：
   * 带 CaptureOption 的调用即使只传 displayId + blackWindowIds 也返回 401，
   * 且紧接着的无参 capture() 会挂起不返回，因此这里固定使用无参形式。
   */
  static async captureScreen(): Promise<CaptureResult | undefined> {
    try {
      const pixelMap: image.PixelMap = await screenshot.capture();
      const info: image.ImageInfo = await pixelMap.getImageInfo();
      hilog.info(DOMAIN, TAG, 'capture ok: %{public}dx%{public}d', info.size.width, info.size.height);
      return { pixelMap: pixelMap, width: info.size.width, height: info.size.height };
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'screenshot.capture failed: %{public}d %{public}s', e.code, e.message);
      return undefined;
    }
  }

  /** 系统截图选择器：无需任何权限，由系统画出选区界面并返回选中区域。 */
  static async pickBySystem(): Promise<CaptureResult | undefined> {
    try {
      const picked: screenshot.PickInfo = await screenshot.pick();
      const info: image.ImageInfo = await picked.pixelMap.getImageInfo();
      hilog.info(DOMAIN, TAG, 'pick ok: %{public}dx%{public}d', info.size.width, info.size.height);
      return { pixelMap: picked.pixelMap, width: info.size.width, height: info.size.height };
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'screenshot.pick failed: %{public}d %{public}s', e.code, e.message);
      return undefined;
    }
  }
}
