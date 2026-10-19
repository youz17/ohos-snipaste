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
   例：判断全局快捷键 → "注册成功"不等于能用、"注册失败"也不等于不能用：订阅跟着**注册它的进程**活，
   进程一退出就没了（本项目曾把注册写在会 `terminateSelf` 的 `EntryAbility` 里，于是得出"平台不支持"的反向结论）。
   做法是注册在常驻进程 → 注入组合键 → 看回调日志 + 焦点窗口有没有收到 `DispatchKeyEvent`。

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
5. 面板里的按钮位置（实测）：自上而下是「开始截图」（蓝色 `#2563EB`）、「使用说明」（浅灰底黑字）、「退出」（浅灰底红字）。
   位置会随面板漂移，别硬编码：截图后在面板区域（本机 `x 2300..3120, y 1500..2050`）按 `#2563EB` 取每行像素数 > 300 的连续行段，
   行段中点就是「开始截图」的 y，x 取面板中线；另外两个按钮按行距往下排（每个按钮 40vp + 间距 10vp）。
6. **托盘图标自己也会漂**（随折叠区内容增减、重启后都会变，**不要硬编码坐标**）。定位办法：先截一张"应用在跑"
   的托盘展开图，`force-stop` 应用后再展开截一张，两张相减 —— 唯一消失的那一小块（约 29×29px）就是我们的图标。
   实测过两组值：`^` `(2390,2020)` / 图标 `(2502,1877)`（2026-10-16 白天），设备重启后变成 `^` `(2330,2005)` /
   图标 `(2765,1840)`。展开面板用 `^`，展开与点图标要写在同一条命令里、间隔 ~900ms，否则折叠区会收起。
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

## 验证全局快捷键（Ctrl+Shift+A）

```powershell
& $hdc shell aa force-stop com.youz.ohsnipaste
& $hdc shell aa start -a EntryAbility -b com.youz.ohsnipaste    # 只做引导
Start-Sleep -Seconds 8
& $hdc shell "hilog -r" | Out-Null
# Ctrl+Shift+A：2072 = CTRL_LEFT，2047 = SHIFT_LEFT，2017 = A；按下/抬起写在同一句里
& $hdc shell "uinput -K -d 2072 -d 2047 -d 2017 -i 60 -u 2017 -u 2047 -u 2072"
Start-Sleep -Seconds 4
& $hdc shell "hilog -x" | Select-String 'TrayAbility: (hotkey|capture)|capture ok|SelectionPage: windowId'
& $hdc shell "hidumper -s WindowManagerService -a '-a'" | Select-String 'ohsnipaste'
```

判据三条：

1. 启动时有 `TrayAbility: hotkey registered: Ctrl + Shift + A`，按键时有 `TrayAbility: hotkey fired {...}`；
   若报 `4200002` / `4200003`，说明组合被系统或别的应用占了（排他），换键位再试。
   （组合来自 preferences：改过键之后这行会打出新的组合名。）
2. `capture ok: 3120x2080` + `SelectionPage: windowId=...`，dump 里选区窗口是 `[0,0,3120,2080]`。
3. **按键没漏给前台窗口**：同一时刻 `hilog -x` 里不该有发给焦点窗口的 `WMSEvent: DispatchKeyEvent`。
   想更严格就先 `aa start -b com.huawei.hmos.notepad -a MainAbility`，让别的应用在前台再按。

> 这条顺带给了一个**命令行触发截图**的办法（以前只有点面板一条路）：注入组合键即可。

## 验证欢迎窗口 / 改键 / 托盘唤起

```powershell
# 首次启动：只能靠清数据回到"没看过欢迎窗口"的状态（代价：CUSTOM_SCREEN_CAPTURE 回到未授权，下次截图要人工点一次授权）
& $hdc shell "bm clean -n com.youz.ohsnipaste -d"
& $hdc shell "aa force-stop com.youz.ohsnipaste"
& $hdc shell "aa start -a EntryAbility -b com.youz.ohsnipaste"
Start-Sleep -Seconds 4
& $hdc shell "hilog -x" | Select-String '/(EntryAbility|Welcome):'
& $hdc shell "hidumper -s WindowManagerService -a '-a'" | Select-String 'ohsnipaste'
```

判据四条：

1. **首次启动弹窗**：`onCreate ... welcome=yes` → `welcome window shown` → `welcome window 1064x988 px`，
   窗口 dump 是 `ohsnipaste0 [ 1028 546 1064 988 ]`（560×520vp 居中）；截图里应看到不透明浅色窗口，
   内容有名字、`Ctrl + Shift + A`、对比说明、Esc 提示。
