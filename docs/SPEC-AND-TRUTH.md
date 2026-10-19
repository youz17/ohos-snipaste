# 平台能力真值与证伪墓地

本文记录**外部世界**（HarmonyOS 平台 / SDK）的现行有效结论。本应用自身的内部设计
（三层 Ability、数据流、算法、代码写法雷区）在 [ARCHITECTURE.md](ARCHITECTURE.md)，不在本文。

**就地覆写**：有新的实测结论就直接改写对应条目，不保留"早先是 A 后来改成 B"的叙事；
被推翻的假说登记到文末的证伪墓地。

证据等级（判据优先级见 [README.md](../README.md)）：

- **实测** —— 在本机真机（设备/系统基线见 [STATUS.md](STATUS.md)）上取得的日志、窗口 dump 或像素证据。
- **SDK** —— 本机 DevEco SDK 定义文件（`C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\...`）。
- **未验证** —— 只有推测，禁止当作结论引用。

## 1. 截图

### 1.1 全屏截图权限可用，无需 ACL

- 结论：`ohos.permission.CUSTOM_SCREEN_CAPTURE` 是 normal + user_grant，声明后运行时弹窗即可拿到，**不需要**华为 ACL 审批。
- 证据：**SDK** `toolchains/lib/PermissionDefinitions.json` → `grantMode=user_grant, availableLevel=normal, since=14`；**实测** 日志 `ScreenCapturer: CUSTOM_SCREEN_CAPTURE granted=true` → `capture ok: 3120x2080`。
- 代码：`common/ScreenCapturer.ets:14`；`ensurePermission()` 先 `checkAccessTokenSync` 查已有授权，未授权才 `requestPermissionsFromUser`。
- **申请必须由带窗口的 Ability 发起**：在常驻的无窗口 `TrayAbility` 里调 `requestPermissionsFromUser`，
  系统**不弹窗、不回调、也不报错**——promise 永久挂起，调用方的 `busy` 标志卡死（症状：按快捷键毫无反应，
  日志只有 `capture triggered` 一行）。授权入口放在欢迎窗口的「去授权」。证据：**实测**（卸载重装后复现，
  窗口态申请一次即弹窗并通过）。

### 1.2 `screenshot.capture()` 只能用无参形式

- 结论：传 `CaptureOption`（哪怕只传 `displayId` + `blackWindowIds`）返回 `401`，且**紧接着的无参调用会挂起不返回**。
- 证据：**实测**。代码固定无参调用：`common/ScreenCapturer.ets:52`。

### 1.3 降级路径 `screenshot.pick()` 无需任何权限

- 结论：系统自绘选区并返回 PixelMap；未授权或截图失败时走它，把结果直接贴出。
- 代码：`common/ScreenCapturer.ets:66`、`common/CaptureFlow.ets:67`。

### 1.4 安全类权限弹窗不接受注入的点击

- 结论：`CUSTOM_SCREEN_CAPTURE` 的授权弹窗（"允许…截取你的屏幕？"）用 `uinput` 点按钮毫无反应，应用侧也没有日志 → 这类弹窗只能人工点，验证脚本走到这一步必须停下来叫人。
- 附：干净卸载会重置 user_grant，重装后须重新授权（症状：`hidumper` 里只有 Entry 窗口、没有选区/贴图窗口）。
- 证据：**实测**。手法与症状见 [VERIFY.md](VERIFY.md)。

## 2. 窗口

### 2.1 `WINDOW_TOPMOST` 只在**本应用**窗口之上

- 结论：normal + system_grant，API 语义是"置于本应用其它窗口之上"。把别的应用切到前台后，贴图窗口 ZOrd 由 `114` 变 `-1`（被隐藏），像素被覆盖。
- 证据：**SDK** `availableLevel=normal, grantMode=system_grant, since=13`；**实测** 窗口 dump + 像素比对（贴图窗口内 (200,200) 由 `(230,229,234)` 变 `(33,33,33)`）。
- 代码：`pasteability/PasteAbility.ets:63` `setWindowTopmost(true)`。

### 2.2 真·系统悬浮窗需要 system_basic 权限，本项目不申请

