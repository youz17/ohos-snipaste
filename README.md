# 截图贴图（ohos-snipaste）

HarmonyOS（ArkTS / Stage 模型）上的 Snipaste 类截图 + 贴图工具。

## 当前进度

已完成（构建通过）：

- 工程骨架：`entry` 模块、`AppScope`、hvigor 构建配置
- 屏幕截图：`screenshot.capture()`（`CUSTOM_SCREEN_CAPTURE` 运行时授权），失败自动降级到系统选择器 `screenshot.pick()`
- 截图落盘：PixelMap 以 PNG 写入应用沙箱
- **区域截图**：全屏选区窗口（`SelectionAbility` + `SelectionPage`）——铺满屏幕显示冻结的截图，拖拽框选、
  遮罩压暗、放大镜（4×）、实时像素尺寸、确认后按选区 `PixelMap.crop()` 裁剪
- 贴图窗口：独立 `PasteAbility`（`multiton`，每张贴图一个窗口），去边框/标题栏、`setWindowTopmost(true)` 置顶、按图片比例调整窗口、拖拽移动、复制到剪贴板、关闭

完整链路：

```
点「截取屏幕并贴图」
  → 申请 CUSTOM_SCREEN_CAPTURE
  → 最小化自身窗口（避免把自己拍进截图）
  → screenshot.capture() 截整屏
  → 沙箱落盘 PNG
  → SelectionAbility 全屏显示冻结画面，框选区域
  → PixelMap.crop() 裁剪 → 落盘
  → PasteAbility 以无边框置顶窗口贴出
未授权 / 截屏失败时：降级 screenshot.pick()，直接把系统选区结果贴出
```

待做：

- 全局快捷键（`inputConsumer.on('hotkeyChange')`，API 14+，无需权限），可用键盘直接唤起截图
- 贴图管理（多贴图列表、透明度、滚轮缩放）
- **真机行为验证**：需要先配置调试签名（见下），代码目前只经过编译验证

## 真机验证结果（HAD-W32 / HarmonyOS 7.0.0.23 / API 26，bundle `com.youz.ohsnipaste`）

已在真机跑通完整链路，逐环节有日志或像素级证据：

| 环节 | 结果 | 证据 |
| --- | --- | --- |
| `CUSTOM_SCREEN_CAPTURE` 授权 | ✅ | `ScreenCapturer: CUSTOM_SCREEN_CAPTURE granted=true` |
| 全屏截图 | ✅ | `capture ok: 3120x2080` |
| 截图不含自身窗口 | ✅ | 用 60% 遮罩反推：桌面蓝 (74,143,238) → 冻结画面 (46,88,128) 比值 0.59；按钮位置 (93,132,223) → (137,137,139) 中性灰，按钮**不在图里** |
| 选区窗口全屏 | ✅ | 窗口 dump：`ohsnipaste1 [0,0,3120,2080] Mode=1` |
| 框选精度 | ✅ | 鼠标按下 (800,400)、松开 (1800,1000) → `crop x=800 y=400 1000x600` |
| 裁剪 + 落盘 | ✅ | `PinStore: saved ...` / `decoded ...: 1000x600` |
| 贴图窗口 | ✅ | `ohsnipaste2 @ (160,160) 900x540`（1000x600 按 900 上限等比缩放），无边框、可拖动、可复制、可关闭 |

### 已知限制：贴图不能浮在**其它应用**之上

`setWindowTopmost(true)` 调用成功（无报错），但实测把文件管理器切到前台后：

- 窗口 dump：`ohsnipaste2` 的 ZOrd 从 `114` 变成 `-1`（被隐藏）
- 像素：贴图窗口内 (200,200) 由 `(230,229,234)`（贴图可见）变为 `(33,33,33)`（被覆盖）

原因：`WINDOW_TOPMOST` 只是 normal 级权限，其 API 语义是「置于**本应用**其它窗口之上」。
真·系统级悬浮需要 `window.createWindow({ windowType: TYPE_FLOAT })` +
`ohos.permission.SYSTEM_FLOAT_WINDOW`（system_basic，**需向华为申请 ACL 受限权限**）。
画中画（`@ohos.PiPWindow`）不适合：它要求 `XComponent` 视频面，不是贴静态图的路径。

## 踩过的坑（实测记录，避免重走）

1. **不能先最小化自身窗口再截图**：最小化后应用进入后台，随后 `startAbility` 报
   `201`（缺 `START_ABILITIES_FROM_BACKGROUND`，system_basic 拿不到）；且 `restore()`
   返回 `1300004 Unauthorized operation` 无法恢复。现方案：截图期间把自身窗口设为
   透明 + 清空页面内容，全程保持前台。
