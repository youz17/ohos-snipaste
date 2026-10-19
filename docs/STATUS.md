# 状态看板

**只写"此刻"**：待办做完就删（历史交给 `git log`），新增结论直接覆写对应条目，不留"早先是 A 后来改成 B"的叙事。
过程流水账在 [archive/HISTORY.md](archive/HISTORY.md)（默认不读），平台结论在 [SPEC-AND-TRUTH.md](SPEC-AND-TRUTH.md)。

## 基线

| 项 | 值 |
| --- | --- |
| 真机 | HAD-W32（HUAWEI MateBook Pro）；2026-10-16 实测 `const.ohos.apiversion=24`、`const.ohos.fullname=OpenHarmony-6.1.1.135`。本节早前记的 "HarmonyOS 7.0.0.23 / 设备 API 26" 与这台物理设备不符 —— 那台是何环境**未验证**（本机 `%LOCALAPPDATA%\Huawei\Emulator\deployed` 下有 "MateBook Pro" 镜像） |
| 显示 | 3120x2080 px，1vp = 1.9px |
| bundle | `com.youz.ohsnipaste` |
| 代码基线 | `6d0a51a`（其后仅改文档的提交不动代码；需要回溯用 `git log --follow`） |
| 产物 | `entry/build/default/outputs/default/entry-default-signed.hap`（调试签名，`build-profile.json5` 已配置 `signingConfigs: default`） |
| 真机连接 | 2026-10-16 已连接（`hdc list targets` → `3QC0124C16000565`）。注意调试签名 profile 的 `device-ids` 只登记了另一台 UDID，换设备后须在 DevEco 重新自动签名才能安装 |

## 已真机跑通（2026-10-16）