2. **后续启动不弹**：再 `aa start` 一次（或干脆 force-stop 后重开），日志只有
   `onCreate ... welcome=no` → `repeat launch: main window minimized` → `bootstrap done`；
   `hidumper` 里查不到窗口，屏幕截图上没有任何窗口（含透明窗口）。
3. **改键（跨进程 + 持久化）**：点窗口里的「修改」（先截图定位，本机 ≈ `(1989,877)`；点了之后按钮变「取消」、
   出现"请按住 Ctrl / Shift / Alt 再按一个键"），注入新组合：
   ```powershell
   & $hdc shell "uinput -K -d 2072 -d 2045 -d 2017 -i 60 -u 2017 -u 2045 -u 2072"   # Ctrl+Alt+A
   ```
   应依次出现 `HotkeySignal: hotkey change published` → 常驻进程 `hotkey re-registered: Ctrl + Alt + A` →
   `Welcome: hotkey applied`，界面显示「已生效」。再 `aa force-stop` + `aa start`，冷启动日志应为
   `hotkey registered: Ctrl + Alt + A`（证明落盘生效）。改完记得改回来。
4. **托盘唤起 / Esc 退出**：托盘面板「使用说明」→ `TrayPanel: welcome window requested` →
   `onCreate ... forced=yes` → 窗口出现；把窗口最小化（dump 里 ZOrd 变 `-1`）再点一次 → `onNewWant -> bring
   welcome window to front` / `welcome window restored`，ZOrd 回到正数。最后 `uinput -K -d 2070 -u 2070` →
   `EntryAbility: onDestroy`、`hidumper` 无窗口、`ps -ef` 里只剩常驻进程。

> 面板按钮位置会随内容漂：本轮面板高度从 176vp 调到 232vp（多一个「使用说明」），旧坐标不再可用。

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
# 面板「开始截图」：蓝按钮 #2563EB，本机 ≈ (2706, 1668)（面板改成 232vp 高、多一个「使用说明」之后的位置）
& $hdc shell "uinput -M -g 2706 1668 2707 1668 80"
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

## 验证"贴图窗口拖动跟手"（抖动回归必跑）

**判据三条**，任何一条不符都算失败：

1. **位移 = 光标位移**（1:1，无 ×1.9、无过冲）。逐次记录前后矩形，别只看"能动"。
2. **松手后窗口纹丝不动** —— 只移动光标（`uinput -M -m`，不带按键）不应产生位移。
3. **右键不误触拖动** —— 弹出菜单时窗口位置不变。

```powershell
function Rect { (& $hdc shell "hidumper -s WindowManagerService -a '-a'" | Select-String 'ohsnipaste').Line }
Write-Output "before: $(Rect)"
& $hdc shell "uinput -M -g 500 400 900 700 400"    # 慢拖 +400,+300
Start-Sleep -Milliseconds 600
Write-Output "after: $(Rect)"                        # 应正好 +400,+300
```

**轨迹取证（要证明"单调、不回退"时用）**：临时在 `pages/PastePage.ets` 的 `init()` 里挂
`win.on('windowRectChange', o => hilog.info(..., 'rect %d,%d', o.rect.left, o.rect.top))`，
拖一次后 `hilog -x | Select-String 'rect'` 取序列，按时间切段后检查 x/y 是否单调、步长是否均匀；**验完把这行删掉**。
（2026-10-19 基线：拖 400px/400ms 得 57 个采样、x/y 零回退、末两点相同=收敛；系统侧同时打
`WMSLayoutPc: StartMovingWithCoordinate: offset:[..] pointer:[..]`，offset 应等于"光标 - 窗口左上角"。）

**两条容易误判的现象**：

- 拖到**屏幕边缘**会触发系统窗口吸附，窗口被改成半屏（`[1571 0 1549 1955]`），再拖一次恢复原尺寸。这是平台行为，不是抖动（见 SPEC-AND-TRUTH 2.8）。
- 中途插一条 `uinput -M -g x y x+1 y` 这种"原地点击"实际是 1px 拖动，窗口会跟着走 1px —— 别当成漂移。

## 清理

```powershell
& $hdc shell "aa force-stop com.youz.ohsnipaste"
& $hdc shell "hidumper -s WindowManagerService -a '-a'" | Select-String 'ohsnipaste'   # 应为空
```