2. **`screenshot.capture(CaptureOption)` 不可用**：即使只传 `displayId` + `blackWindowIds`
   也返回 `401`，且紧接着的无参 `capture()` 会挂起不返回，因此固定使用无参形式。
3. **`loadContent(url, storage)` 传的 LocalStorage 在页面里取不到值**：
   实测页面 `@LocalStorageProp` 读到空字符串（`imagePath len=0`）。现方案：
   用窗口 id 作 key 存 `AppStorage`（见 `common/PinPayload.ets`）。
4. **`@Builder` 按值传参不具备刷新能力**：遮罩四块一旦用 `@Builder(maskPiece(l,t,w,h))`
   就会被冻结在选区刚成形（4×4）时的尺寸，导致选区内部也被压暗；必须把遮罩直接写在
   `build()` 里。
5. **`PanGesture` 有约 5vp 激活阈值**：会让选区起点比实际按下点偏十几 px（实测
   (800,400) 被裁成 (822,413)）；改用 `onTouch` 后精确一致。改用 `onTouch` 后必须给
   所有覆盖层加 `hitTestBehavior(HitTestMode.None)`，否则点工具栏时父层 Down 会先
   把选区重置为 0×0，按钮消失、click 不触发。
6. **图片不要用沙箱路径交给 `Image()`**：改用 `fileIo` 打开 fd 再
   `image.createImageSource(fd)`，避开路径解析差异（见 `PinStore.decode`）。
7. **bundleName 被 DevEco 改为 `com.youz.ohsnipaste`**：`Launcher` 里不要硬编码，
   用 `context.abilityInfo.bundleName`。
8. **`touch.screenX/screenY` 不是屏幕绝对坐标**：实测其取值与 `windowX/windowY` **完全相同**
   （都相对窗口左上角）。用它算拖窗会形成反馈回路——窗口一动坐标就漂，
   实测拖 200px 窗口只走 99px、拖 400px 只走 204px（约 52.6% = 1/1.9）。
   正确做法：用窗口内位移做闭环
   `target = 已发送位置 + (当前窗口内坐标 - 按下时窗口内坐标)`，
   窗口追上光标后差值不再变化，收敛且不跑飞（实测误差 ≤1px）。
   另外移动请求必须**串行 + 合并**，同时发多个 `moveWindowTo` 会互相竞争。
9. **贴图窗口会盖住选区界面**：`setWindowTopmost(true)` 使贴图窗口 ZOrd 更高，
   新一次截图时选区右下角的操作条会被贴图挡住点不到。选区窗口在
   `maximize()` 之后也要 `setWindowTopmost(true)`（后设置的更靠上）。
10. **`setWindowShadowEnabled(false)` 需要 `ohos.permission.SET_WINDOW_TRANSPARENT`**
    （normal + system_grant，声明即得）；但**主窗口的圆角去不掉**（见下）。
11. **主窗口的圆角无法去掉**：`setWindowCornerRadius(0)` 对主窗口报
    `1300004`，系统日志写得很直白：`SetWindowCornerRadius: This is not sub window
    or float window`。被裁的是**窗口四角**（实测半径约 40px），所以图片四角会被切掉。
12. **主窗口画布改不成透明**，因此"窗口四周留透明边距把圆角藏起来"这条绕法不成立：
    实测边距恒为不透明浅灰 `(228,227,232)`，`setWindowBackgroundColor('#01000000')`
    在 resize 前/后各设一次都没用（`'#00000000'` 更会被当成"未设置背景"）。
    故该绕法会露出一圈灰框，已放弃。想真正去掉圆角只能换 `TYPE_FLOAT` 悬浮窗。
13. **系统对主窗口有最小尺寸限制**：实测最小约 `608x136` px。截图区域比它小时
    窗口会被撑大，按 1:1 画就会露出一圈灰底。现用"同一张图放大模糊铺底"
    （`ImageFit.Cover` + `blur(40)`）填补，正常尺寸时该层完全不可见。

## 第四轮反馈（3 项）