- 结论：`window.createWindow({ windowType: TYPE_FLOAT })` + `ohos.permission.SYSTEM_FLOAT_WINDOW` 是 system_basic（**SDK**），需向华为申请 ACL 受限权限。
- 影响：这是"贴图浮在其它应用之上"与"贴图窗口去圆角/去阴影"的唯一正路。
- 已排除：画中画 `@ohos.PiPWindow` 要求 `XComponent` 视频面，不是贴静态图的路径（见证伪墓地 3）。

### 2.3 主窗口圆角去不掉

- 结论：`setWindowCornerRadius(0)` 对主窗口报 `1300004`，系统日志写明 `SetWindowCornerRadius: This is not sub window or float window`。被裁掉的是**窗口四角**（实测半径约 40px），所以图片四角会被切。
- 证据：**实测**。代码注释：`pasteability/PasteAbility.ets:69`。

### 2.4 主窗口画布改不成透明，"留透明边距藏圆角"不成立

- 结论：窗口四周留出的边距恒为不透明浅灰 `(228,227,232)`；`setWindowBackgroundColor('#01000000')` 在 resize 前/后各设一次都没用；`'#00000000'` 更会被当成"未设置背景"（露出主题底色）。
- 推论：该绕法会露出一圈灰框，已放弃 —— 想真正去圆角只能换 `TYPE_FLOAT`。
- 证据：**实测**。

### 2.5 系统对主窗口有最小尺寸（实测约 608x136 px）

- 结论：截图区域比它小时窗口会被撑大，按 1:1 画就露出一圈灰底。现用"同一张图放大模糊铺底"（`ImageFit.Cover` + `blur(40)`）填补，正常尺寸时该层不可见。
- 证据：**实测** 窗口 dump `ohsnipaste0 [ ... 608 136 ]`；代码里 `resize(320, 72)` vp，按 1vp = 1.9px 换算正是 608x136px。
- 代码：`pages/PastePage.ets:156` `isClamped()`。

### 2.6 单位陷阱：`resize` 收 vp，`moveWindowTo` 收 px

- 结论：单位不一致，两处都按 vp 传会让窗口落在屏幕中间（提交 `1862a6c` 修的就是这个）。
- 证据：**实测**。代码：`entryability/EntryAbility.ets:69`、`pasteability/PasteAbility.ets:91`（贴图初始落点）。
- 对照：`TouchObject` 的 `x/y`、`windowX/windowY`、`displayX/displayY` **都是 vp**（真机实测：1vp = 1.9px 时按下点 `x=126.32` 对应窗口内 240px），只有 `startMoving` 的偏移量收 px。

### 2.7 启动窗口（start window）的行为

- 结论：系统在窗口内容绘制完成前显示启动窗口，**不 `loadContent` 它就不消失**（连同 `startWindowIcon` 一直挂在屏幕中央）；`startWindowIcon` 是 schema 必填项，删掉构建报 `Schema validate failed`。
- 边界：这条只对**会被显示的窗口**成立。`STARTUP_HIDE` 挂载、且引导之后**再也不会被 `startAbility` 唤醒**的常驻 Ability，不 `loadContent` 也不会留下启动窗口 —— 实测 `TrayAbility` 去掉 `loadContent` 后引导照常（握手文件照写），`hidumper -s WindowManagerService` 里没有它的窗口记录，屏幕上也没有启动窗口。
- 结论：底色由资源 `start_window_background` 决定，`base` 已改为 `#01000000`（近全透明；`#00000000` 会被当成未设置）。
- 结论：底色是**按 Ability 配**的。`EntryAbility` 已改用不透明的 `$color:welcome_background`（`#F5F6F7`），因为它首次启动要显示欢迎窗口，透明底会像个幽灵框；其余 Ability 仍用近透明的 `start_window_background`。
- 结论：`window.setWindowBackgroundColor` 在 `onWindowStageCreate` 里**同步**调用会报 `1300002 This window state is abnormal`（窗口还没进 normal 状态），要等 `loadContent` 完成后再设。
- 结论：**不需要露面的窗口可以一露头就收走**。`welcome_seen` 之后的启动在 `onWindowStageCreate` 里直接 `mainWindow.minimize()`，实测窗口 ZOrd 立刻变 `-1`，`terminateSelf` 后 `hidumper` 里查不到窗口记录，启动约 450ms 后的屏幕截图是干净桌面（没有空白/透明窗口）。
- 变更生效的三项配置有 WMS 日志佐证（`OnSetWindowDecorVisible` / `OnSetWindowBackgroundColorSync color=#01000000` / `OnSetWindowShadowEnabled`）。
- ⚠️ **未验证**：`entry/src/main/resources/dark/element/color.json` 的 `start_window_background` 仍是 `#000000`，暗色模式下贴图/选区窗口起来的瞬间可能仍冒出纯黑 —— 登记在 [STATUS.md](STATUS.md) 待确认（`EntryAbility` 已不受影响）。

