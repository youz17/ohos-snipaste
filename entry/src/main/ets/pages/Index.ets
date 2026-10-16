import { common } from '@kit.AbilityKit';
import { CaptureFlow } from '../common/CaptureFlow';

/**
 * 空页面：主窗口必须有内容可绘制，否则系统的启动窗口（start window）不会消失。
 *
 * 它同时是触发点之一：窗口被激活/恢复显示时 onPageShow 会回调。
 * 冷启动那一次由 CaptureFlow 自己按时间跳过（"首次启动不截图，再点才截"），
 * 所以这里直接调用即可，不必判断。
 */
@Entry
@Component
struct Index {
  onPageShow(): void {
    CaptureFlow.run(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#01000000')
  }
}
