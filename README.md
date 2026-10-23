# Codex Quota for macOS

一个原生 macOS 菜单栏应用，用可移动的 Liquid Glass 桌面面板查看 Codex 5h 额度、周额度与近七天 Token 用量。

Native, movable glass panels for your Codex quota. One desktop panel, three layouts, shared live controls.

> **版本提示：此首页介绍新的面板开发版（build 39，尚未发布 Release）。**
> [当前公开正式版 v0.5.1](https://github.com/tonig0709/codex-quota-widget/releases/tag/v0.5.1) 仍是旧的小组件版本，不包含下述三尺寸面板。
> v0.5.6 目前是草稿，不是面向所有用户的公开下载。请勿把旧 DMG 当作本次更新的安装包。

## 三种尺寸，一个桌面面板

| 模式 | 尺寸（pt） | 内容 |
| --- | --- | --- |
| 小型 | 164 × 164 | 原有双圆环：5h 与周额度，环中保留 Codex 图标 |
| 中型 | 344 × 164 | Codex 标识、5h 与周额度两条进度条，不显示趋势图 |
| 大型 | 680 × 300 | 保留现有额度、重置时间、同步状态与近七天趋势 |

小、中面板沿用项目原生 macOS 组件的网格尺寸；pt 是逻辑点，Retina 显示不改变布局比例。
遵循 [Apple 的组件布局原则](https://developer.apple.com/design/human-interface-guidelines/widgets)，根据尺寸减少信息，不拉伸整张大面板来凑小尺寸。

- **像翻照片一样选择**：在 App 预览区用触控板左右滑动，也可点击左右箭头或模式名称。
- **始终只有一个**：已打开的桌面面板直接切换内容与尺寸，不会创建第二个窗口；保留面板左上角位置。
- **自由移动**：按住顶部拖动；鼠标靠近边缘时显示关闭与设置入口，移开自动隐藏。
- **保留全部玻璃参数**：自动/深/浅外观、不透明度（35–100%）、边缘强度、弹性高光、圆角、折射模式、位移、磨砂、色彩增益、色散与色调。
- **参数即时共用**：三种模式沿用相同参数与现有底层玻璃渲染，切换不重置；也可直接在面板设置弹窗调整。
- **额度颜色不变**：剩余 ≥60% 为绿色，30–59% 为橙色，<30% 为红色。

当前源码已移除 WidgetKit 扩展、组件库入口与登记修复逻辑，全部改用动态桌面面板。
这不是系统“编辑小组件”中的组件；不需要搜索组件库，也不会改变其他图标的透明度。
粒子实验不包含在本次稳定玻璃面板实现中。

## 下载与安装

新面板版暂未公开发布。本机测试包和 GitHub Actions 测试产物不等同于正式 Release。

- 普通用户请访问 [公开 Releases](https://github.com/tonig0709/codex-quota-widget/releases)，核对版本说明与附件；旧版不包含新面板。
- 开发者可从当前源码构建；不要将 GitHub 的 Source code 压缩包当作可运行 App。
- 新版发布后：打开其 DMG，将 **Codex Quota.app** 拖到 **应用程序**，弹出 DMG，再从“应用程序”打开。
- 仅当版本明确标注 **Developer ID signed and Apple-notarized** 时，才可将其描述为 Apple 签名并公证。Ad-hoc 测试版未公证，可能仍需系统首次打开确认。

面板版使用方式：

1. 保持 Codex Quota 运行，在 App 中选择小、中或大模式。
2. 点击 **桌面玻璃面板**；在 App 中换页，已放置面板随之切换。
3. 用 App 的 **玻璃设置** 或面板边缘的设置按钮调整参数。
4. 关闭面板不退出主程序；可从 App 或菜单栏重新打开。

升级旧小组件版时，请先退出旧 App 并替换整个应用包。已放在桌面的旧 WidgetKit 组件需要手动移除；
新版不会清空系统组件数据库，也不会删除账户数据来“修复”显示。

## 数据同步

主 App 是唯一的 Codex 连接所有者。面板直接观察同一份账户快照，不经过 WidgetKit 时间线或系统刷新预算。
App 每 15 秒轮询，并响应额度变化通知；额度和趋势尽量作为同一快照提交。
若趋势响应超时，新的额度仍会更新，并保留最后有效趋势。实际新鲜度仍受 Codex 服务、网络和账户数据可用性影响，不承诺逐秒刷新。

## 隐私与安全

- 登录和凭据刷新仍由本机 Codex 处理；本项目不读取或保存 OAuth token。
- App 与面板在同一进程内共享数据，不向第三方服务发送账户数据。
- 现有只读兼容/诊断接口保留在 `127.0.0.1:48193/snapshot`，仅输出去除邮箱和套餐的快照；面板不依赖该接口刷新。
- 完整威胁模型、签名与公证说明见 [SECURITY.md](SECURITY.md)。

## 从源码构建

要求 macOS 14+、完整 Xcode 16+，以及已安装的 Codex CLI 或附带 Codex 的 ChatGPT/Codex Mac App。

1. 用 Xcode 打开 `CodexQuotaWidget.xcodeproj`（保留历史工程名，现已只有 App target）。
2. 选择 `CodexQuota` scheme，配置自己的开发团队后构建运行。
3. 安装到“应用程序”再启动；不要从临时 DMG 副本运行账户连接。

```sh
swift run quota-self-check
./scripts/check-desktop-panel.sh
```

完整发布门禁只能在隔离 CI 用户运行，详见 [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)。
它检查三种布局的非黑屏、单面板、尺寸、关闭重开、滑动选择、实时数据链路、签名、双架构和 DMG 精确载荷。
最终鼠标悬停、原生拖动、透光与连续滑杆效果仍必须在真实桌面人工验收；自动检查不冒充系统桌面实测。

## 独立性与许可

本项目是独立开源项目，不隶属于 OpenAI，也未获 OpenAI 背书。源码采用 MIT 许可；
Codex 图标属于 OpenAI 商标资产，不包含在 MIT 授权中，见 [TRADEMARKS.md](TRADEMARKS.md)。
