# 架构（现行设计真值）

本文只写**此刻生效**的设计。平台能力边界（哪些 API 能用、权限等级、系统行为）在
[SPEC-AND-TRUTH.md](SPEC-AND-TRUTH.md)；未完成事项和待复核项在 [STATUS.md](STATUS.md)。
旧方案的取舍过程见 [archive/HISTORY.md](archive/HISTORY.md)。

## 为什么是这个形状

Snipaste 的核心是"整个屏幕都是画布，选中什么就贴什么"。鸿蒙上第三方应用拿不到系统级悬浮窗权限
（`SYSTEM_FLOAT_WINDOW` 是 system_basic，需 ACL 审批，见 SPEC-AND-TRUTH 2.2），所以本应用
不去抢系统悬浮窗，而是**先把整屏冻结成一张图**，再在普通窗口里自绘选区 —— 冻结画面不需要任何特权，
选区窗口就是一个全屏普通窗口。

## Ability 与扩展

| Ability / 扩展 | 窗口形态 | 职责 |
| --- | --- | --- |
| `EntryAbility` | 只借系统的启动窗口，**不加载任何内容**；引导结束即 `terminateSelf` | 引导：注册托盘图标 → 拉起 `TrayAbility` → 确认它起来后退出。之后应用**没有任何窗口**，任务栏也就不占位 |
| `TrayAbility` | **没有窗口**：`STARTUP_HIDE` 挂到状态栏项上、**不 `loadContent`**，跑在独立进程 `...:entry:TrayAbility:0` | 常驻载体：托盘图标活在这个进程里；订阅跨进程信号（`tray/CaptureSignal.ets`）跑 `CaptureFlow` |
| `SelectionAbility` | 全屏、无装饰、去标题按钮，`setWindowLayoutFullScreen` + `maximize()` 之后 `setWindowTopmost(true)`（singleton） | 铺冻结画面，自绘遮罩 / 选区 / 8 个把手 / 放大镜 / 操作条 |
| `PasteAbility` | 每张图一个窗口，无装饰无阴影、`setWindowTopmost(true)`，尺寸 = 图片像素尺寸（multiton） | 显示贴图或差异图；拖动移动、方向键微调、右键菜单 |
| `TrayStatusBarExt`（`type: statusBarView`，`exported: true`） | 无独立窗口；左键面板由 sceneboard 承载（页面 `pages/TrayPanel.ets`），跑在独立进程 `:statusBarView` | 托盘图标的左键面板：开始截图 / 退出 |

入口页（`pages/Index.ets`）已删除：两个 Ability 都不需要承载内容 —— `EntryAbility` 引导完就退出，
`TrayAbility` 是 `STARTUP_HIDE` 挂载且永不显示窗口的常驻进程。用户全程只看到选区窗口和贴图窗口。

## 触发链路

只有一个入口：托盘面板的「开始截图」→ **跨进程信号**（`commonEventManager` 自定义事件，
`tray/CaptureSignal.ets`）→ 常驻进程 `TrayAbility` 的订阅回调 → `CaptureFlow.run()`。

信号而不是 `startAbility`：**任何** ability 启动都会把常驻 Ability 的场景容器重新激活成前台，
应用立刻在任务栏冒出一个带运行点的图标，而且窗口再隐藏它也不消失（`STARTUP_HIDE` 与
`ProcessMode.ATTACH_TO_STATUS_BAR_ITEM` 都拦不住，实测）。因此引导之后**再也不启动 any ability**。

```
CaptureFlow.run(ctx)
  ├─ 丢弃条件：距启动 < 3s（启动窗口还在，截进去就是那个大窗口）
  │             或 距上次 < 1.5s
  │             或 busy（正在跑）
  ├─ ScreenCapturer.ensurePermission   先 checkAccessTokenSync 查已有授权，未授权才弹窗
  ├─ hideSelfWindow()                  win.minimize()，兜底收走自身窗口（本 Ability 没有窗口）
  ├─ ScreenCapturer.captureScreen()    无参 screenshot.capture() → 3120x2080 PixelMap
  ├─ PinStore.saveAsPng(pm, filesDir, 'shot')   → files/shot_<ts>.png
  ├─ Launcher.openSelection(path, w, h)         → startAbility(SelectionAbility)
  └─ hideSelfWindow()                  选区窗口已在前台，再收一次
未授权 / 截图失败 → pickAndPin：screenshot.pick() 系统选择器 → 直接贴出
```

