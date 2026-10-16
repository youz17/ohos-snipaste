# ohos-snipaste — 协作与 AI 代理约定

HarmonyOS NEXT（ArkTS / Stage 模型）上的 Snipaste 类截图贴图应用。
真机：HAD-W32 / HarmonyOS 7.0.0.23（设备 API 26），显示 3120x2080px，1vp = 1.9px。

## 硬性纪律

- 说"已完成 / 已修复 / 已通过"之前，必须真的跑过验证命令，并引用输出。没有输出就不下结论。
- 破坏性操作（删文件、改历史、覆盖配置）先说明会失去什么，再执行。
- 只改必须改的：不做顺手重构、不删别人的死代码；但自己改动造成的孤儿（失效的导入/常量/方法）要清掉。
- 不确定就停下来说清楚，不要在两种理解里默默选一种。

## 构建 / 安装 / 触发

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
$env:NODE_HOME='C:\Program Files\Huawei\DevEco Studio\tools\node'
$env:HVIGOR_USER_HOME='D:\tools\ohos-snipaste\.hvigor'   # 不给这个会 EPERM 写 C:\Users\<user>\.hvigor
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon
```

- 构建需要在**不受限沙箱**下跑：hvigor 会在缓存目录建目录联接（junction），沙箱会拒绝重解析点。
- 安装：`hdc install -r entry\build\default\outputs\default\entry-default-signed.hap`
- 触发一次截图：`hdc shell aa start -a EntryAbility -b com.youz.ohsnipaste`（等同于点任务栏图标）
- 清场：`hdc shell aa force-stop com.youz.ohsnipaste`

真机驱动、截图取证的完整手法见 [docs/VERIFY.md](docs/VERIFY.md)。

## 架构一句话

`EntryAbility`（无窗口，激活即截图）→ `SelectionAbility`（全屏铺冻结画面、自绘选区与操作条）
→ `PasteAbility`（multiton，每张贴图一个无装饰置顶窗口）。细节见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 已经踩过的坑（别重走）

构建/API 层面的坑集中在 [README.md](README.md) 的"踩过的坑"一节；真机验证手法上的坑在
[docs/VERIFY.md](docs/VERIFY.md)。改代码前建议先扫一眼这两处，里面每一条都是实测结论。

## 已知限制（不是 bug，是平台约束）

- 贴图窗口**不能浮在其它应用之上**（`WINDOW_TOPMOST` 只保证在本应用窗口之上）。
- 贴图窗口四角有系统给的约 40px 圆角，`setWindowCornerRadius` 对主窗口直接报 1300004。
- 图片比较的基点（第一个非背景像素）在框选位置变化后会失准。
- 应用运行时任务栏必然有一个图标：`excludeFromDock: true` 已加但实测无效，第三方也无法往
  时间/输入法那排（状态栏托盘）放图标。
- 第三方做不了全局快捷键：`inputConsumer.on('hotkeyChange')` 注册成功但按键不回调（它是"配置变更"
  通知），`on('keyPressed')` 文档限定前台；系统快捷键表只读、`shortcuts.json` 无键位字段。

各条的实测证据与候选方案见 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 文档索引

| 文档 | 内容 |
| --- | --- |
| [README.md](README.md) | 进度、真机验证结果、踩坑记录、权限说明、构建与安装 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 三层 Ability/窗口模型、数据流、截图与比较算法 |
| [docs/VERIFY.md](docs/VERIFY.md) | 真机验证手册：hdc/uinput 驱动、截图取证、像素比对 |
| [docs/ROADMAP.md](docs/ROADMAP.md) | 已知限制、候选改进、待定决策 |
