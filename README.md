# 截图贴图（ohos-snipaste）

HarmonyOS NEXT（ArkTS / Stage 模型）上的 Snipaste 类截图 + 贴图工具。
真机：HAD-W32（HUAWEI MateBook Pro），3120x2080px，1vp = 1.9px，bundle `com.youz.ohsnipaste`；
系统版本与 API 等级以 [docs/STATUS.md](docs/STATUS.md) 的基线为准。

## 能力边界

一次完整手感：**激活 → 冻结整屏 → 框选 → 复制 / 保存 / 贴图 / 比较**。

| 能力 | 现状 |
| --- | --- |
| 全屏截图 | `CUSTOM_SCREEN_CAPTURE`（normal + user_grant，**无需**华为 ACL 审批） |
| 区域框选 | 铺满屏幕的冻结画面；遮罩、8 个调整把手、4× 放大镜、实时像素尺寸；方向键微调、Shift+方向键改大小、Esc 退出 |
| 复制 / 保存 | 写系统剪贴板 / 走系统保存对话框导出 PNG |
| 贴图 | 独立无装饰置顶窗口、按原始像素 1:1 显示、拖动移动、右键菜单（复制 / 保存为图片… / 关闭） |
| 图片比较 | 与最后一张贴图对齐后逐像素比对，差异图另开窗口并给出一行结论 |
| 常驻入口 | 状态栏右下角折叠区（`^`）里的托盘图标；左键面板提供「开始截图 / 退出」。图标由挂在状态栏项上的常驻进程持有，应用**没有窗口、也不占任务栏** |
| 全局快捷键 | **Ctrl+Shift+A** 直接起截图（`inputConsumer.on('hotkeyChange')`，无需权限、应用没有窗口也生效） |
| 降级 | 未授权或截图失败 → 系统截图选择器 `screenshot.pick()`，把结果直接贴出 |

平台做不到（每条都有实测证据，见 [docs/SPEC-AND-TRUTH.md](docs/SPEC-AND-TRUTH.md)）：
贴图不能浮在**其它应用**之上、托盘图标左键必然弹面板（点一下直接截图做不到）、主窗口圆角去不掉。
全局快捷键只有一条限制：**组合必须带修饰键**（做不出 Snipaste 的裸 `F1`），且同一组合全局排他。

## 真值判据优先级

1. **真机实测** —— 日志 / 窗口 dump / 像素证据（手法见 [docs/VERIFY.md](docs/VERIFY.md)）
2. **SDK 定义与 schema** —— `ets/api/@ohos.*.d.ts` 的 `@permission` / `@since` / 注释，`toolchains/modulecheck/*.json`
3. 官方文档与推测

写进 L2 文档的每条平台结论都必须能追到第 1 或第 2 级；只有推测的必须标「未验证」。

## 构建

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
$env:NODE_HOME='C:\Program Files\Huawei\DevEco Studio\tools\node'
$env:HVIGOR_USER_HOME='D:\tools\ohos-snipaste\.hvigor'   # 把 hvigor 缓存限制在工程内
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-signed.hap`（同时产出 `-unsigned.hap`）。

`build-profile.json5` 已配置调试签名（`signingConfigs: default`，证书/Profile 在 `C:\Users\youz\.ohos\config`）。
调试签名不需要申请和审批；只有受限权限（ACL）才需要走 AppGallery Connect —— 本项目不使用 ACL。

> `HVIGOR_USER_HOME` 让 hvigor 的缓存与目录联接留在工程内；受限沙箱会拒绝创建目录联接，构建需在不受限环境执行。

## 安装与触发

```powershell
hdc install -r entry\build\default\outputs\default\entry-default-signed.hap   # 安装/更新
hdc shell aa start -a EntryAbility -b com.youz.ohsnipaste                     # 引导：注册托盘图标 + 拉起常驻进程（不截图）
hdc shell aa force-stop com.youz.ohsnipaste                                   # 清场
```

冷启动只做引导：注册托盘图标 → 拉起常驻的 `TrayAbility` → 主 Ability 退出，此后应用没有任何窗口。

两条触发路径，终点都是同一个 `CaptureFlow`：

- **全局快捷键 Ctrl+Shift+A**：在常驻进程里 `inputConsumer.on('hotkeyChange')` 注册（无需权限、不要求前台），
  按下即截图。修饰键必填、组合全局排他（被系统或别的应用占用时注册会报 `4200002` / `4200003`）。
- **状态栏托盘图标**：点右下角折叠区（`^`）里的图标 → 面板 → 「开始截图」。它发给常驻进程一个**应用内公共事件**
  （不是 `startAbility` —— 那会让应用重新出现在任务栏），并且要等 500ms 让面板收走再截。「退出」会摘掉图标并结束应用
  （图标只在应用还有进程活着时存在）。

触发链路与静默期/去抖规则见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 目录结构

```
ohos-snipaste/
├── AGENTS.md                    # AI 协作宪法：纪律、构建/验证命令、文档路由
├── README.md                    # 本文件：定位、能力边界、构建与安装
├── AppScope/                    # 应用级配置与图标（bundleName / 版本 / 分层图标）
├── build-profile.json5          # 产品与签名配置（含调试签名 default）
└── docs/
    ├── ARCHITECTURE.md          # 现行设计真值：Ability/窗口模型、数据流、算法、实现雷区
    ├── SPEC-AND-TRUTH.md        # 平台能力真值、证伪墓地、候选方案
    ├── STATUS.md                # 实时看板：基线、开放待办、待复核项
    ├── VERIFY.md                # 真机验证手册：驱动、取证、像素比对
    └── archive/HISTORY.md       # 多轮反馈的过程流水账（只增不改，默认不读）

