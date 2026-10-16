/**
 * 进程内登记"此刻屏幕上开着哪些贴图窗口"。
 *
 * 为什么不扫沙箱目录按文件名时间戳猜"最新一张"：目录里同时躺着
 * - 冻结整屏图 shot_*（每次截图都会写，最新的一张往往就是它）
 * - 已经关掉窗口的历史 pin_*
 * - 差异图 diff_*
 * 实测就猜错过一次：拿刚截的 3120x2080 整屏图当了比较基准。
 *
 * 进程内登记的是"真的开了窗口的图片"，与屏幕上所见一致；关窗即注销。
 * 同一应用的各个 Ability（Entry/Selection/Paste）在同一进程里，
 * 静态字段天然共享（日志里多个 Ability 的 pid 相同）。
 */
export class PinRegistry {
  private static pins: string[] = [];

  /** 打开一张贴图窗口时登记（重复登记会挪到末尾） */
  static add(path: string): void {
    if (path.length === 0) {
      return;
    }
    const index: number = PinRegistry.pins.indexOf(path);
    if (index >= 0) {
      PinRegistry.pins.splice(index, 1);
    }
    PinRegistry.pins.push(path);
  }

  /** 贴图窗口关闭时注销 */
  static remove(path: string): void {
    const index: number = PinRegistry.pins.indexOf(path);
    if (index >= 0) {
      PinRegistry.pins.splice(index, 1);
    }
  }

  /** 上一张图片（最后打开的那张贴图），没有则返回空串 */
  static latest(): string {
    return PinRegistry.pins.length > 0 ? PinRegistry.pins[PinRegistry.pins.length - 1] : '';
  }

  /** 当前开着的贴图数量 */
  static count(): number {
    return PinRegistry.pins.length;
  }
}
