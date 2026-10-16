# 状态看板

**只写"此刻"**：待办做完就删（历史交给 `git log`），新增结论直接覆写对应条目，不留"早先是 A 后来改成 B"的叙事。
过程流水账在 [archive/HISTORY.md](archive/HISTORY.md)（默认不读），平台结论在 [SPEC-AND-TRUTH.md](SPEC-AND-TRUTH.md)。

## 基线

| 项 | 值 |
| --- | --- |
| 真机 | HAD-W32（HUAWEI MateBook Pro）；2026-10-16 实测 `const.ohos.apiversion=24`、`const.ohos.fullname=OpenHarmony-6.1.1.135`。本节早前记的 "HarmonyOS 7.0.0.23 / 设备 API 26" 与这台物理设备不符 —— 那台是何环境**未验证**（本机 `%LOCALAPPDATA%\Huawei\Emulator\deployed` 下有 "MateBook Pro" 镜像） |
| 显示 | 3120x2080 px，1vp = 1.9px |
| bundle | `com.youz.ohsnipaste` |
| 代码基线 | `1862a6c`（其后 `6592110` 及之后仅改文档，代码未动） |
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
| 贴图窗口 | ✅ | `pin window 1200x700 for image 1200x700`；无边框、可拖动、右键菜单可用 |
| 复制 / 保存 | ✅ | `ImageShare: copied to clipboard`；保存弹系统对话框、默认名 `snipaste_20261016_124328.png` |
| 比较 | ✅ | 同区域 `差异 0 px / 400000 px (0.00%)`；时钟区域 `差异 179 px / 27000 px (0.66%) · 区域 15×21 @(282,18)` |
| 首次启动不截图 | ✅ | `onCreate` → `skip: first launch (by design)`；再激活 → `onNewWant -> capture` |
| 状态栏托盘入口 | ✅ | `TrayEntry: tray icon registered`；折叠区出现线稿图标，点它 → `StartUIExtension: pages/TrayPanel`；面板内「开始截图」→ `CaptureFlow: main window hidden` → `SelectionPage ... shot_*.png`；「退出」→ `pidof` 为空、托盘插件数 8→7、图标槽位暗像素 309→0 |

## 模块健康度

| 模块 | 位置 | 状态 |
| --- | --- | --- |
| 入口编排 | `common/CaptureFlow.ets` | ✅ 静默期 / 去抖 / busy 防重 / pick 降级齐备；⚠️ 截图前 `minimize()` 的顺序待复核（待办 1） |
| 截图 | `common/ScreenCapturer.ets` | ✅ 无参 `capture()` + `pick()` 降级；带参 `capture()` 这条路已走死 |
| 选区 | `pages/SelectionPage.ets` + `selectionability/` | ✅ 框选 / 8 把手 / 4× 放大镜 / 方向键 / 5 个操作条动作 |
| 贴图 | `pages/PastePage.ets` + `pasteability/` | ✅ 1:1 显示、拖动、右键菜单；置顶范围与圆角是平台限制（非缺陷） |
| 比较 | `common/ImageDiff.ets` + `common/PinRegistry.ets` | ⚠️ 算法按需求实现，基点在框选位置变化后失准（限制，见 SPEC-AND-TRUTH 候选 3） |
| 分享 | `common/ImageShare.ets` | ✅ 剪贴板 + 系统保存对话框 |
| 传值 / 落盘 | `common/PinPayload.ets`、`common/PinStore.ets` | ✅ 窗口 id + AppStorage；fd 解码，固定 RGBA_8888 |
| 常驻入口 | `tray/TrayEntry.ets` + `tray/TrayStatusBarExt.ets` + `pages/TrayPanel.ets` | ✅ 注册/摘除、左键面板（开始截图 / 退出）均真机跑通；⚠️ 面板冷启动约 2.4s |

## 开放待办（做完即删）

1. **待复核：触发链路相关的两条早期实测**（设备未连接，需按 [VERIFY.md](VERIFY.md) 的典型序列真机复跑）
   - `minimize()` 与截图顺序：早期实测称"先最小化自身窗口再截图会让应用进后台、`startAbility` 报 `201`"，而现行 `CaptureFlow` 正是"申请权限 → `minimize()` → 截图 → `startAbility`"（`common/CaptureFlow.ets:44`）。
   - VERIFY 里"选区窗口开着时再 `aa start` 不会再触发截图"：当时触发点只有 `onPageShow`，现在 `onNewWant` 也会触发。
2. **待确认：暗色模式启动窗口** —— `entry/src/main/resources/dark/element/color.json` 的 `start_window_background` 仍是 `#000000`（`base` 已改 `#01000000`）。暗色模式下激活瞬间可能仍冒出纯黑窗口；未实测。
3. 比较基点稳健化（方案见 [SPEC-AND-TRUTH.md](SPEC-AND-TRUTH.md) 候选 3）—— 需你确认是否偏离最初指定的算法。
4. 多贴图管理（透明度、滚轮缩放、一键关全部、贴图列表）。
5. 比较入口 UX（贴图右键菜单「设为比较基准」等）。
6. `ImageDiff` 单元测试（纯计算，可脱离设备）。
7. 换新版本系统后复测 `excludeFromDock`（本机实测无效，配置已保留）。

## 已知限制（结论与证据在 SPEC-AND-TRUTH，本文不复制）

- 贴图**不能浮在其它应用之上**（SPEC-AND-TRUTH 2.1 / 2.2）
- 贴图窗口四角有系统给的约 40px 圆角（2.3 / 2.4）
- 应用运行时任务栏必然有一个图标（SPEC-AND-TRUTH 3.1）
- 托盘图标只在应用进程存活期间存在：平台没有给三方应用后台常驻服务，进程被杀或点面板「退出」后图标即消失（SPEC-AND-TRUTH 3.3）
- 第三方做不了全局快捷键（3.2）
- 图片比较的基点不稳健（候选 3）

## 技术债与触发重构的阈值

- 没有任何自动化测试；真机取证产物在 `.verify/`（`.gitignore` 已忽略，**不入库**），所以证据链只有屏幕截图与日志摘录，没有可复现的脚本。
- `ImageDiff` 是纯计算、可脱离设备验证 —— 想做回归就先补它的测试（待办 6）。
- 一旦要做"贴图浮在其它应用之上"或"去圆角"，必须切到 `TYPE_FLOAT` + ACL 受限权限，会同时牵动 `PasteAbility`、权限声明与验证流程 —— 那时再开专项，别顺手改。
