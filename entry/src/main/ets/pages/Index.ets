import { common } from '@kit.AbilityKit';

/**
 * 空页面。它的唯一作用是让主窗口有内容可绘制 ——
 * 系统的启动窗口（start window）要等窗口内容绘制完成才消失，
 * 不加载页面的话启动窗口会一直挂在屏幕上。
 *
 * 这里刻意不写任何 onPageShow 触发逻辑：截图由 EntryAbility.onCreate / onNewWant 触发，
 * 页面只负责"被画出来"（自身和窗口都是近全透明的）。
 */
@Entry
@Component
struct Index {
  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#01000000')
  }
}
