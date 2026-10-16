import { common } from '@kit.AbilityKit';
import { CaptureFlow } from '../common/CaptureFlow';

/**
 * 入口页面：刻意不放任何界面元素。
 * 应用以"任务栏图标"的形式存在，被激活（onPageShow）就直接开始截图，
 * 用户全程只看到选区窗口和贴图窗口，看不到应用主窗口。
 * 另一条触发路径是全局快捷键（Ctrl+Shift+A），两条路共用 CaptureFlow。
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
