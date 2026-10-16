import { UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StatusBarViewExtensionAbility } from '@kit.DeskTopExtensionKit';

const DOMAIN = 0x0000;
const TAG = 'TrayExt';

/**
 * 状态栏托盘图标的左键面板。
 *
 * 两条实测约束：
 * - `module.json5` 里 `exported` 必须为 `true`，否则系统起不来这个扩展（只有 `no ability or uiextension`）；
 * - 本扩展跑在独立进程 `com.youz.ohsnipaste:statusBarView`，不与主进程共享 AppStorage。
 */
export default class TrayStatusBarExt extends StatusBarViewExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onSessionCreate');
    session.loadContent('pages/TrayPanel');
  }

  onSessionDestroy(session: UIExtensionContentSession): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onSessionDestroy');
  }
}