| 环节 | 结果 | 关键证据 |
| --- | --- | --- |
| `CUSTOM_SCREEN_CAPTURE` 授权 | ✅ | `CUSTOM_SCREEN_CAPTURE granted=true` |
| 全屏截图 | ✅ | `capture ok: 3120x2080` |
| 截图不含自身窗口 | ✅ | 60% 遮罩反推桌面蓝比值 0.59；按钮位置为中性灰 → 按钮不在图里 |
| 选区窗口全屏 | ✅ | dump `ohsnipaste1 [0,0,3120,2080]` |
| 框选精度 | ✅ | 按 (800,400) 松 (1800,1000) → `crop x=800 y=400 1000x600` |
| 裁剪 + 落盘 | ✅ | `PinStore: saved ...` / `decoded ...: 1000x600` |
| 贴图窗口 | ✅ | `pin window 1000x600 for image 1000x600`；无边框、右键菜单可用；拖动改由 `win.startMoving` 接管（2026-10-19 实测：慢拖 +400,+300 → 窗口 `560,460`、快拖 +600,+400 → `1160,860`、微拖 +30,+30 → `1190,890`，全部 1:1 且无过冲；松手后只移动光标窗口不动；右键弹出菜单时窗口不动）；方向键微调 1px（2026-10-19 实测 `[160,160]` → 右 `161` / 下 `161`、连按 5 次右 → `167`、拖到 `267` 后再按 → `268`、连按 12 次左被夹在 `x=0`，且框选生成的贴图窗口**获得焦点后无需先点击**即可微调） |
| 复制 / 保存 | ✅ | `ImageShare: copied to clipboard`；保存弹系统对话框、默认名 `snipaste_20261016_124328.png` |
| 比较 | ✅ | 同区域 `差异 0 px / 400000 px (0.00%)`；时钟区域 `差异 179 px / 27000 px (0.66%) · 区域 15×21 @(282,18)` |
| 首次启动不截图 | ✅ | 引导只注册托盘与拉起常驻进程，不截图；截图由两条路径触发：托盘面板的「开始截图」（公共事件）或全局快捷键 Ctrl+Shift+A |
| 状态栏托盘入口 | ✅ | `TrayEntry: tray icon registered`；折叠区出现线稿图标，点它 → `StartUIExtension: pages/TrayPanel`；面板内「开始截图」→ `CaptureSignal: capture signal published` → `TrayAbility: capture signal received` → 504ms 后 `CUSTOM_SCREEN_CAPTURE already granted` → `capture ok` → `SelectionPage ... shot_*.png`；「退出」→ `tray icon removed` → `KillApplicationSelf` → `pidof` 为空、窗口全清 |
| 应用无窗口常驻 | ✅ | 引导后 `ProcessMgr: Terminate last` 只终结主进程，挂载进程 `...:entry:TrayAbility:0` 仍在；`hidumper -s WindowManagerService` 查不到任何 `ohsnipaste` 窗口；任务栏裁剪区里我们的图标消失（只剩 WPS） |
| 截图全程不进任务栏 | ✅ | 面板触发截图 → 选区窗口出现 → Esc 关掉，三个时刻截同一块任务栏裁剪区都只有 WPS；日志里 `refreshSCBSceneContainerSession : add` 只出现 `SelectionAbility`，没有 `TrayAbility`（见 [SPEC-AND-TRUTH.md](SPEC-AND-TRUTH.md) 3.1 / 墓地 10） |
| 托盘面板截图不带面板 | ✅ | 冻结画面里面板区（x 2250-3050 / y 1600-2000）只剩被压暗的桌面，没有面板与蓝按钮；触发到截图间隔 504ms，`PANEL_SETTLE_MS` 真的生效（此前被 `pages/Index.onPageShow` 的立即触发抢跑） |
| 全局快捷键截图 | ✅ | 常驻进程注册 `Ctrl+Shift+A`（`hotkey registered`），注入后 `hotkey fired` → `capture ok: 3120x2080` → `SelectionPage windowId=149`；应用当时**没有任何窗口**，焦点在系统「备忘录」（`notepad0 [496,295,2090,1394]`），且该窗口没收到 `DispatchKeyEvent`（按键被系统消费，不是前台普通按键） |
| 欢迎窗口（首次启动） | ✅ | 清空应用数据后冷启动 → `onCreate ... welcome=yes` / `welcome window shown` / `welcome window 1064x988 px`，窗口 `[1028 546 1064 988]` 居中、不透明 `#F5F6F7`，内容含名字、快捷键（含「修改」）、对比说明、Esc 提示；Esc 关闭 → `onDestroy`、`hidumper` 无窗口、常驻进程仍在 |
| 后续启动不弹窗 | ✅ | `welcome=no` 时 `repeat launch: main window minimized`，约 20ms 内窗口 ZOrd 变 `-1`；`welcome=no` 冷启动从创建到 `bootstrap done` 约 750ms，随后 `hidumper` 里查不到窗口；常驻进程已在（16000068）的那次 43ms 内就退出。截图（启动后约 450ms）与任务栏截图都干净 |
| 改键（跨进程 + 持久化） | ✅ | 欢迎窗口「修改」→ 捕获 Ctrl+Alt+A → `HotkeySignal: hotkey change published` → 常驻进程 `hotkey re-registered: Ctrl + Alt + A` → `Welcome: hotkey applied`，界面显示「已生效」；`aa force-stop` 后冷启动日志是 `hotkey registered: Ctrl + Alt + A`（持久化生效）；随后改回 `Ctrl + Shift + A` 同样成功 |
| 托盘面板「使用说明」 | ✅ | `TrayPanel: welcome window requested` → `EntryAbility: onCreate ... forced=yes` → 窗口出现（`TrayAbility already running` 后不退出）；把窗口最小化（ZOrd `-1`）再点一次 → `onNewWant -> bring welcome window to front` / `welcome window restored`，ZOrd 回到 `110` |

## 模块健康度

