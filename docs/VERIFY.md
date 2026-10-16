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
2. **选区窗口开着时再 `aa start` 不会再触发截图**：页面已可见，`onPageShow` 不重复触发。
   要重新截图必须先让上一个选区结束（贴图/复制/保存/取消/Esc）。

## 典型验证序列

```powershell
# 全链路：触发 → 框选 → 贴图
& $hdc shell aa start -a EntryAbility -b com.youz.ohsnipaste
Start-Sleep -Seconds 6
& $hdc shell "uinput -M -g 400 250 1000 650 400"     # 框选
Start-Sleep -Seconds 2
& $hdc shell "uinput -M -g 661 700 662 700 80"       # 点操作条上的「贴图」
Start-Sleep -Seconds 4
& $hdc shell "hilog -x" | Select-String '/(SelectionPage|PasteAbility):'
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