顺序有硬约束：**必须先申请权限再收窗口** —— 反过来的话应用已进后台，权限请求会被直接拒掉
（权限申请与窗口状态的交互记录见 SPEC-AND-TRUTH 1.4）。

面板按「开始截图」到真正截图之间有 `PANEL_SETTLE_MS = 500`（`tray/TrayAbility.ets`）：面板是
sceneboard 的窗口，要等它收走才不会进冻结画面。

## 状态栏托盘入口

常驻入口不靠全局快捷键（平台不给），而是状态栏折叠区里的自绘图标。图标由**挂在状态栏项上的常驻进程**持有，
所以应用可以没有任何窗口 —— 任务栏也就不占位（这一点改写了 SPEC-AND-TRUTH 3.1 的旧结论）。

```
引导（只在冷启动跑一次）
  EntryAbility.onCreate → registerTray(ctx)
    ├─ app.media.tray_icon_white / _black → PixelMap（image 模块不解 SVG，这两个是离屏光栅化好的 PNG）
    └─ statusBarManager.addToStatusBar(ctx, item)，item.quickOperation → TrayStatusBarExt
  → startAbility(TrayAbility, {processMode: NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM,
                               startupVisibility: STARTUP_HIDE})       ← 有界重试，首次常报 16000067
  → 轮询 files/tray-ready（TrayAbility 窗口起来后落下的握手文件）
  → terminateSelf()      主窗口随之消失；此时 AMS 才认账，不会把应用当"最后一个 ability 退出"而杀掉

运行期（`startAbility` 只出现在引导里，运行期一次都没有）
  左键点图标 → sceneboard 拉起 TrayStatusBarExt（独立进程 com.youz.ohsnipaste:statusBarView）
    └─ onSessionCreate → session.loadContent('pages/TrayPanel')
         ├─ 开始截图 → publish('com.youz.ohsnipaste.action.CAPTURE')
         │              → 常驻进程 CaptureSignal 订阅回调 → TrayAbility.capture() → CaptureFlow
         └─ 退出     → removeFromStatusBar + ApplicationContext.killAllProcesses(true)
```