| 模块 | 位置 | 状态 |
| --- | --- | --- |
| 入口编排 | `common/CaptureFlow.ets` | ✅ 静默期 / 去抖 / busy 防重 / pick 降级齐备；⚠️ 截图前 `minimize()` 的顺序待复核（待办 1）。`hideSelfWindow()` 现在只对着一个不存在的窗口调用（实测不会误伤同应用的贴图窗口：贴图窗口 ZOrd 全程 `113`） |
| 截图 | `common/ScreenCapturer.ets` | ✅ 无参 `capture()` + `pick()` 降级；带参 `capture()` 这条路已走死 |
| 选区 | `pages/SelectionPage.ets` + `selectionability/` | ✅ 框选 / 8 把手 / 4× 放大镜 / 方向键 / 5 个操作条动作 |
| 贴图 | `pages/PastePage.ets` + `pasteability/` | ✅ 1:1 显示、系统接管拖动（`window.startMoving`，见 SPEC-AND-TRUTH 2.8）、方向键 1 像素微调、右键菜单；置顶范围与圆角是平台限制（非缺陷）；⚠️ 拖到屏幕边缘会被系统吸附成半屏（候选 9） |
| 比较 | `common/ImageDiff.ets` + `common/PinRegistry.ets` | ⚠️ 算法按需求实现，基点在框选位置变化后失准（限制，见 SPEC-AND-TRUTH 候选 3） |
| 分享 | `common/ImageShare.ets` | ✅ 剪贴板 + 系统保存对话框 |
| 传值 / 落盘 | `common/PinPayload.ets`、`common/PinStore.ets` | ✅ 窗口 id + AppStorage；fd 解码，固定 RGBA_8888 |
| 常驻入口 | `tray/TrayEntry.ets` + `tray/TrayAbility.ets` + `tray/CaptureSignal.ets` + `tray/HotkeySignal.ets` + `tray/TrayStatusBarExt.ets` + `pages/TrayPanel.ets` | ✅ 注册/摘除、挂载常驻（独立进程、无窗口、无页面）、左键面板（开始截图 / 使用说明 / 退出）均真机跑通；触发有两条：同应用自定义公共事件（面板）与 `inputConsumer.on('hotkeyChange')`（默认为 Ctrl+Shift+A、可在欢迎窗口改，见 SPEC-AND-TRUTH 3.2）；⚠️ 面板冷启动约 2.4s；⚠️ 挂载首次调用报 `16000067`，靠有界重试兜住 |
| 欢迎窗口 / 设置 | `pages/Welcome.ets` + `common/Hotkey.ets` + `tray/HotkeySignal.ets` | ✅ 首次启动自动弹一次（标记 `welcome_seen` 落 preferences），后续启动不弹；Esc 关窗即 `terminateSelf`；托盘点「使用说明」可再唤起，已最小化时走 `onNewWant` + `show()` 唤回；改键走「先落盘 → 公共事件 → 常驻进程重注册 → 回执」四步，成功/失败都会更新界面 |
| 引导 | `entryability/EntryAbility.ets` | ✅ 注册托盘 → 挂载常驻进程 → 等握手文件 → `terminateSelf`（欢迎窗口那一次不退出）；非首次启动先 `minimize()` 主窗口，实测不再闪空白窗；⚠️ 握手文件用 `fs.accessSync`（返回 boolean，不是抛异常）；⚠️ `16000068` 时跳过等握手 |

## 开放待办（做完即删）

1. **待复核：`minimize()` 与截图顺序**（设备已连接可复跑，按 [VERIFY.md](VERIFY.md) 的典型序列）
   - 早期实测称"先最小化自身窗口再截图会让应用进后台、`startAbility` 报 `201`"，而现行 `CaptureFlow` 正是
     "申请权限 → `minimize()` → 截图 → `startAbility`"（`common/CaptureFlow.ets`）；本轮改造后这条路径
     已实测跑通（面板触发 → 截图 → 选区窗口出现），但当时那条记录的适用条件仍未查清。
