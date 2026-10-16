# ohos-snipaste — 协作与 AI 代理约定

HarmonyOS NEXT（ArkTS / Stage 模型）上的 Snipaste 类截图贴图应用。
真机：HAD-W32 / HarmonyOS 7.0.0.23（设备 API 26），显示 3120x2080px，1vp = 1.9px。

## 硬性纪律

- 说"已完成 / 已修复 / 已通过"之前，必须真的跑过验证命令，并引用输出。没有输出就不下结论。
- 破坏性操作（删文件、改历史、覆盖配置）先说明会失去什么，再执行。
- 只改必须改的：不做顺手重构、不删别人的死代码；但自己改动造成的孤儿（失效的导入/常量/方法）要清掉。
- 不确定就停下来说清楚，不要在两种理解里默默选一种。
- 平台结论（"这个 API 能不能用"）必须带证据等级：真机实测 > SDK 定义/schema > 推测；
  只有推测的必须写明"未验证"，不许当真值引用。

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

`EntryAbility`（不可见主窗口，被激活即交给 `CaptureFlow`）→ `SelectionAbility`（全屏铺冻结画面、
自绘选区与操作条）→ `PasteAbility`（multiton，每张贴图一个无装饰置顶窗口）。
细节见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 任务路由

| 要做什么 | 先读 |
| --- | --- |
| 改任何代码 | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 的「实现雷区」 |
| 判断某平台能力行不行 | [docs/SPEC-AND-TRUTH.md](docs/SPEC-AND-TRUTH.md)（先扫证伪墓地，别重走死胡同） |
| 报"已完成 / 已通过" | [docs/VERIFY.md](docs/VERIFY.md) 的取证流程，基线看 [docs/STATUS.md](docs/STATUS.md) |
| 说"某功能还没做" | [docs/STATUS.md](docs/STATUS.md) 的开放待办 |

## 已知限制（不是 bug，是平台约束）

结论、证据与候选方案都在 [docs/SPEC-AND-TRUTH.md](docs/SPEC-AND-TRUTH.md)，不要试图顺手绕过：

- 贴图窗口**不能浮在其它应用之上**（`WINDOW_TOPMOST` 只保证在本应用窗口之上）。
- 贴图窗口四角有系统给的约 40px 圆角，`setWindowCornerRadius` 对主窗口直接报 1300004。
- 图片比较的基点（第一个非背景像素）在框选位置变化后会失准。
- 应用运行时任务栏必然有一个图标：`excludeFromDock: true` 已加但实测无效，第三方也无法往
  时间/输入法那排（状态栏托盘）放图标。
- 第三方做不了全局快捷键：`inputConsumer.on('hotkeyChange')` 注册成功但按键不回调（它是"配置变更"
  通知），`on('keyPressed')` 文档限定前台；系统快捷键表只读、`shortcuts.json` 无键位字段。

## 文档纪律（防腐败六条）

1. **一事实一落点**：待办只在 [STATUS.md](docs/STATUS.md)；现行设计与实现雷区只在
   [ARCHITECTURE.md](docs/ARCHITECTURE.md)；平台能力真值只在 [SPEC-AND-TRUTH.md](docs/SPEC-AND-TRUTH.md)；
   验证手法只在 [VERIFY.md](docs/VERIFY.md)。跨文档只给链接，**不复制**结论、配置或统计数字。
2. **L2 只覆写、不写编年史**：直接改成当前最新定案，删掉"早先是 A 后改成 B"的过程叙述
   （演变过程留给 [docs/archive/HISTORY.md](docs/archive/HISTORY.md)）。
3. **待办即焚**：TODO 做完并验证后当场从 STATUS 删除，不在看板里留"已完成清单"（历史交给 `git log`）。
4. **推翻必挂牌、作废即删除**：推翻旧结论时，更新 L2 真值并在证伪墓地登记，同时在被推翻的旧 L3 文档首行加
   `> ⚠️ 状态：已被 <新文档> 替代/更正`（archive 只增不改，靠挂牌保追溯）。
   若某篇文档整体作废，**直接删除**，不要留"已被替代"的路标文件；需要回溯原文用 `git log --follow -- <path>`。
5. **文档与验证同提交**：凡涉及契约、行为或统计数字的改动，必须在同一 commit 里跑通验证命令，
   并同步对应的 L2 文档，杜绝代码与文档漂移。
6. **文档改动自动提交**：一批文档改完、链接校验通过后，**直接 `git add` + `git commit` 提交，不必再问**，
   提交信息用 `docs: <做了什么>`；只改文档的提交不要夹带代码改动（代码改动照常走普通流程）。

## 文档索引

| 文档 | 内容 | 更新方式 |
| --- | --- | --- |
| [README.md](README.md) | 定位与能力边界、构建/安装/触发、目录结构 | 低频，随边界与工具链变更 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 三层 Ability 与触发链路、数据流、截图/比较算法、实现雷区 | 就地覆写 |
| [docs/SPEC-AND-TRUTH.md](docs/SPEC-AND-TRUTH.md) | 平台能力现行真值、证伪墓地、候选方案 | 就地覆写 |
| [docs/STATUS.md](docs/STATUS.md) | 当前基线、已跑通环节、开放待办、待复核项 | 就地覆写 |
| [docs/VERIFY.md](docs/VERIFY.md) | 真机验证手册：hdc/uinput 驱动、截图取证、像素比对 | 低频 |
| [docs/archive/HISTORY.md](docs/archive/HISTORY.md) | 多轮反馈的过程流水账 | 只增不改，默认不读 |
