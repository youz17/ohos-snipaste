# 架构（现行设计真值）

本文只写**此刻生效**的设计。平台能力边界（哪些 API 能用、权限等级、系统行为）在
[SPEC-AND-TRUTH.md](SPEC-AND-TRUTH.md)；未完成事项和待复核项在 [STATUS.md](STATUS.md)。
旧方案的取舍过程见 [archive/HISTORY.md](archive/HISTORY.md)。

## 为什么是这个形状

Snipaste 的核心是"整个屏幕都是画布，选中什么就贴什么"。鸿蒙上第三方应用拿不到系统级悬浮窗权限
（`SYSTEM_FLOAT_WINDOW` 是 system_basic，需 ACL 审批，见 SPEC-AND-TRUTH 2.2），所以本应用
不去抢系统悬浮窗，而是**先把整屏冻结成一张图**，再在普通窗口里自绘选区 —— 冻结画面不需要任何特权，
选区窗口就是一个全屏普通窗口。

## 三层 Ability

| Ability | 窗口形态 | 职责 |
| --- | --- | --- |
| `EntryAbility` | 主窗口**不可见**：去装饰 + 背景 `#01000000` + 去阴影，缩到系统最小尺寸（320x72vp）贴右下角后 `minimize()` | 入口与编排：接收激活事件，交给 `CaptureFlow` |
| `SelectionAbility` | 全屏、无装饰、去标题按钮，`setWindowLayoutFullScreen` + `maximize()` 之后 `setWindowTopmost(true)`（singleton） | 铺冻结画面，自绘遮罩 / 选区 / 8 个把手 / 放大镜 / 操作条 |
| `PasteAbility` | 每张图一个窗口，无装饰无阴影、`setWindowTopmost(true)`，尺寸 = 图片像素尺寸（multiton） | 显示贴图或差异图；拖动移动、右键菜单 |

入口页（`pages/Index.ets`）刻意没有任何界面元素，只有一层近全透明的 `Column`：它的存在是必须的
（不 `loadContent` 的话系统启动窗口不会消失，见 SPEC-AND-TRUTH 2.7），但用户全程只看到选区窗口和贴图窗口。

## 触发链路

三个入口都调 `CaptureFlow.run()`，由它自己判断该不该跑：

| 入口 | 何时 |
| --- | --- |
| `EntryAbility.onCreate` | 冷启动 |
| `EntryAbility.onNewWant` | 应用已在运行时再被激活（例如再点一次任务栏图标） |
| `Index.onPageShow` | 页面被显示/恢复时 |

```
CaptureFlow.run(ctx)
  ├─ 丢弃条件：距启动 < 3s（启动窗口还在，截进去就是那个大窗口）
  │             或 距上次 < 1.5s（onCreate/onNewWant/onPageShow 可能几毫秒内连着命中）
  │             或 busy（正在跑）
  ├─ ScreenCapturer.ensurePermission   先 checkAccessTokenSync 查已有授权，未授权才弹窗
  ├─ hideSelfWindow()                  win.minimize()，把主窗口收走
  ├─ ScreenCapturer.captureScreen()    无参 screenshot.capture() → 3120x2080 PixelMap
  ├─ PinStore.saveAsPng(pm, filesDir, 'shot')   → files/shot_<ts>.png
  ├─ Launcher.openSelection(path, w, h)         → startAbility(SelectionAbility)
  └─ hideSelfWindow()                  选区窗口已在前台，再收一次主窗口
未授权 / 截图失败 → pickAndPin：screenshot.pick() 系统选择器 → 直接贴出
```

顺序有硬约束：**必须先申请权限再收窗口** —— 反过来的话应用已进后台，权限请求会被直接拒掉
（权限申请与窗口状态的交互记录见 SPEC-AND-TRUTH 1.4）。

## 数据流

```
SelectionPage（全屏）
  └─ 用**本窗口 id** 从 AppStorage 取回图片路径（PinPayload）
  └─ PinStore.decode(path) → Image 铺满窗口 = 冻结画面
  └─ onTouch 状态机：把手→缩放(3) / 选区内→整体移动(2) / 选区外→新建(1)
  └─ 方向键平移、Shift+方向键改右/下边界（步长 = 1 个截图像素）、Esc 取消
  └─ 操作条（贴选区右下角，放不下翻内部/上方）：复制 / 保存 / 贴图 / 比较 / 取消
       └─ 四个出口都要先 cropSelection()：重新 decode 一份再 crop（crop 是原地修改）

PasteAbility（每张图一个）
  └─ 同样用窗口 id 取回路径 + 备注文字（note 给差异窗口显示结论）
  └─ 窗口尺寸 = min(图片像素尺寸, 屏幕尺寸)，页面按 px2vp 反算 1:1 显示
  └─ 右键菜单：复制 / 保存为图片… / 关闭（关闭时 PinRegistry.remove）
```

### 为什么用「窗口 id + AppStorage」传数据

`windowStage.loadContent(url, storage)` 传进去的 LocalStorage，页面里的 `@LocalStorageProp`
实测读到空值（`imagePath len=0`）。改用 AppStorage、以**该窗口自己的 id** 作 key（`PinPayload`）：
每个贴图窗口是独立 Ability 实例，各取各的，天然不会串。图片像素尺寸由页面解码后自取。

### 为什么图片要落盘再传

贴图窗口是独立 Ability，可能与本页不同进程，用文件路径传递比传内存对象可靠。
`PinStore.decode` 用 `fileIo` 打开 fd 再 `image.createImageSource(fd)`，不把路径直接交给 `Image()`；
解码固定 `RGBA_8888`，因为图片比较要按 4 字节/像素直接读像素缓冲。