| 反馈 | 处理 | 验证证据 |
| --- | --- | --- |
| 选区支持常规复制/保存/贴图 | 操作条改为 复制 / 保存 / 贴图 / 比较 / 取消；复制走 `pasteboard`，保存走系统 `DocumentViewPicker` 对话框 | `SelectionPage: crop x=400 y=250 600x400` → `ImageShare: copied to clipboard`；保存弹出「选择路径」对话框、默认名 `snipaste_20261016_124328.png` |
| 贴图去掉按钮，能力放右键菜单 | 贴图页不再有任何按钮，`bindContextMenu(..., ResponseType.RightClick)`：复制 / 保存为图片… / 关闭 | 右键后日志来自本应用：`ohsnipaste/AceOverlay: show menu animation finished`；点「复制」得 `ImageShare: copied to clipboard` |
| 图片比较 | 选区「比较」→ 与最新贴图比对（算法见下）→ 差异图作为新窗口展示 | 同区域：`差异 0 px / 400000 px (0.00%)`；隔一分钟的时钟区域：`差异 179 px / 27000 px (0.66%) · 区域 15×21 @(282,18)`，红点正好落在变化的分钟数字上 |

比较算法（`common/ImageDiff.ets`，按需求实现）：左上角像素取背景色 → 行优先找第一个非背景色像素作基点 → 两基点重合 → 重叠区逐像素比对（单通道色差 > 16 判为差异）；差异图画法＝当前截图压暗 45% + 差异像素标红；窗口左上角一行结论。

### 已知弱点：框选位置变化后基点会失准

基点用的是"**第一个**非背景像素"，它可能是随裁剪位置一起漂的边框，而不是稳定特征。实测框选整体偏移 +20px 后：

```
ref anchor(2,0) | cur anchor(685,77) | offset(-683,-77)
差异 19509 px / 比对 49491 px (39.42%)
```

同一内容却报 39% 差异。改进方向：把基点当**初值**，再在其邻域内做有界搜索，取差异最小的偏移（粗到细两阶段，避免全量枚举）。未实现，等确认。

### 测试方法上的两个坑（真机验证用）

1. `uinput -M -c 1` 是在**默认位置（屏幕左上角）**右键，不是当前光标处；要定位右键必须一条命令里连着写：`uinput -M -m 400 300 -i 200 -d 1 -i 200 -u 1`。
2. 贴图窗口在**别的窗口获得焦点后会 ZOrd=-1（被隐藏）**。若先点了桌面再右键贴图，测的是"不可见窗口"，结论无效（我为此白跑了两轮）。必须先创建贴图、期间不点别处，再右键。

### 比较基准改为进程内登记（不扫沙箱目录）

`common/PinRegistry.ets`：打开贴图窗口时登记图片路径，关窗时注销，「比较」取最后登记的那张。
不再扫沙箱目录按文件名时间戳猜最新——目录里同时躺着冻结整屏图 `shot_*`、已关窗的历史
`pin_*`、差异图 `diff_*`，猜错过一次（拿刚截的 3120x2080 整屏图当了基准）。
同一应用各 Ability 在同一进程，静态字段天然共享。

真机验证：

| 场景 | 证据 |
| --- | --- |
| 贴 A(600x400) 再贴 B(500x300) 后比较 | `compare with .../pin_1792126194799.png (registry has 2)` → `ref 500x300`（取到后贴的 B） |
| 用右键菜单关掉 B 后比较 | 只剩一个贴图窗口；`ref 600x400`（回退到 A） |
| 差异图不参与登记 | 比较生成的 `diff_*` 窗口不计入基准 |

## 第五轮反馈：不要窗口出现在任务栏（应像托盘图标一样）

结论：**鸿蒙不给第三方应用这个能力**，两个方向都堵死，已实测。

| 尝试 | 结果 |
| --- | --- |
| `"excludeFromDock": true`（三个 Ability 都加，语义是 "hide the application icon from the dock area"，schema 无 system-only 限制） | `bm dump -n com.youz.ohsnipaste` 确认系统已读到 `"excludeFromDock": true`，但应用运行时任务栏**仍然多出我们的图标**（未运行 11 个图标 → 运行中 12 个，多出的最右蓝色四方格就是我们的；force-stop 后消失）❌ |
| 干净卸载重装（怀疑 dock 缓存旧任务条目） | 图标依旧 ❌ |
| 往"时间/输入法图标那一排"（状态栏托盘）放图标 | 通读 SDK：**没有任何第三方可用 API**；`@ohos.window.d.ts` 里连 "tray" 字样都没有，只有 `UIAbility.d.ts` 一句注释提到"右键 dock bar / system tray 关闭 UIAbility"。`excludeFromMissions` 则明确写着 "For system application only" ❌ |

也就是说 `excludeFromDock` 是唯一的官方开关，但在这台设备（HAD-W32 / HarmonyOS 7.0.0.23 / API 26）上不生效。
配置保留在 `module.json5` 里（语义正确、无副作用，换新版本系统可能就生效了）。