### 2.8 拖动无装饰窗口：用 `window.startMoving`，别自己发 `moveWindowTo`

- 结论：`startMoving(offsetX, offsetY)`（Since 15，`SystemCapability.Window.SessionManager`）能让窗口管理器直接接管光标跟随，**只在 `onTouch` 的 `TouchType.Down` 回调里调用才生效**，偏移量是按下点相对窗口左上角的 **px** 值。无装饰主窗口可用，不需要 `TYPE_FLOAT` 或受限权限。
- 反例：用 `moveWindowTo` 自己算增量（`target = 上次目标 + Δ窗口内坐标`）会抖 —— 那是把"异步生效的移动"当同步用，落后量在下一条事件里再累加一遍，正反馈震荡。判别证据：同一手法真机拖 200px 窗口走了 365px（×1.83，见 [archive/HISTORY.md](archive/HISTORY.md)）；换 `startMoving` 后拖 400px 窗口正好走 400px，`windowRectChange` 57 个采样点单调、零回退。
- 副作用（**实测**）：跟手拖到屏幕边缘会触发系统窗口吸附 —— 贴图窗口被改成半屏尺寸（`[1571 0 1549 1955]`），页面走"被撑大"分支画模糊铺底；再拖一次即恢复原尺寸（`1000x600`）。公开 API 没有关掉吸附的开关（`setResizeByDragEnabled` 只管边框缩放）。
- 证据：**实测**（2026-10-19；`WMSLayoutPc: StartMovingWithCoordinate: offset:[340,240] pointer:[500,400]`）+ **SDK**（`@ohos.window.d.ts` 两个重载的注释）。

## 3. 常驻入口（任务栏 / 托盘 / 快捷键）

### 3.1 运行时任务栏图标：靠"应用无窗口"消掉（实测通过）

- 结论：`excludeFromDock: true` 本身**无效** —— 三个 Ability 都配了、`bm dump` 也确认系统读到了，应用运行时任务栏**仍然多出图标**（未运行 11 个 → 运行中 12 个；force-stop 后消失）。
- 真正起作用的是**场景容器是否被激活**，而不是窗口可见与否：`addToStatusBar` + `NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM` +
  `STARTUP_HIDE` 的**首次**启动只把会话放进"不显示"列表（无任务栏图标、无窗口记录）；此后任何
  `startAbility` 把该会话"显示"一次，任务栏就多出图标 —— 窗口随后被 `minimize()`（ZOrd 变 `-1`）也不会让它消失，
  只有 force-stop / 「退出」才清。所以运行期一次 ability 启动都不能有（见 3.3 的信号通道）。
- 判别证据：同一块任务栏裁剪区，改造前是"蓝色自绘图标 + WPS"，改造后只剩 WPS；
  触发截图前后各截一次，裁剪区都只有 WPS；且 `hidumper -s WindowManagerService -a '-a'` 查不到任何 `ohsnipaste` 窗口。
- 处置：`excludeFromDock: true` 保留（语义正确、无副作用）。
- 证据：**实测**（2026-10-16）+ **SDK**。

### 3.2 全局快捷键可以做（实测通过）

- 结论：`inputConsumer.on('hotkeyChange')`（`@kit.InputKit`，API 14）是**全局**快捷键订阅 —— 官方参考页标题
  就叫「全局快捷键」，接口描述是"订阅应用快捷键，获取满足条件的组合按键输入事件"；**不需要任何权限、不要求前台**。
  应用现状：常驻进程里按设置注册（默认 **Ctrl+Shift+A**，可在欢迎窗口里改），按下直接走截图链路
  （`tray/TrayAbility.ets` 的 `registerHotkey`）。
- 实测（2026-10-19）：注册在常驻进程、应用**没有任何窗口**、焦点在别的会话时，注入 `Ctrl+Shift+A` →
  `hotkey fired {"preKeys":[2047,2072],"finalKey":2017}` → `capture ok: 3120x2080` → `SelectionPage windowId=149`；
  焦点在系统「备忘录」窗口（`notepad0 [496,295,2090,1394]`）上时同样成功，且同一时刻**没有**向焦点窗口派发
  `DispatchKeyEvent` —— 按键被系统消费，不是"前台应用的普通按键"。