文件前缀有语义：

| 前缀 | 含义 | 是否参与"上一张图片"（比较基准） |
| --- | --- | --- |
| `shot_` | 冻结整屏图 | 否 |
| `pin_` | 贴图 | 是 |
| `diff_` | 比较结果图 | 否 |

## 截图

`ScreenCapturer.captureScreen()` 固定用**无参** `screenshot.capture()`（带 `CaptureOption` 会返回
`401`，且随后无参调用会挂起，见 SPEC-AND-TRUTH 1.2）。

自身窗口不进截图的现状：主窗口本来就是不可见的（去装饰 + `#01000000` + 去阴影 + 缩到最小贴右下角），
截图前再 `hideSelfWindow()`（`win.minimize()`）收一次。

> ⚠️ 与早期实测记录的冲突：早前记录称"先最小化自身窗口再截图会让应用进后台，随后 `startAbility`
> 报 `201`（缺 `START_ABILITIES_FROM_BACKGROUND`），且 `restore()` 返回 `1300004` 无法恢复"，
> 而现行代码顺序正是"先收窗口"，两者尚未对齐。登记在 [STATUS.md](STATUS.md) 待复核第 1 条，
> 在真机复跑前不要引用任何一边当结论。

未授权或截图失败时走降级：`screenshot.pick()` 让系统画选区，拿到 PixelMap 后直接 `pinPixelMap` 贴出。

## 选区窗口的交互约定

- 用 `onTouch` 而不是 `PanGesture`：后者有约 5vp 激活阈值，会让选区起点偏离按下点。
- 选区一旦成形（≥ 4vp）就常驻 8 个把手、尺寸标签和操作条；无选区时显示一行操作提示 + 一个「取消」。
- 遮罩由四块矩形围出（上/下/左/右），必须直接写在 `build()` 里，不能用 `@Builder`。
- 所有覆盖层（遮罩、边框、把手、标签、放大镜）都要 `hitTestBehavior(HitTestMode.None)`，否则点操作条时
  父层 Down 会把选区重置成 0x0，按钮消失、click 不触发。

## 图片比较（`common/ImageDiff.ets`）

按需求实现的算法：

1. 各自取**左上角像素**作为背景色。
2. 按行优先扫描，找到**第一个与背景色不同的像素**作为基点（单通道色差 > 16）。
3. 把两个基点重合，得到当前图相对参考图的位移 `offset`。
4. 在重叠区域内逐像素比对，记录差异像素数、占比、包围盒。
5. 差异图：底图 = 当前截图压暗 45%，差异像素标红；窗口左上角显示一行结论（`note`）。

比对基准取自 `common/PinRegistry.ets`（**进程内**登记当前开着窗口的贴图路径，关窗即注销），
不扫沙箱目录 —— 目录里同时有 `shot_*` / 历史 `pin_*` / `diff_*`，按文件名时间戳猜会猜错。

已知弱点：基点是"**第一个**非背景像素"，可能是随裁剪位置漂移的边框而非稳定特征，框选位置变化后
对齐会失准（实测偏移 +20px 时报出 39% 差异）。候选改进见 SPEC-AND-TRUTH 候选 3。

## 权限

本项目声明三个权限（`entry/src/main/module.json5`）：`CUSTOM_SCREEN_CAPTURE`（截图）、
`WINDOW_TOPMOST`（贴图置顶）、`SET_WINDOW_TRANSPARENT`（去阴影）。等级、授权方式与证据见
[SPEC-AND-TRUTH.md](SPEC-AND-TRUTH.md) 第 4 节。刻意不申请 `SYSTEM_FLOAT_WINDOW`（system_basic，需 ACL）。

## 实现雷区（实测，改代码前必读）

| 雷区 | 正确做法 |
| --- | --- |
| `loadContent(url, storage)` 的 LocalStorage 在页面里取不到值 | 用 AppStorage + **本窗口 id** 作 key（`common/PinPayload.ets`） |
| `@Builder` 按值传参不具备刷新能力 | 会随选区变化的覆盖层直接写进 `build()`（遮罩四块） |
| `PanGesture` 约 5vp 激活阈值 | 选区用 `onTouch`，并给覆盖层加 `HitTestMode.None` |
| `touch.screenX/screenY` 不是屏幕绝对坐标（实测等于 `windowX/windowY`） | 拖窗用窗口内位移做闭环：`target = 已发送位置 + (当前窗口内坐标 - 按下时窗口内坐标)` |
| 同时发多个 `moveWindowTo` 会互相竞争 | 移动请求串行 + 合并（`pendingX/sentX/moveInFlight`） |
| 图片用沙箱路径交给 `Image()` 可能不显示 | `fileIo` 打开 fd → `image.createImageSource(fd)`，解码要 `RGBA_8888` |
| `bundleName` 不要硬编码 | 用 `context.abilityInfo.bundleName` |
| 贴图窗口 ZOrd 比选区高，会挡住操作条 | 选区窗口在 `maximize()` **之后**再 `setWindowTopmost(true)` |
| 系统对主窗口有最小尺寸（约 608x136 px） | 贴图页用同图放大模糊铺底填补（`ImageFit.Cover` + `blur(40)`） |
| `resize` 收 vp、`moveWindowTo` 收 px | 换算时显式乘 `densityPixels`（`entryability/EntryAbility.ets`） |
| 启动窗口相关 | 必须 `loadContent`；`startWindowIcon` 是 schema 必填；底色见 SPEC-AND-TRUTH 2.7 |