entry/src/main/
├── module.json5                 # 三个 Ability + statusBarView 扩展 + 权限声明（含 excludeFromDock）
├── ets/
│   ├── common/
│   │   ├── CaptureFlow.ets      # 入口编排：静默期/去抖、权限、截图、落盘、拉起窗口
│   │   ├── ScreenCapturer.ets   # 权限查询与申请、capture()、pick() 降级
│   │   ├── PinStore.ets         # PixelMap ↔ PNG 沙箱落盘（fd 解码）
│   │   ├── PinPayload.ets       # 窗口 id → 图片路径/备注（AppStorage）
│   │   ├── PinRegistry.ets      # 进程内登记开着的贴图，提供比较基准
│   │   ├── ImageDiff.ets        # 基点对齐 + 逐像素比较 + 差异图
│   │   ├── ImageShare.ets       # 剪贴板 / 系统保存对话框
│   │   └── Launcher.ets         # startAbility 统一入口（选区 / 贴图）
│   ├── entryability/EntryAbility.ets               # 引导：注册托盘 + 拉起常驻进程后自己退出
│   ├── selectionability/SelectionAbility.ets       # 全屏无装饰置顶的选区窗口
│   ├── pasteability/PasteAbility.ets               # 每张贴图一个无装饰置顶窗口
│   ├── entrybackupability/EntryBackupAbility.ets   # 系统备份扩展（模板自带）
│   ├── tray/
│   │   ├── TrayEntry.ets        # 状态栏托盘图标：注册 addToStatusBar / 摘除 removeFromStatusBar
│   │   ├── TrayAbility.ets      # 挂在状态栏项上的常驻 Ability（STARTUP_HIDE、无窗口；截图链路 + 全局快捷键注册）
│   │   ├── CaptureSignal.ets    # 面板 → 常驻进程的跨进程触发信号（自定义公共事件）
│   │   └── TrayStatusBarExt.ets # 托盘左键面板的 statusBarView 扩展
│   └── pages/
│       ├── SelectionPage.ets    # 遮罩 + 框选 + 把手 + 放大镜 + 操作条
│       ├── PastePage.ets        # 贴图内容 + 拖动 + 右键菜单
│       └── TrayPanel.ets        # 托盘面板：开始截图 / 退出
└── resources/                   # 字符串/颜色/图标/profile（托盘与面板图标是 SVG 离屏光栅化出的 PNG）
```

## 文档导航

| 文档 | 内容 |
| --- | --- |
| [AGENTS.md](AGENTS.md) | 协作纪律、构建与验证命令、文档路由 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Ability 与扩展、触发链路、数据流、截图/比较算法、实现雷区 |
| [docs/SPEC-AND-TRUTH.md](docs/SPEC-AND-TRUTH.md) | 平台能力现行真值、证伪墓地、候选方案 |
| [docs/STATUS.md](docs/STATUS.md) | 基线、已跑通环节、开放待办、待复核项 |
| [docs/VERIFY.md](docs/VERIFY.md) | 真机驱动、取证、像素比对手法 |
| [docs/archive/HISTORY.md](docs/archive/HISTORY.md) | 多轮反馈的过程流水账（默认不读） |
