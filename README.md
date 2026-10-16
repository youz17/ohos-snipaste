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
