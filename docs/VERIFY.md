# 真机验证手册

本项目的"完成"必须以真机证据为准。这里记录已验证可行的取证手法，以及踩过的坑。

## 工具与路径

```powershell
$hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$py  = 'C:\Users\youz\workspace\scoop\apps\python\current\python.exe'   # 装了 PIL + numpy
```

## 驱动设备

**鼠标拖拽**（也当点击用：起止同点即可）：

```powershell
& $hdc shell "uinput -M -g 400 250 1000 650 400"   # 从 (400,250) 拖到 (1000,650)，400ms
& $hdc shell "uinput -M -g 400 250 401 250 80"     # 在 (400,250) 点一下
```

坐标是屏幕物理像素；选区窗口全屏时与组件内坐标 1:1。

**右键**（坑！）：`uinput -M -c 1` 是在**默认位置（屏幕左上角）**右键，不是当前光标处。
要定位右键必须一条命令里连着写：

```powershell
& $hdc shell "uinput -M -m 400 300 -i 200 -d 1 -i 200 -u 1"   # 移到 (400,300) 再右键
```

**键盘**：`& $hdc shell "uinput -K -d 2014 -u 2014"`（左方向键）。
用到的键码：UP=2012 DOWN=2013 LEFT=2014 RIGHT=2015 SHIFT_L=2047 SHIFT_R=2048 ESC=2070。

## 取证

**截图 + 拉回本地**：

```powershell
& $hdc shell "snapshot_display -f /data/local/tmp/s.jpeg"
& $hdc file recv /data/local/tmp/s.jpeg 'D:\tools\ohos-snipaste\.verify\s.jpeg'
```

注意：`hdc file recv` **读不到应用沙箱**（`/data/storage/el2/base/...` 权限拒绝），
所以产物内容只能靠屏幕截图 + 像素分析验证。截图可直接用读图能力看，也可用
Python+PIL/numpy 做精确判断（例如判断某个采样点是否等于预期颜色）。

本地取证产物放在 `.verify/`，该目录已被 `.gitignore` 忽略、**不入库**。因此结论不能只留在截图里：
把关键日志行/坐标与截图文件名一起写进 L2 文档（[SPEC-AND-TRUTH.md](SPEC-AND-TRUTH.md) 的平台结论、
[STATUS.md](STATUS.md) 的基线、[ARCHITECTURE.md](ARCHITECTURE.md) 的设计约束），截图只作为本地旁证。

**窗口状态**（判断窗口是否可见、位置、层级）：

```powershell
& $hdc shell "hidumper -s WindowManagerService -a '-a'" | Select-String 'ohsnipaste'
```

各列里：第 4 列是 `windowId`，`ZOrd` 越大越靠上，**`ZOrd = -1` 表示被隐藏/最小化**。
行尾方括号是 `[left top width height]`。

**日志**：`hilog -r` 清空、`hilog -x` dump，配合 `Select-String '/(SelectionPage|ImageDiff):'` 过滤。

## 两个害我白跑一轮的坑

1. **贴图窗口在别的窗口获得焦点后会 `ZOrd=-1`（被隐藏）**。若先点了桌面/别的应用再右键
   贴图，测的是"不可见窗口"，结论无效。正确顺序：先创建贴图，期间不点别处，再操作它。
2. **截图入口只有一个，而且没有命令行等价物**：`aa start -a EntryAbility` 现在只做引导、**不截图**；
   面板发的是**应用内公共事件**（`com.youz.ohsnipaste.action.CAPTURE`，见 `tray/CaptureSignal.ets`），
   命令行发不了 —— 而 `aa start -a TrayAbility` 既不会截图，还会把应用重新拉进任务栏（见
   [SPEC-AND-TRUTH.md](SPEC-AND-TRUTH.md) 3.1）。要截图只能真的点：状态栏托盘图标 → 面板「开始截图」。
   另外选区窗口开着时不会重复触发（`CaptureFlow` 的 busy/去抖拦着），要重新截图必须先结束上一个选区
   （贴图/复制/保存/取消/Esc）。

## 还有两个坑