- 实测（2026-10-19）**运行期换键**：`off(旧 options)` + `on(新 options)` 可以在进程不重启的情况下生效 ——
  窗口进程 `HotkeySignal: hotkey change published` → 常驻进程 `hotkey re-registered: Ctrl + Alt + A` →
  再注入 `Ctrl+Alt+A` 得到 `hotkey fired {"preKeys":[2045,2072],"finalKey":2017}`；`force-stop` 后冷启动日志是
  `hotkey registered: Ctrl + Alt + A`（组合来自 preferences）。改回 `Ctrl+Shift+A` 同样一次成功。
- 实测（2026-10-19）**本机没占的组合比想象中多**：`Ctrl+C`、`Ctrl+Alt+Del` 都能注册成功，所以
  `4200002 / 4200003` 这两条失败分支本轮**没能复现**（回滚逻辑只有代码、没有实测）。
- 约束：
  - **必须注册在常驻进程**：`EntryAbility` 引导完 `terminateSelf`，注册随进程消失。早前"注册成功但按键不回调"
    就是在这个形态下测的（见第 6 节墓地 1）。
  - **修饰键必填**：`HotkeyOptions.preKeys` 至少 1 个（SDK 注释写最多 2 个，官方文档写范围 [1,4]），
    所以做不出 Snipaste 那种裸 `F1`；`isRepeat: false` 抑制长按重复触发。
  - **排他**：同一组合全局只归一家，系统已占用报 `4200002`、别的应用已占用报 `4200003`。换键位先看这两个码。
  - `getAllSystemHotkeys()` 只读（本机返回 81 条系统绑定，`Meta+A` 一族在列），不能改键位表。
- 证据：**实测**（2026-10-19）+ **官方文档 / SDK**（`@ohos.multimodalInput.inputConsumer.d.ts`）。

### 3.3 状态栏托盘图标可以做（实测通过）

- 结论：第三方应用能把图标放进状态栏右下角的折叠区（`^`），左键点击可拉起自绘面板。需要三件套：
  1. `module.json5` 声明一个 `"type": "statusBarView"` 的 extensionAbility（官方示例写 `exported: true`，本机实测 `false` 也能被拉起，见第 6 节墓地 7）；
  2. 一个继承 `StatusBarViewExtensionAbility`（`@kit.DeskTopExtensionKit`）的类，在 `onSessionCreate` 里 `session.loadContent(<页面>)`，该页面要登记进 `main_pages.json`；
  3. 运行期 `statusBarManager.addToStatusBar(context, item)`，`item.icons.white/black` 传 `vp2px(24)` PixelMap，`item.quickOperation` 指向上面那个扩展。