2. 比较基点稳健化（方案见 [SPEC-AND-TRUTH.md](SPEC-AND-TRUTH.md) 候选 3）—— 需你确认是否偏离最初指定的算法。
3. 多贴图管理（透明度、滚轮缩放、一键关全部、贴图列表）。
4. 比较入口 UX（贴图右键菜单「设为比较基准」等）。
5. `ImageDiff` 单元测试（纯计算，可脱离设备）。
6. **待确认：暗色模式启动窗口** —— `EntryAbility` 已改用不透明的 `welcome_background`（`#F5F6F7`，两种模式同一份）；但 `PasteAbility` / `SelectionAbility` 仍用 `start_window_background`，而 `dark/element/color.json` 里它还是 `#000000`（`base` 是 `#01000000`）。暗色模式下贴图/选区窗口起来的瞬间可能冒一下纯黑；未实测。
7. **待确认：常驻进程被杀后的自愈** —— 面板触发改成公共事件后，若 `...:entry:TrayAbility:0` 已死而图标还在（例如只有 `:statusBarView` 活着），点「开始截图」会没有任何反应（老写法靠 `startAbility` 顺带重启进程）。未实测这种状态的复现概率与表现。
8. **待确认：面板开着时按快捷键** —— 快捷键那条路 `capture(0)` 不等待，而面板是 sceneboard 的窗口、不进"自身窗口"排除（见 SPEC-AND-TRUTH 3.2 / ARCHITECTURE 雷区）。此时冻结画面里可能带面板；未实测。
9. **待确认：改键失败的回滚分支没被触发过** —— 逻辑是"`off` 旧组合 → `on` 新组合失败 → 把旧组合装回去 + 回报错误码 + 窗口回滚设置"，但本机 `Ctrl+C`、`Ctrl+Alt+Del` 都能注册成功，`4200002 / 4200003` 没能复现，这条分支只有代码没有实测（回滚代码见 `TrayAbility.applyHotkey` / `Welcome` 的 `listenHotkeyResult`）。
10. **待确认：权限申请没回执会让 `CaptureFlow.busy` 卡死** —— 清空应用数据后触发截图（`CUSTOM_SCREEN_CAPTURE` 变回未授权），系统拉起 privacycenter 授权弹窗（`grantResult=[2]`），但应用侧**没有任何** `CUSTOM_SCREEN_CAPTURE granted=` 日志，`ensurePermission` 的 await 没回来，于是 `busy` 一直为 true，之后再按快捷键只会打 `skip: busy or too soon`，直到进程重启。弹窗被注入点击是点不掉的（VERIFY 坑 3），本轮没继续查。

## 已知限制（结论与证据在 SPEC-AND-TRUTH，本文不复制）

- 贴图**不能浮在其它应用之上**（SPEC-AND-TRUTH 2.1 / 2.2）
- 贴图窗口四角有系统给的约 40px 圆角（2.3 / 2.4）
- 托盘图标只在应用**还有进程活着**时存在；「退出」或进程被杀后图标消失（SPEC-AND-TRUTH 3.3）
- 托盘图标左键**必然弹面板**，取消不掉；"点一下直接截图"平台不支持（3.3）
- 全局快捷键**修饰键必填**（做不出裸 F1）、组合**全局排他**；默认 Ctrl+Shift+A，可在欢迎窗口里改（3.2）
- 图片比较的基点不稳健（候选 3）

## 技术债与触发重构的阈值

- 没有任何自动化测试；真机取证产物在 `.verify/`（`.gitignore` 已忽略，**不入库**），所以证据链只有屏幕截图与日志摘录，没有可复现的脚本。
- `ImageDiff` 是纯计算、可脱离设备验证 —— 想做回归就先补它的测试（待办 6）。
- 一旦要做"贴图浮在其它应用之上"或"去圆角"，必须切到 `TYPE_FLOAT` + ACL 受限权限，会同时牵动 `PasteAbility`、权限声明与验证流程 —— 那时再开专项，别顺手改。