3. **安全类权限弹窗不理会注入的点击**。`CUSTOM_SCREEN_CAPTURE` 的授权弹窗（"允许…截取你的屏幕？"）
   用 `uinput` 点按钮中心两次都毫无反应，应用侧也没有任何日志（注入输入被安全 UI 过滤了）。
   这类弹窗只能人工点，验证脚本走到这一步必须停下来叫人。
4. **干净卸载会重置 user_grant 权限**。`hdc uninstall` + 重装后 `CUSTOM_SCREEN_CAPTURE` 变回未授权，
   应用会卡在授权弹窗上（此时 `hidumper` 里只有 Entry 窗口、没有选区/贴图窗口，是典型症状）。

## 判断"平台能不能做"的三板斧

1. **读 API 定义**：`ets\api\@ohos.*.d.ts` 里的 `@permission`、`@since`、以及那句人话描述
   （例：`on('keyPressed')` 的 *"If the current application is in the foreground focus window…"*）。
2. **读 schema**：`toolchains\modulecheck\*.json` 决定 manifest/资源文件能写什么字段
   （例：`shortcuts.json` 只有 `shortcutId/label/icon/visible/wants`，所以快捷方式带不了键位）。
3. **真机实测**：注册 + 注入事件 + 看日志里"谁收到了"。
   例：判断全局快捷键 → 注册成功（`SubscribeHotkey`）≠ 能用；注入 `Ctrl+Shift+A` 后
   前台是 `WMSEvent: DispatchKeyEvent`（被当普通按键），后台则毫无日志 → 不可用。

第 3 步必须有，第 1、2 步只能给"大概行不行"。

> 续上：**第 1 步要先找对目录**。SDK 分成 `openharmony/` 与 `hms/` 两个分支，PC 桌面类能力
> （`@hms.pcService.*`，如 `statusBarManager`）只在 `hms/ets/api` 下 —— 只搜 `openharmony/` 会得出
> "平台没有这个能力"的错误结论（见 [SPEC-AND-TRUTH.md](SPEC-AND-TRUTH.md) 证伪墓地 6）。

## 状态栏托盘图标的验证手法

1. 冷启动（`aa start -a EntryAbility -b com.youz.ohsnipaste`）。引导链路该出现三行日志：
   `TrayEntry: tray icon registered` → `EntryAbility: TrayAbility attached (attempt N)`（**首次常报
   `16000067 The StartOptions check failed`，第 2 次才成功，属预期**）→ `bootstrap done, main ability terminated`。
   之后 `ps -ef | grep youz` 应该只剩 `...:entry:TrayAbility:0` 这一个进程。
2. 点状态栏右下角的 `^` 展开折叠区（本机 ≈ `(2390, 2020)`）。它是**切换**语义，且折叠区会自动收起 ——
   展开和点图标必须写在同一条命令里（间隔 ~900ms），否则点空。图标位置见第 6 条。
3. 展开的面板里是各应用的状态栏插件图标（含 WPS 等三方应用）。**给自绘图标一个独有颜色**再数像素最稳：
   例如"透明底 + 品红圆"，用 PIL 数 `(r>180)&(b>180)&(g<110)` —— 装上时 545 px、卸载后 0 px。
4. 点图标：`uinput -M -g <iconX> <iconY> <iconX+1> <iconY> 80`。**面板要等 ≥3 秒**才出现（扩展冷启动实测约 2.4s），
   抢拍早了只能看到桌面。成功时日志依次出现 `StartUIExtension: element: com.youz.ohsnipaste/TrayStatusBarExt` →
   `TrayExt: onSessionCreate` → `AceUiExtensionComponent: StartUIExtension: pages/TrayPanel`。
5. 面板里的按钮位置（实测）：「开始截图」居中的蓝色按钮（`#2563EB`，约 4.8 万像素）。位置会随面板漂移，
   别硬编码：截图后在面板区域（本机 `x 2300..3120, y 1500..1960`）按 `#2563EB` 取每行像素数 > 300 的连续行段，
   行段中点就是按钮的 y，x 取面板中线（本机 ≈ 2638~2700）。「退出」是下方浅灰底红字。