- **图标尺寸有规范值**：实现里 `STANDARD_SIZE = 24`（vp），即图标应为 `vp2px(24)`（本机 1.9 密度 ≈ 46px）。尺寸不符只由 `checkIcons` 记一条 `The size of the pixelmap exceeds the limit`，**不拦注册**。
- **左键弹窗取消不掉**：`StatusBarItem.quickOperation` 在 `.d.ts` 里是**必填**（无 `?`），实现里 `checkQuickOperation` 对 `height <= 0` 直接抛 `401`；系统给的最小面板约 106vp（传 1 也被抬到 106）。官方示例（[DesktopExtensionKit-samplecode](https://gitcode.com/HarmonyOS_Samples/DesktopExtensionKit-samplecode)）里左键就是弹窗，且社区文档明说"暂不支持通过代码动态拦截并自定义左键/右键的底层事件映射"。**想要"点一下不出面板"，平台不支持**；官方给出的无面板路径是右键菜单 `statusBarGroupMenu` 的 `menuAction.abilityName`（点菜单项直接启动 ability）。
- **`statusBarIconClick` 本机不派发**：四种配置都试过（正常扩展 / `exported:false` / 已挂载进程监听 / 面板起不来），回调一次都没来；面板照旧弹出或什么都没发生。SDK 实现里该事件是存在的（`STATUS_BAR_ICON_CLICK = 7 → 'statusBarIconClick'`，载荷 `data.iconClickType`），派发方在服务侧，推测是"图标直显在状态栏"才发，未验证。
- **事件只会发给"挂在状态栏项上的进程"**：SDK 实现里有 `IStatusBarCallback::AttachPidToStatusBarItem / OnAttachPidToStatusBarItem`，而挂载靠 `startAbility` 时设 `processMode: NEW_PROCESS_ATTACH_TO_STATUS_BAR_ITEM` + `startupVisibility: STARTUP_HIDE`（调用方须**先** `addToStatusBar`）。首次启动常报 `16000067 The StartOptions check failed` —— 该校验查服务侧 `CreateTrayForApp` 填的集合，而 `addToStatusBar` 只投递就返回，**要有界重试**（实测第 2 次成功）。挂载成功后该 Ability 跑在独立进程 `...:entry:TrayAbility:0`，主 Ability 退出后它仍在。
- ⚠️ **引导 Ability 退出前必须确认挂载进程已就绪**：否则 AMS 判"最后一个 ability 退出"，`ProcessMgr: Terminate last` 会把**整个应用**（含已挂载进程）杀掉，托盘图标一起消失。
- **面板还开着时截图，面板会进冻结画面**：面板是 sceneboard 的窗口，不算"自身窗口"。判别：面板可见时截出的图里带面板（按 Esc 关掉选区窗口后同一区域标题暗像素 3438 → 0，证明它在图里而不是实时窗口）。**不等就直接截时实测带面板**（面板区"压暗蓝按钮"像素 50257）；现行做法是触发后先等 500ms 再截 —— 已复核：日志里"收到触发 → `CUSTOM_SCREEN_CAPTURE already granted`"间隔 ≈ 504ms，且选区窗口里的冻结画面看不到面板。
- **运行期不能用 `startAbility` 唤醒挂载进程**：只带 `startupVisibility: STARTUP_HIDE`、或再加
  `processMode: ATTACH_TO_STATUS_BAR_ITEM`，两种写法都照样把会话激活成前台 → 任务栏立刻多出图标（见 3.1）。
  可用通道是**同应用内的自定义公共事件**（`commonEventManager`）：面板进程 `publish('com.youz.ohsnipaste.action.CAPTURE')`
  → 常驻进程 `subscribe` 回调 → 截图链路，全程不碰 AMS 的场景切换。实测日志
  `CaptureSignal: capture signal published` → `TrayAbility: capture signal received`，同毫秒到达。
- 系统侧证据：`PcAccessPluginComponent: ... "action":"action.systemui.plugin.STATUS_BAR","pluginPosition":"BOTTOM_RIGHT"`；点击后依次 `StartUIExtension: element: com.youz.ohsnipaste/TrayStatusBarExt` → 扩展进程 `com.youz.ohsnipaste:statusBarView` → `TrayExt: onSessionCreate` → `StartUIExtension: pages/TrayPanel`。
- 图标渲染：自绘图标按原样出现在折叠区；卸载应用后同一区域品红像素 545 → 0，证明图标确由该插件产生。
- ⚠️ **误导日志**：每次调用 napi 层都打 `1010710001 The size of the pixelmap exceeds the limit`。实测 1×1 到 128×128 各种尺寸、`editable` 取真取假、真实解码的 PNG，**全部照打**，而图标仍正常渲染 —— 不要拿这条日志判成败（它就是上面 `checkIcons` 的尺寸检查在说话）。
- 生命期：图标只在应用**还有进程活着**时存在；正因如此才需要挂载进程（见 §3.1）。`removeFromStatusBar` 在面板里（前台窗口存在）能成功摘除；「退出」链路实测 `tray icon removed` → `KillApplicationSelf` → 进程与窗口全清。
- 证据：**实测**（2026-10-16，设备与系统基线见 [STATUS.md](STATUS.md)）+ **SDK/官方示例**。复现手法见 [VERIFY.md](VERIFY.md)。
- ⚠️ **未解释的现象**：传**不透明**的纯色方块（24×24 纯青）时，折叠区里显示的是一个**黄色方块**而不是青色；换成"透明底 + 品红圆"后按原样显示。是否要求图标必须带透明通道，**未验证**。
- 图标来源：`icons.white/black` 只收 `PixelMap`，而 `image` 模块**不支持 SVG 解码**（SDK 里全无 svg 字样），所以 SVG 图形必须先离屏光栅化成 PNG 再打进包。
- 面板加载耗时：面板由 sceneboard 拉起 UIExtension，实测**冷启动约 2.4s** 才出现（`onSessionCreate` → `StartUIExtension` → `RunPage`），且跑在独立进程 `<bundle>:statusBarView`。
- 未测边界：右键菜单（`statusBarGroupMenu`）、`hoverTips` 文案、`hideAbility()/showAbility()`（文档要求"应用已添加至状态栏"+ 挂载启动）。

## 4. 权限一览（本项目声明的三个）

| 权限 | 等级 / 授权方式 | `since` | 用途 |
| --- | --- | --- | --- |
| `ohos.permission.CUSTOM_SCREEN_CAPTURE` | normal / user_grant | 14 | 全屏截图，首次运行时弹窗 |
| `ohos.permission.WINDOW_TOPMOST` | normal / system_grant | 13 | 贴图窗口置于本应用窗口之上 |
| `ohos.permission.SET_WINDOW_TRANSPARENT` | normal / system_grant | 20 | `setWindowShadowEnabled(false)` 去阴影 |

- 证据：**SDK** `toolchains/lib/PermissionDefinitions.json`（本机实查）。
- 声明位置：`entry/src/main/module.json5`。
- 刻意不申请 `SYSTEM_FLOAT_WINDOW`（system_basic，需 ACL），代价见 2.1 / 2.2。

## 5. 应用分发（签名 / 邀请测试）

- **调试签名 14 天、且绑设备**：DevEco 自动签名签出的调试 Profile `validity` 只有 14 天
  （本机 2026-10-16 15:48 → 2026-10-30 15:48），`device-ids` 只登记签名时连过的设备（本机 2 个 UDID，
  其中一个是当前这台 HAD-W32）；名单外设备 `hdc install` 报 `9568423`。过期后 hvigor 报
  `The certificate has expired!`，回 DevEco 勾一次「自动签名」即可续期。证据：**实测**（解析 `.p7b`）。
- **发布 Profile 不绑设备、3 年**：`ohos-snipaste-发布Release.p7b` → `type: release`、
  `app-distribution-type: app_gallery`、**无** `device-ids`、`validity` 2026-10-19 → 2029-10-19、
  `bundle-name` 与工程一致。证据：**实测**（解析文件；与本机 `.p12` 的 SKI 一致）。
- **hvigor 只吃 DevEco 加密后的密码**：`signingConfigs.material` 里填明文密码，`SignHap` 直接报
  `00303116 The length of the storePassword or keyPassword field … is less than 32`（按密文长度校验）。
  所以发布签名这份配置只能在 `File > Project Structure > Signing Configs` 里建，由 IDE 加密后写回
  `build-profile.json5`。证据：**实测**。
- **`.app` 不能手工签**：`hap-sign-tool.jar` 的 `sign-app` 只收 `.hap/.bin/.elf`；拿本机三件套手工签 HAP
  时返回 `11011005 Param is not trusted`（原因未定位）。要出 `.app` 只能配好 signingConfig 走
  `assembleApp -p product=release -p buildMode=release`；没配时日志是 `Will skip sign 'app'`，产物为
  `-unsigned.app`。证据：**实测**。
- **`signingConfig` 的名字大小写敏感**：DevEco 生成的配置名是 `Release`，而 product 里写的是 `release` 时，
  hvigor **不报错**，只在日志打 `Will skip sign 'hos_hap'` / `Will skip sign 'app'`，照样
  `BUILD SUCCESSFUL`，产物是 unsigned。判成败只看 `verify-app`，不看退出码。证据：**实测**。
- **`.app` 是整体签名，内含 HAP 不带签名块**（`buildOption.packOptions.appWithSignedPkg` 默认 false）；
  `verify-app` 对 `.app` 通过、对包内 `entry-default.hap` 报 `No Hap Signing Block`，属正常形态。
  AGC 是否接受未签内包**未验证**。证据：**实测**（验证通过时为 `Signing Block version: 3` +
  `Digest verify result: true`，证书链顶层 `…\Release` 2026-10-19 → 2029-10-19）。
- **发布签名包不能侧载**：`app-distribution-type: app_gallery` 的发布签名 HAP 用 `hdc install` 装，
  报 `9568322 signature verification failed due to not trusted app source`。也就是说发布签名的包**只能**
  经 AppGallery（邀请测试 / 上架）落到设备；"发给朋友直接装"要么让对方自己在 DevEco 里用调试签名构建，
  要么走企业开发者的「指定设备发布」。证据：**实测**（先 `bm uninstall` 掉调试包再装发布 HAP）。
  同 bundle 换签名可以装，但**必须先卸载**（不能 `-r` 覆盖）。
- **邀请测试的硬约束**（官方文档经第三方转述，**未在本机验证**）：测试时间**最长 90 天**；
  测试版本 `VersionCode` 不得低于已发布过的测试版本，两个在架测试版本不能 VersionName/VersionCode/构建版本全同；
  测试用户按**测试群组**选取（≤30 组、累计 ≤10000 人），群组是账号级实体——**新版本沿用同一群组不需要重新邀请**；
  分享链接在创建测试版本时生成，邀请码有效期 **30 天**、需拼到分享链接上；手动停止测试后，
  已安装用户仍可用到「安装后 90 天」。
- **分发通道容量**：邀请测试 10000 人 / 100 个在架版本；公开测试 1000 万次下载 / 1 个版本；
  指定设备发布（原内部测试）100 台、**仅企业开发者**、版本 90 天。

## 6. 证伪墓地（曾以为成立、已被推翻）

> 目的：防止后续会话重复踏入同一死胡同。每条都给出**判别反例**。

1. ~~「`inputConsumer` 提供零权限全局快捷键」~~ —— **这一条把结论推翻反了**（2026-10-19 复查更正）。
   当时判否的三条依据里，前两条与事实不符：`on('hotkeyChange')` 是**全局按键**订阅（官方页标题即「全局快捷键」），
   注册也真的成功；不回调的真实原因是注册写在 `EntryAbility` 里、而它引导完就 `terminateSelf`，订阅随进程消失。
   `shortcuts.json` 与本能力无关（那是桌面快捷启动方式，无键位字段，确实带不了快捷键）。
   判别证据：改注册到常驻进程后，应用无窗口、焦点在别的应用上时注入 `Ctrl+Shift+A` 照样回调（见 3.2）。
   **仍然成立的教训**：注册必须落在**不会退出的进程**里 —— 只看"注册那行没报错"会得出相反结论。
2. **「`excludeFromDock: true` 能去掉任务栏图标」** —— 配置被系统读到，图标照旧（见 3.1）。
3. **「画中画 `@ohos.PiPWindow` 可以当贴图用」** —— 它要求 `XComponent` 视频面，不是贴静态图的路径。
4. **「窗口四周留透明边距可以把圆角藏起来」** —— 主窗口画布不透明（2.4），会露出一圈灰框，已放弃。
5. **「扫沙箱目录按文件名时间戳取最新贴图当比较基准」** —— 目录里同时躺着 `shot_*` / 历史 `pin_*` / `diff_*`，实测猜错过一次（拿刚截的 3120x2080 整屏图当了基准）→ 改为进程内登记（`common/PinRegistry.ets`）。
6. **「第三方做不了状态栏托盘图标」** —— 依据只是通读了 `@ohos.window.d.ts`（里面确实没有 "tray" 字样），漏掉了 SDK 的 `hms` 分支：`@hms.pcService.statusBarManager` 根本不在 `openharmony` 目录下。
   判别反例：2026-10-16 真机实测，`addToStatusBar` + `statusBarView` 扩展在状态栏折叠区渲染出自绘图标，点击拉起扩展页（见本文 3.3）。
7. **「`statusBarView` 扩展必须 `exported: true`，否则系统起不来」** —— 早前把"点托盘图标毫无反应"归因到这个字段。
   判别反例：2026-10-16 复测，同一个 APK 只把 `exported` 改成 `false`，sceneboard 照样拉起扩展（`AceUiExtensionComponent: The session is created with bundle=com.youz.ohsnipaste, ability=TrayStatusBarExt`），面板照常出现。当时那次"毫无反应"另有原因，未查清。
8. **「左键点托盘图标可以不弹面板、直接触发动作」** —— 用户提过这个诉求，我也按这个方向试过自动触发。
   判别反例：`StatusBarItem.quickOperation` 在 `.d.ts` 里**必填**；实现里 `checkQuickOperation` 对 `height <= 0` 抛 `401`（实测确认）；官方示例与社区文档都把左键弹窗当作既定行为。更要命的是"面板还开着就截图"会把面板烙进冻结画面（见 3.3），所以自动触发这条路在体验上也不成立。
9. **「`statusBarIconClick` 能拿到托盘点击」** —— 社区示例里有 `if (data['iconClickType'] === 'leftClick')`，看着像可用。
   判别反例：四种配置下真机实测回调一次都没来（见 3.3）。SDK 实现里事件确实存在，但**本机在折叠区图标上不派发**，未查明触发条件。
10. **「用 `startAbility` 唤醒挂载进程不会影响任务栏」** —— 以为常驻会话已经"挂在不显示列表里"，再启动只是投递一个 want。
    判别反例：2026-10-16 实测三种写法（裸 `startAbility`、加 `STARTUP_HIDE`、再加 `ATTACH_TO_STATUS_BAR_ITEM`）都让 sceneboard 把
    TrayAbility 的会话重新激活成前台：`PCDock-PcSmartDockModel: refreshSCBSceneContainerSession : add: <persistentId>, com.youz.ohsnipaste, , entry, TrayAbility`
    → `SCBSceneContainer: aboutToAppear`，任务栏立刻多出带运行点的图标，且窗口 `minimize()` 后仍在，只有 force-stop 才清。
    正解是运行期改用同应用自定义公共事件（见 3.1 / 3.3）。
11. **「自己发 `moveWindowTo` 做增量闭环就是贴图窗口的正确拖动方式」** —— 曾是 `PastePage` 的实现（串行 + 合并，看着挺"工程"）。
    判别反例：真机拖 200px 窗口走了 365px（×1.83），且用户反复反馈"拖动过程中严重抖动"——增量闭环把异步生效的移动当同步用，落后量每条事件再累加一遍，正反馈震荡。
    正解是 `win.startMoving(offsetX, offsetY)`：WMS 直接接管光标跟随，同一手法 400px 拖拽窗口正好走 400px、轨迹 57 个采样点单调零回退（见本文 2.8）。

## 7. 候选方案与待决策

| # | 候选 | 能解决 | 代价 | 谁来定 |
| --- | --- | --- | --- | --- |
| 1 | 申请 `SYSTEM_FLOAT_WINDOW` 的 ACL | 贴图浮在其它应用之上；圆角/阴影可改 | system_basic，需向华为申请审批；牵动 PasteAbility 与权限模型 | 你 |
| 2 | 通知作常驻入口（通知中心带按钮触发截图） | 多一条入口 | 应用必须在运行；**未验证** | 你 |
| 3 | 比较基点稳健化：把基点当**初值**，邻域有界搜索取差异最小的偏移（粗到细两阶段：先 1/8 降采样搜 ±64px，再全分辨率在 ±8px 内细化，预计几十毫秒） | 框选位置变化后比较失准 | 偏离你最初指定的算法，未实现 | 你 |
| 4 | 多贴图管理（透明度、滚轮缩放、一键关全部、贴图列表） | 贴图多了之后不好管 | 中 | 你 |
| 5 | 比较入口 UX（贴图右键菜单加「设为比较基准」，或比较时弹列表选一张） | 目前只能跟"最后一张贴图"比 | 小 | 你 |
| 6 | `ImageDiff` 单元测试 | 纯计算逻辑可脱离设备验证对齐与统计 | 小 | 你 |
| 7 | 贴图窗口去掉按钮、能力收进右键菜单后，是否再留一个最小的可见操作入口 | 贴图窗口上现在没有任何可见按钮，新用户可能找不到菜单 | 小（会重新挡住一点图片） | 你 |
| 8 | 托盘入口从"左键面板"改成"右键菜单 + `menuAction` 直接启动 ability" | 省掉面板这一层 | 小；但要从右键触发，且 `menuAction` 是**启动 ability**，会重新把应用拉进任务栏（见 3.1），除非改成同时投递公共事件 | 你 |
| 9 | 贴图窗口禁止被窗口管理器吸附/改尺寸（`setWindowLimits` 把 min=max=图片尺寸） | 拖到屏幕边缘时贴图不会被吸成半屏（见 2.8 副作用） | 小；需实测能否拦下吸附、并处理系统最小尺寸 608x136 的钳制（要按 `resize` 后的实际 `windowRect` 设限） | 你 |

（未列入的候选：画中画 —— 已排除，理由见本文 2.2。）
