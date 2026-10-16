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
- 代码：`pages/PastePage.ets:196` `isClamped()`。

### 2.6 单位陷阱：`resize` 收 vp，`moveWindowTo` 收 px

- 结论：单位不一致，两处都按 vp 传会让窗口落在屏幕中间（提交 `1862a6c` 修的就是这个）。
- 证据：**实测**。代码：`entryability/EntryAbility.ets:69`、`pages/PastePage.ets:110`。

### 2.7 启动窗口（start window）的行为

- 结论：系统在窗口内容绘制完成前显示启动窗口，**不 `loadContent` 它就不消失**（连同 `startWindowIcon` 一直挂在屏幕中央）；`startWindowIcon` 是 schema 必填项，删掉构建报 `Schema validate failed`。
- 结论：底色由资源 `start_window_background` 决定，`base` 已改为 `#01000000`（近全透明；`#00000000` 会被当成未设置）。
- 变更生效的三项配置有 WMS 日志佐证（`OnSetWindowDecorVisible` / `OnSetWindowBackgroundColorSync color=#01000000` / `OnSetWindowShadowEnabled`）。
- ⚠️ **未验证**：`entry/src/main/resources/dark/element/color.json` 的 `start_window_background` 仍是 `#000000`，暗色模式下激活瞬间可能仍冒出纯黑窗口 —— 登记在 [STATUS.md](STATUS.md) 待确认。

## 3. 常驻入口（任务栏 / 托盘 / 快捷键）

### 3.1 运行时任务栏图标去不掉

- 结论：`excludeFromDock: true` 三个 Ability 都已在 `module.json5`，且 `bm dump -n com.youz.ohsnipaste` 确认系统读到了该配置，但应用运行时任务栏**仍然多出我们的图标**（未运行 11 个 → 运行中 12 个，多出的最右蓝色四方格；force-stop 后消失）；干净卸载重装也无效。
- 处置：配置保留（语义正确、无副作用，换新版本系统可能就生效），换系统版本后复测（见 [STATUS.md](STATUS.md) 开放待办）。
- 证据：**实测** + **SDK**。

### 3.2 第三方没有全局快捷键

- 结论：不是缺权限，是平台**没有暴露**。逐项反例见证伪墓地 1。
- 现状：应用内没有快捷键唤起；相关探测代码已删除。

### 3.3 状态栏托盘图标可以做（实测通过）

- 结论：第三方应用能把图标放进状态栏右下角的折叠区（`^`），左键点击可拉起自绘面板。需要三件套：
  1. `module.json5` 声明一个 `"type": "statusBarView"` 的 extensionAbility，**`exported` 必须为 `true`** —— 为 `false` 时系统起不来，只有 `AppMS: no ability or uiextension` 和一条 `HoverTips: getAppName ... appName:fail`；
  2. 一个继承 `StatusBarViewExtensionAbility`（`@kit.DeskTopExtensionKit`）的类，在 `onSessionCreate` 里 `session.loadContent(<页面>)`，该页面要登记进 `main_pages.json`；
  3. 运行期 `statusBarManager.addToStatusBar(context, item)`，`item.icons.white/black` 传 24×24 `RGBA_8888` PixelMap，`item.quickOperation` 指向上面那个扩展。
- 系统侧证据：`PcAccessPluginComponent: ... "action":"action.systemui.plugin.STATUS_BAR","pluginPosition":"BOTTOM_RIGHT","pluginIconWidth":20,"pluginType":"message","bundleName":"com.youz.ohsnipaste"`；点击后依次 `StartUIExtension: element: com.youz.ohsnipaste/StatusBarProbeExt` → `ProcessMgr: startProcessName = com.youz.ohsnipaste:statusBarView` → `SBProbeExt: onSessionCreate -> loadContent` → `StartUIExtension: pages/StatusBarProbePage`，面板落在 `displayArea=RectT (2361,1483) - [687x456]`，扩展跑在独立进程 `com.youz.ohsnipaste:statusBarView`。
- 图标渲染：自绘的"透明底 + 品红圆"24×24 按原样出现在折叠区；卸载应用后同一区域品红像素 545 → 0，证明图标确由该插件产生。
- ⚠️ **误导日志**：每次调用 napi 层都打 `1010710001 The size of the pixelmap exceeds the limit`。实测 1×1、4×4、8×8、16×16、20×20、24×24、28×28、32×32、41×41、96×96、128×128，`editable` 取真取假，以及真实解码的 PNG，**全部照打**，而图标仍正常渲染 —— 不要拿这条日志判成败。
- 证据：**实测**（2026-10-16，设备与系统基线见 [STATUS.md](STATUS.md)）。复现手法见 [VERIFY.md](VERIFY.md)。
- ⚠️ **未解释的现象**：传**不透明**的纯色方块（24×24 纯青）时，折叠区里显示的是一个**黄色方块**而不是青色；换成"透明底 + 品红圆"后按原样显示。是否要求图标必须带透明通道，**未验证**。
- 图标来源：`icons.white/black` 只收 `PixelMap`，而 `image` 模块**不支持 SVG 解码**（SDK 里全无 svg 字样），所以 SVG 图形必须先离屏光栅化成 PNG 再打进包。
- 面板加载耗时：面板由 sceneboard 拉起 UIExtension，实测**冷启动约 2.4s** 才出现（`onSessionCreate` → `StartUIExtension` → `RunPage`），且跑在独立进程 `<bundle>:statusBarView`。
- 未测边界：右键菜单（`statusBarGroupMenu`）、`removeFromStatusBar`（其文档写明"没有前台窗口时不能删图标"）、`hoverTips` 文案。