6. **托盘图标自己也会漂**（随折叠区内容增减）。定位办法：先截一张"应用在跑"的托盘展开图，`force-stop` 应用
   后再展开截一张，两张相减 —— 唯一消失的那一小块（本机 ≈ 29×29px，2026-10-16 在 `x 2488..2517, y 1863..1892`）
   就是我们的图标。实测点它的坐标 `(2502, 1877)`；展开面板用 `^`（本机 ≈ `(2390, 2020)`），
   两次点击要写在一条命令里、间隔 ~900ms，否则折叠区会收起。
7. **别被 `1010710001 The size of the pixelmap exceeds the limit` 骗了**：它每次都打，图标照样渲染
   （见 [SPEC-AND-TRUTH.md](SPEC-AND-TRUTH.md) 3.3）。判成败只看第 5 步的日志与画面。
8. **测"截图里有没有面板"**：面板可见时截图会把面板烙进冻结画面。判别法是关掉选区窗口（`uinput -K -d 2070 -u 2070`）
   再截同一块区域 —— 暗像素从 3438 掉到 0 就说明它在图里而不是实时窗口。也可直接截"选区窗口正开着"时的
   面板区域（本机 `(2250,1600)-(3050,2000)`）：里面只剩被压暗的桌面就对了。
9. **测"任务栏有没有我们"**：裁 `(2150,1930)-(3120,2080)` 看有没有自绘的蓝色方形图标（带运行点）。三个时刻都要干净：
   引导后、选区窗口开着时、关掉选区窗口后。
10. **测"常驻 Ability 有没有窗口"**：`hidumper -s WindowManagerService -a '-a' | Select-String ohsnipaste`
    在"选区窗口开着"时只该出现 `SelectionAbility` 那一行，任何时刻都不该出现 TrayAbility 的窗口；
    日志里 `refreshSCBSceneContainerSession : add: <id>, com.youz.ohsnipaste, , entry, TrayAbility` 一次都不该有
    （有它就意味着走了 `startAbility`，应用会常驻任务栏，见墓地 10）。
11. 换设备安装前先看签名：`hdc shell bm get -u` 得到的 UDID 必须在该 `.p7b` 的 `device-ids` 里，
    否则 `hdc install` 报 `9568423`。

## 典型验证序列

```powershell
# 全链路：引导 → 托盘面板触发 → 框选 → 贴图
& $hdc shell aa force-stop com.youz.ohsnipaste
& $hdc shell aa start -a EntryAbility -b com.youz.ohsnipaste    # 只做引导，不截图
Start-Sleep -Seconds 10
# 展开折叠区 → 点我们的托盘图标（坐标见上一节第 6 条；这里用 2026-10-16 实测值）
& $hdc shell "uinput -M -g 2390 2020 2391 2020 80"
Start-Sleep -Milliseconds 900
& $hdc shell "uinput -M -g 2502 1877 2503 1877 80"
Start-Sleep -Seconds 6                                          # 面板冷启动 ~2.4s
# 面板「开始截图」：蓝按钮 #2563EB，本机 ≈ (2638, 1769)
& $hdc shell "uinput -M -g 2638 1769 2639 1769 80"
Start-Sleep -Seconds 4
& $hdc shell "uinput -M -g 400 250 1000 650 400"                # 框选
Start-Sleep -Seconds 2
& $hdc shell "uinput -M -g 661 700 662 700 80"                  # 点操作条上的「贴图」
Start-Sleep -Seconds 4
& $hdc shell "hilog -x" | Select-String '/(CaptureSignal|TrayAbility|SelectionPage|PasteAbility):'
```

> 操作条按钮位置随选区变化：条形 356vp 宽、右对齐选区右下角（外侧 8vp），
> 5 个按钮等宽。`ux = (selRight - 356) * 1.9`，`uy = selBottom + 8 + 18`（vp→px ×1.9）。
> 与其硬算，不如先截一张图确认按钮位置再点。

**日志是主证据**：`crop x=.. y=..` 证明选区换算正确；`pin window WxH for image WxH` 证明 1:1；
`ImageDiff: 差异 N px / 比对 M px` 证明比较结果。像素探针用来交叉验证"看到的确实是这样"。

## 清理

```powershell
& $hdc shell "aa force-stop com.youz.ohsnipaste"
& $hdc shell "hidumper -s WindowManagerService -a '-a'" | Select-String 'ohsnipaste'   # 应为空
```
