/**
 * 传给选区页 / 贴图页的数据（当前只有冻结截图的沙箱路径）。
 *
 * 为什么不用 LocalStorage：实测 windowStage.loadContent(url, storage) 之后，
 * 页面里的 @LocalStorageProp 读到的是空值（日志 imagePath len=0），因此改用
 * AppStorage + 窗口 id 作为 key —— 每个贴图窗口是独立的 Ability 实例，
 * 用它自己窗口的 id 取数据，天然不会串。图片像素尺寸在页面解码后自行获取。
 */
export class PinPayload {
  private static key(windowId: number): string {
    return `pin_payload_${windowId}`;
  }

  /** 在 Ability 的 onWindowStageCreate 里调用，key 用该窗口自己的 id。 */
  static save(windowId: number, imagePath: string): void {
    AppStorage.setOrCreate(PinPayload.key(windowId), imagePath);
  }

  /** 在页面的 aboutToAppear 里用同一个窗口 id 取回。 */
  static load(windowId: number): string {
    return AppStorage.get<string>(PinPayload.key(windowId)) ?? '';
  }
}