### 顺带查证：全局快捷键（结论：平台不支持）

既然任务栏图标去不掉，退一步想用"按一下快捷键就截图"。逐条查证：

| 检查 | 结果 |
| --- | --- |
| `inputConsumer.on('hotkeyChange')` 注册 | 注册**成功且无需权限**（日志 `InputManagerImpl: SubscribeHotkey` + `hotkey registered: Ctrl+Shift+A`），但按下**不触发回调**：应用在前台时按键被当普通按键派发给窗口（`WMSEvent: DispatchKeyEvent ret:51`），退到后台（`ohsnipaste0` ZOrd 变 `-1`）后日志里连按键都没有 ❌ |
| 该 API 的文档含义 | `@ohos.multimodalInput.inputConsumer.d.ts`：*"Subscribes to application shortcut key **change** events"* —— 是"应用快捷键配置变更"通知，不是按键订阅 |
| `inputConsumer.on('keyPressed')`（API 16） | 文档：*"If the current application is in the **foreground focus window**, a callback is triggered"* → 只前台 ❌ |
| launcher 快捷方式 schema `toolchains/modulecheck/shortcuts.json` | 只允许 `shortcutId / label / icon / visible / wants`，**没有键位字段** ❌ |
| `inputConsumer.getAllSystemHotkeys()` | 可读，返回 **81** 条，全是系统窗口管理绑定（Win+方向键、Ctrl+Shift+Esc、Alt+F10…），应用只读 ❌ |
| 设置应用 | 无任何快捷键页面（`bm dump com.huawei.hmos.settings` 只有键鼠共享/恢复密钥） ❌ |

结论：不是缺权限，是平台**没有暴露**第三方全局快捷键。相关探测代码已删除，只留下把入口流程抽成
`common/CaptureFlow.ets` 的重构（页面与今后任何触发方式共用）。

> 更正：本文件早前把"`inputConsumer` 零权限全局快捷键"列为候选，依据的是已从该 SDK 移除的
> 老接口 `on('key')`，属于未查证就下的判断，现作废。

## 激活时冒出一个"很大、纯色、无意义"的窗口

现象：点任务栏图标触发截图时，屏幕上先冒出一个占满半个屏幕的浅色窗口，还会被截进冻结画面。

两个成因，都实测确认：

1. **启动窗口（start window）是纯白的**。`resources/base/element/color.json` 里
   `start_window_background` 写的是 `#FFFFFF`，它是系统在窗口内容绘制前显示的启动窗口底色，
   尺寸＝窗口尺寸。已改成 `#01000000`（近全透明）。
2. 窗口内容必须存在：启动窗口**要等窗口内容绘制完成才消失**，所以 `onWindowStageCreate` 里
   不能省 `loadContent`（试过完全不加载页面，结果启动窗口连同 `startWindowIcon` 一直挂在屏幕
   中央不走）。正确做法是保留空页面，让窗口本身不可见 —— WMS 日志证实三项配置都生效：

```
WMSDecor: OnSetWindowDecorVisible: Window [718, ohsnipaste0] end
WMSAttribute: OnSetWindowBackgroundColorSync: win=718, color=#01000000, retErr=0
WMSAttribute: OnSetWindowShadowEnabled winId: 718, set enable: 0
```

另外：`startWindowIcon` 是 **schema 必填项**，删掉会让构建报 `Schema validate failed`。
窗口虽然不可见，但仍会吃掉它范围内的点击，所以打开选区窗口后依旧要 `minimize()`。

触发点也从页面的 `onPageShow` 挪到了 `EntryAbility.onCreate`（冷启动）与 `onNewWant`
（应用已在运行时再被激活），页面只剩"被画出来"这一个职责，避免与两者重复触发。

## 第三轮反馈（3 项）


| 反馈 | 处理 | 验证证据 |
| --- | --- | --- |
| 自己触发点击测试 | 先 force-stop 前后对比任务栏截图，定位到本应用图标（最右侧蓝色四方格，停掉即消失），再点它 | 点击后 `CUSTOM_SCREEN_CAPTURE granted=true` → `capture ok` → 选区窗口 `[0,0,3120,2080] ZOrd=116`，全程未用 `aa start` |
| 选区可继续微调 | 加 8 个把手（拖角/边改范围）、拖选区内部整体移动、方向键平移、Shift+方向键改大小、Esc 退出；无选区时也常驻一个「取消」 | 一次连续操作后裁切 `x=498 y=347 1205x750`，与逐步推算完全一致（把手 +200/+150 → 移动 +100/+100 → 方向键 -2/-3 → Shift+Right +5） |
| 贴图窗口圆角 | 做不到，原因见踩坑 11/12（主窗口圆角 + 主窗口不透明），已撤回会露出灰框的绕法 | `setWindowCornerRadius failed: 1300004 ... This is not sub window or float window` |