## 4. 权限一览（本项目声明的三个）

| 权限 | 等级 / 授权方式 | `since` | 用途 |
| --- | --- | --- | --- |
| `ohos.permission.CUSTOM_SCREEN_CAPTURE` | normal / user_grant | 14 | 全屏截图，首次运行时弹窗 |
| `ohos.permission.WINDOW_TOPMOST` | normal / system_grant | 13 | 贴图窗口置于本应用窗口之上 |
| `ohos.permission.SET_WINDOW_TRANSPARENT` | normal / system_grant | 20 | `setWindowShadowEnabled(false)` 去阴影 |

- 证据：**SDK** `toolchains/lib/PermissionDefinitions.json`（本机实查）。
- 声明位置：`entry/src/main/module.json5`。
- 刻意不申请 `SYSTEM_FLOAT_WINDOW`（system_basic，需 ACL），代价见 2.1 / 2.2。

## 5. 证伪墓地（曾以为成立、已被推翻）

> 目的：防止后续会话重复踏入同一死胡同。每条都给出**判别反例**。

1. **「`inputConsumer` 提供零权限全局快捷键」** —— 依据是已从该 SDK 移除的老接口 `on('key')`，属于未查证就下的判断。
   判别反例：`on('hotkeyChange')` 注册成功（`InputManagerImpl: SubscribeHotkey`）但按键不回调 —— 前台按键只被当普通按键派发（`WMSEvent: DispatchKeyEvent ret:51`），退到后台则毫无日志；`on('keyPressed')` 文档限定"前台聚焦窗口"；`shortcuts.json` 只有 `shortcutId/label/icon/visible/wants`，没有键位字段；`getAllSystemHotkeys()` 只读，返回 81 条系统绑定。
2. **「`excludeFromDock: true` 能去掉任务栏图标」** —— 配置被系统读到，图标照旧（见 3.1）。
3. **「画中画 `@ohos.PiPWindow` 可以当贴图用」** —— 它要求 `XComponent` 视频面，不是贴静态图的路径。
4. **「窗口四周留透明边距可以把圆角藏起来」** —— 主窗口画布不透明（2.4），会露出一圈灰框，已放弃。
5. **「扫沙箱目录按文件名时间戳取最新贴图当比较基准」** —— 目录里同时躺着 `shot_*` / 历史 `pin_*` / `diff_*`，实测猜错过一次（拿刚截的 3120x2080 整屏图当了基准）→ 改为进程内登记（`common/PinRegistry.ets`）。
6. **「第三方做不了状态栏托盘图标」** —— 依据只是通读了 `@ohos.window.d.ts`（里面确实没有 "tray" 字样），漏掉了 SDK 的 `hms` 分支：`@hms.pcService.statusBarManager` 根本不在 `openharmony` 目录下。
   判别反例：2026-10-16 真机实测，`addToStatusBar` + `exported: true` 的 `statusBarView` 扩展在状态栏折叠区渲染出自绘图标，点击拉起扩展页（见本文 3.3）。

## 6. 候选方案与待决策

| # | 候选 | 能解决 | 代价 | 谁来定 |
| --- | --- | --- | --- | --- |
| 1 | 申请 `SYSTEM_FLOAT_WINDOW` 的 ACL | 贴图浮在其它应用之上；圆角/阴影可改 | system_basic，需向华为申请审批；牵动 PasteAbility 与权限模型 | 你 |
| 2 | 通知作常驻入口（通知中心带按钮触发截图） | 少点一次任务栏图标 | 应用必须在运行；任务栏图标依旧在；**未验证** | 你 |
| 3 | 比较基点稳健化：把基点当**初值**，邻域有界搜索取差异最小的偏移（粗到细两阶段：先 1/8 降采样搜 ±64px，再全分辨率在 ±8px 内细化，预计几十毫秒） | 框选位置变化后比较失准 | 偏离你最初指定的算法，未实现 | 你 |
| 4 | 多贴图管理（透明度、滚轮缩放、一键关全部、贴图列表） | 贴图多了之后不好管 | 中 | 你 |
| 5 | 比较入口 UX（贴图右键菜单加「设为比较基准」，或比较时弹列表选一张） | 目前只能跟"最后一张贴图"比 | 小 | 你 |
| 6 | `ImageDiff` 单元测试 | 纯计算逻辑可脱离设备验证对齐与统计 | 小 | 你 |
| 7 | 贴图窗口去掉按钮、能力收进右键菜单后，是否再留一个最小的可见操作入口 | 贴图窗口上现在没有任何可见按钮，新用户可能找不到菜单 | 小（会重新挡住一点图片） | 你 |
| 8 | 状态栏托盘图标作常驻入口（图标 + 左键面板：截图 / 贴图 / 比较 / 退出） | 不必依赖任务栏图标，也不必依赖做不成的全局快捷键 | 中；需新增 `statusBarView` 扩展并置 `exported: true`，面板由 sceneboard 承载（见 3.3） | 你 |

（未列入的候选：画中画 —— 已排除，理由见本文 2.2。）
