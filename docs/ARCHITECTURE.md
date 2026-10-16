# 架构

## 为什么是这个形状

Snipaste 的核心是"整个屏幕都是画布，选中什么就贴什么"。鸿蒙上第三方应用拿不到
系统级悬浮窗权限（`SYSTEM_FLOAT_WINDOW` 是 system_basic，需 ACL 审批），所以本应用
不去抢系统悬浮窗，而是**先把整屏冻结成一张图**，再在普通窗口里自绘选区——
冻结画面不需要任何特权，选区窗口就是一个全屏普通窗口。

## 三层 Ability

| Ability | 窗口形态 | 职责 |
| --- | --- | --- |
| `EntryAbility` | 主窗口**不可见**（去装饰 + 近全透明 + 空页面），用完 minimize | 入口与编排：申请权限、截图、落盘、拉起选区窗口 |
| `SelectionAbility` | 全屏、无装饰、置顶（singleton） | 显示冻结画面，自绘遮罩/选区/把手/放大镜/操作条 |
| `PasteAbility` | 每张图一个窗口、无装饰无阴影、置顶（multiton） | 显示贴图或差异图；拖动移动、右键菜单 |

入口页刻意没有任何界面元素：应用以"任务栏图标"的形式存在，被激活（`onPageShow`）
就直接开始截图。这样用户全程只看到选区窗口和贴图窗口，看不到应用主窗口。

## 数据流

```
Index.onPageShow
  └─ ScreenCapturer.ensurePermission   CUSTOM_SCREEN_CAPTURE（normal + user_grant）
  └─ ScreenCapturer.captureScreen()    无参 screenshot.capture() → 3120x2080 PixelMap
  └─ PinStore.saveAsPng(pm, filesDir, 'shot')   → files/shot_<ts>.png
  └─ Launcher.openSelection(path, w, h)         → startAbility(SelectionAbility)
  └─ hideSelfWindow()                           → 主窗口 minimize，免得透明窗口挡桌面点击

SelectionPage（全屏）
  └─ 用**本窗口 id** 从 AppStorage 取回图片路径（PinPayload）
  └─ PinStore.decode(path)  → Image 铺满窗口 = 冻结画面
  └─ onTouch 状态机：把手→缩放 / 选区内→整体移动 / 选区外→新建选区
  └─ 方向键平移、Shift+方向键改大小（步长 = 1 个截图像素）、Esc 取消
  └─ 操作条：复制 / 保存 / 贴图 / 比较 / 取消

PasteAbility（每张图一个）
  └─ 同样用窗口 id 取回路径 + 备注文字（差异窗口的结论）
  └─ 窗口尺寸 = 图片像素尺寸（1:1），超过屏幕按屏幕裁
  └─ 右键菜单：复制 / 保存为图片… / 关闭
```

### 为什么用「窗口 id + AppStorage」传数据

`windowStage.loadContent(url, storage)` 传进去的 LocalStorage，页面里的
`@LocalStorageProp` 实测读到空值（`imagePath len=0`）。改用 AppStorage、以
**该窗口自己的 id** 作 key（`PinPayload`）：每个贴图窗口是独立 Ability 实例，
各取各的，天然不会串。图片像素尺寸由页面解码后自取。

### 为什么图片要落盘再传

贴图窗口是独立 Ability，可能与本页不同进程，用文件路径传递比传内存对象可靠。
`PinStore.decode` 用 `fileIo` 打开 fd 再 `image.createImageSource(fd)`，不把路径
直接交给 `Image()`（路径/URI 解析差异会导致图片不显示）。

文件前缀有语义：

| 前缀 | 含义 | 是否参与"上一张图片" |
| --- | --- | --- |
| `shot_` | 冻结整屏图 | 否 |
| `pin_` | 贴图 | 是 |
| `diff_` | 比较结果图 | 否 |

## 截图

`ScreenCapturer.captureScreen()` 固定用**无参** `screenshot.capture()`：

- 传 `CaptureOption`（哪怕只传 `displayId` + `blackWindowIds`）会返回 `401`，且紧接着的
  无参调用会挂起不返回——这条路已经试死。
- 自身窗口不进截图的办法：截图期间把主窗口设成近全透明 + 页面清空，并保持前台。
  实测冻结画面里那块区域是桌面内容，不是我们的窗口。
- **不能**先 minimize 再截图：应用进后台后 `startAbility` 报 `201`
  （缺 `START_ABILITIES_FROM_BACKGROUND`，system_basic 拿不到），且 `restore()`
  返回 `1300004` 无法恢复。

## 图片比较（`common/ImageDiff.ets`）

按需求实现的算法：

1. 各自取**左上角像素**作为背景色。
2. 按行优先扫描，找到**第一个与背景色不同的像素**作为基点（单通道色差 > 16）。
3. 把两个基点重合，得到当前图相对参考图的位移 `offset`。
4. 在重叠区域内逐像素比对，记录差异像素数、占比、包围盒。
5. 差异图：底图 = 当前截图压暗 45%，差异像素标红；窗口左上角显示一行结论。

比对基准取自 `common/PinRegistry.ets`（**进程内**登记当前开着窗口的贴图路径，
关窗即注销），不扫沙箱目录——目录里同时有 `shot_*`/历史 `pin_*`/`diff_*`，
按文件名时间戳猜会猜错（实测猜错过一次：拿整屏图当了基准）。

已知弱点：基点是"第一个非背景像素"，可能是随裁剪位置漂移的边框而非稳定特征，
框选位置变化后对齐会失准（实测偏移 +20px 时报出 39% 差异）。候选改进见 ROADMAP。

## 权限

| 权限 | 等级 / 授权方式 | 用途 |
| --- | --- | --- |
| `ohos.permission.CUSTOM_SCREEN_CAPTURE` | normal / user_grant | 截图（首次弹授权） |
| `ohos.permission.WINDOW_TOPMOST` | normal / system_grant | 贴图窗口置于本应用窗口之上 |
| `ohos.permission.SET_WINDOW_TRANSPARENT` | normal / system_grant | `setWindowShadowEnabled(false)` 去阴影 |

刻意**没有**申请 `SYSTEM_FLOAT_WINDOW`（system_basic，需 ACL）：本应用不需要它也能
完成"冻结画面 + 自绘选区"；代价是贴图不能浮在其它应用之上（见 ROADMAP）。