## 第二轮反馈修复（6 项，均已真机验证）

| 反馈 | 处理 | 验证 |
| --- | --- | --- |
| 贴图窗口有边框 | 加 `setWindowShadowEnabled(false)`，窗口背景全透明，页面不再有底色 | 截图中贴图边缘直接接桌面，无阴影/圆角/边框 |
| 拖动有点奇怪 | 见踩坑 8：改用窗口内位移做闭环 + 串行合并 | 拖 (600,600)→(800,800) 得 `[365,365]`；快拖 (700,700)→(1100,1100) 得 `[764,764]`（期望 765） |
| 主窗口不应存在（任务栏形式） | 入口页清空且透明、启动即自动截图，选区窗口起来后把主窗口 minimize | 日志 `Index: main window hidden`；窗口 dump 主窗口 ZOrd=`-1`；再次激活应用能重新截图 |
| 贴图图片应与截图等大 | 窗口尺寸 = 截图像素尺寸（去掉 900 上限），图片按 `px2vp` 反算 1:1 显示 | `pin window size 1200x700 (image 1200x700)`；与冻结画面逐像素比对平均偏差 0.2 |
| 按钮应在选区边上 | 操作条贴选区右下角，放不下则翻到选区内部/上方 | 截图中按钮在选区右下角；实测点「取消」能关闭选区 |
| 贴图能浮在其它应用上 | **做不到**，见下节（需 ACL 受限权限） | 实测被其它应用覆盖 |



## 权限说明（已核实，非推测）

依据 SDK 权威权限库 `sdk/default/openharmony/toolchains/lib/PermissionDefinitions.json`：

| 权限 | 级别 | 授权方式 | 用途 |
| --- | --- | --- | --- |
| `ohos.permission.CUSTOM_SCREEN_CAPTURE` | normal | user_grant | 全屏截图，运行时弹窗授权，**无需华为 ACL 审批** |
| `ohos.permission.WINDOW_TOPMOST` | normal | system_grant | 贴图窗口置顶，安装即授予 |

因此本项目**不需要**申请受限权限 `ohos.permission.SYSTEM_FLOAT_WINDOW`（system_basic，需 ACL）：
贴图用「独立自由窗口 + 置顶」实现，效果等价而无需审批。`supportWindowMode` 已声明
`fullscreen / split / floating`，便于 2in1 上以自由窗口显示。

## 构建

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
$env:NODE_HOME='C:\Program Files\Huawei\DevEco Studio\tools\node'
$env:HVIGOR_USER_HOME='D:\tools\ohos-snipaste\.hvigor'   # 把 hvigor 缓存限制在工程内
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`。

> `HVIGOR_USER_HOME` 让 hvigor 的缓存/目录联接留在工程内；若在受限沙箱下运行，hvigor 创建
> 目录联接会被拒绝，需要在不受限环境执行。

## 安装到设备

当前 `build-profile.json5` 未配置签名，产出的是 unsigned HAP，无法直接安装。真机调试步骤：

1. DevEco Studio 打开本工程
2. `File > Project Structure > Signing Configs` 勾选 **Automatically generate signature**
3. 登录华为开发者账号（免费注册 + 实名认证），DevEco 会自动生成调试证书并写入 `C:\Users\youz\.ohos\config`
4. 运行到设备

调试签名**不需要申请和审批**；只有受限权限（ACL）才需要走 AppGallery Connect 申请，本项目不使用。

## 目录结构

```
entry/src/main/ets/
├── common/
│   ├── ScreenCapturer.ets   # 截图权限 + capture/pick
│   ├── PinStore.ets         # PixelMap → PNG 落盘
│   └── Launcher.ets         # 拉起选区窗口 / 贴图窗口
├── entryability/EntryAbility.ets
├── selectionability/SelectionAbility.ets   # 全屏选区窗口（去边框 + 铺满屏幕）
├── pasteability/PasteAbility.ets           # 贴图窗口（无边框 + 置顶 + 缩放定位）
└── pages/
    ├── Index.ets            # 主界面：截图 → 选区 → 贴图
    ├── SelectionPage.ets    # 选区：遮罩 + 框选 + 放大镜 + 尺寸 + 裁剪
    └── PastePage.ets        # 贴图内容：显示 + 拖动 + 复制 + 关闭
```