图标是**离屏光栅化**产物：`image` 模块不支持 SVG 解码，所以 `screenshot-icon-line.svg` 用无头 Chrome
渲染成 48×48 的黑/白两份（`media/tray_icon_black.png`、`media/tray_icon_white.png`，`icons.white`
对应深色背景、`black` 对应浅色背景）；彩色的 `screenshot-icon.svg` 渲染成 `media/panel_icon.png`
（128×128）给面板当徽标，并拆成背景/前景两层重绘应用的分层图标
（`AppScope` 与 `entry` 各一份 `background.png` / `foreground.png`，1024×1024）。

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
  └─ 方向键：窗口位置 ±1px（`nudge`，基准取真实位置；拖到屏幕外会被夹在屏幕内）
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
| 拖动无装饰贴图窗口别自己算 | 在 `onTouch` 的 `TouchType.Down` 里调 `win.startMoving(vp2px(touch.x), vp2px(touch.y))`，由窗口管理器接管光标跟随（`pages/PastePage.ets`）。自己用 `moveWindowTo` 做增量闭环会因异步延迟正反馈震荡 → 抖，见 [SPEC-AND-TRUTH.md](SPEC-AND-TRUTH.md) 2.8 |
| 方向键微调贴图位置别每次回读 `windowRect` | `moveWindowTo` 异步生效，连按方向键时回读到的是旧位置，几步会并成一步。做法（`pages/PastePage.ets` 的 `nudge`）：没有在途移动时才回读真实矩形当基准，有在途移动就按"上次目标 + 本次增量"累加；移动失败则把基准作废、下次重新回读 |
| `TouchObject` 的 `screenX/screenY` 已废弃（since 10，等于 `windowX/windowY`，窗口相对） | 窗口内位置用 `x/y` 或 `windowX/windowY`，屏幕绝对位置用 `displayX/displayY` —— **都是 vp** |
| 图片用沙箱路径交给 `Image()` 可能不显示 | `fileIo` 打开 fd → `image.createImageSource(fd)`，解码要 `RGBA_8888` |
| `bundleName` 不要硬编码 | 用 `context.abilityInfo.bundleName` |
| 贴图窗口 ZOrd 比选区高，会挡住操作条 | 选区窗口在 `maximize()` **之后**再 `setWindowTopmost(true)` |
| 系统对主窗口有最小尺寸（约 608x136 px） | 贴图页用同图放大模糊铺底填补（`ImageFit.Cover` + `blur(40)`） |
| `resize` 收 vp、`moveWindowTo` 收 px | 换算时显式乘 `densityPixels`（`entryability/EntryAbility.ets`） |
| 启动窗口相关 | 必须 `loadContent`；`startWindowIcon` 是 schema 必填；底色见 SPEC-AND-TRUTH 2.7 |
| `statusBarView` 扩展的 `exported` | 官方示例写 `true`，本项目保持一致；但本机实测 `false` 时 sceneboard 照样能拉起该扩展，"必须 true"不成立（见 SPEC-AND-TRUTH 第 5 节墓地） |
| `image` 模块解不了 SVG | 图形资源先离屏光栅化成 PNG 再打进包（`media/tray_icon_*.png`、`media/panel_icon.png`、分层图标 `background/foreground.png`） |
| 托盘面板是 UIExtension，冷启动约 2.4s | 面板要等 sceneboard 拉起 `:statusBarView` 进程才出现，验证时抢拍要等 ≥3s |
| 左键面板取消不掉 | `StatusBarItem.quickOperation` 是**必填**，且实现里 `height <= 0` 直接抛 `401`；系统最小约 106vp。别指望"点一下不出面板" |
| 面板还开着时截图，面板会进冻结画面 | 面板是 sceneboard 的窗口，不算"自身窗口"、不会被排除。现行做法是收到信号后先等 `PANEL_SETTLE_MS = 500` 再 `CaptureFlow`；实测该等待真的生效（触发 → `CUSTOM_SCREEN_CAPTURE already granted` 间隔 ≈ 504ms），冻结图里没有面板 |
| 用 `startAbility` 唤醒挂载的常驻 Ability | 会重新激活它的场景容器 → 应用**立刻在任务栏冒出图标，且窗口隐藏后也不消失**（`STARTUP_HIDE`、`ProcessMode.ATTACH_TO_STATUS_BAR_ITEM` 都拦不住）。运行期改用同应用自定义公共事件（`tray/CaptureSignal.ets`），启动 ability 只留给引导 |
| 常驻 Ability 的窗口内容 | 不需要：它 `STARTUP_HIDE` 挂载、之后永不被 `startAbility` 唤醒，因此不 `loadContent` 也不会留下启动窗口（实测 WMS 里没有它的窗口记录）。原 `pages/Index.ets` 已删除 |
| 想用 `terminateSelf()` 把面板收掉 | 面板会话会被 sceneboard 重建一次（实测 `onSessionDestroy` → 73ms 后 `onSessionCreate`），重建出来的会话不可见、也不会再次触发截图。早前记的"每 ~65ms 一个新进程、截图被反复触发"未复现 |
| `statusBarManager.on('statusBarIconClick')` 本机不派发 | 四种配置（普通 / 非导出扩展 / 已挂载进程 / 面板起不来）都没有回调。别把它当触发手段（见 SPEC-AND-TRUTH 3.3） |
| 挂载进程（`NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM`）首次启动报 `16000067` | 校验查的是服务侧 `CreateTrayForApp` 填的 (accessTokenId, instanceKey) 集合，而 `addToStatusBar` 只是投递就返回。要有界重试（`EntryAbility.attachTrayAbility`，实测第 2 次成功） |
| 挂载进程还没起来就 `terminateSelf` | AMS 判定"最后一个 ability 退出"→ `ProcessMgr: Terminate last` 把**整个应用**杀掉（含已挂载进程，托盘图标一起没）。必须先等到握手文件 `files/tray-ready` |
| `fs.accessSync(path)` 返回 boolean | 它**不抛异常**。写成 try/catch 判断存在性会恒真、握手直接失效（本项目踩过一次） |
| 托盘图标尺寸 | 实现里 `STANDARD_SIZE = 24`（vp），即应为 `vp2px(24)`；尺寸不符只记一条 `The size of the pixelmap exceeds the limit`，不拦注册 |
