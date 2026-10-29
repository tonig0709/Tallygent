# Tallygent

让 Agent 额度始终可见，让下一步安排有据可依。

[English](README.md) · **简体中文** · [繁體中文](README.zh-TW.md)

Tallygent 是本地优先的 macOS 应用，监测 **Codex** 与实验性 **Claude Code** 额度，提供 **12/24 小时额度历史**、可移动 Liquid Glass 桌面面板、Insights 分析与可解释的 Planner 建议，不需要授予自动执行任务的权限。

## 语言支持

**English、简体中文、繁體中文**，从 v0.8.1 开始提供。应用自动跟随 Mac 的首选语言，也尊重系统为单个 App 指定的语言；未支持的语言回退为 English。更改语言后请重新启动应用。日期、时间与数字格式仍跟随系统地区设置。

这里的 README 语言链接仅切换文档，不改变应用或系统设置。详见[本地化说明](docs/LOCALIZATION.md)。

## 下载与安装

**v0.8.1（build 55）** · **macOS 14+** · **Apple Silicon / Intel 通用构建**。

[下载 DMG](https://github.com/tonig0709/Tallygent/releases/download/v0.8.1/Tallygent-v0.8.1-macOS.dmg) · [发布说明](https://github.com/tonig0709/Tallygent/releases/tag/v0.8.1) · [SHA-256](https://github.com/tonig0709/Tallygent/releases/download/v0.8.1/Tallygent-v0.8.1-checksums.txt)

1. 下载 `.dmg`，不是 GitHub 的 Source code 压缩包。
2. 把 **Tallygent.app** 拖到“应用程序”，弹出 DMG，再启动安装好的应用。
3. 安装并登录本机 Codex CLI，或包含 Codex 的受支持 Mac App；在 Tallygent 中选择服务。
4. 选择小、中、大面板，点击“桌面玻璃面板”，通过“玻璃设置”调整外观和图表。
5. 保持 Tallygent 运行，以继续采集新的额度观测。关闭面板不会退出应用。

> 当前下载包为 **ad-hoc 签名，未经 Apple 公证**。首次打开可能需要额外的系统确认。请核对来源与校验值，不要关闭 Gatekeeper；SHA-256 证明文件完整性，不代表 Apple 审核。见[安全说明](SECURITY.md)。

## 主要功能

- **12/24 小时额度历史**：分别查看 5h 和周额度，切换柱状图或折线图。小时柱代表该小时最后一次有效观测，不是该小时 Token 消耗。
- **保留七日 Token 趋势**：大型面板可切回原来的七日 Token 图；额度百分比与 Token 不混算。
- **三种原生尺寸**：小型双圆环 164×164pt，中型双额度条 344×164pt，大型额度与趋势 680×300pt。
- **一个可移动桌面面板**：App 中左右滑动切换尺寸；面板正文可拖动，边缘按钮移入显示、移开隐藏。
- **实时共用玻璃设置**：深色、浅色、自动外观，不透明度、磨砂、边缘和高光等参数同步到桌面面板。
- **Monitor / Insights / Planner**：保留本机观测、解释使用节奏，并根据任务、可用模型、额度窗口和保留量给出 Model + Effort 建议；数据不足时明确说明。

剩余额度 ≥60% 为绿，30–<60% 为橙，低于 30% 为红。历史缺口留空，重置和长时间中断不连线，不补造启用前的数据。详见[图表含义](docs/PANEL_TRENDS.md)。

![深色大型面板示例](docs/screenshots/panel-12h-dark.png)

图片来自 v0.7.1 / build 52 的原生演示数据快照，早于多语言更新，不含个人账户数据。[图片来源](docs/SCREENSHOTS.md)。

## 数据来源与刷新

**Codex**：主应用拥有唯一的 app-server 连接，每 15 秒轮询并响应额度变化通知。面板直接观察同一状态，不依赖 WidgetKit 刷新预算。右上角每秒变化的是 Mac 时钟，不代表额度每秒更新；实际新鲜度取决于服务、网络和可用数据。

**Claude Code（实验性）**：用户主动启用本地 statusLine 接入，运行可提供订阅额度字段的会话。应用每两秒读取本地缓存，不主动查询订阅服务器。无数据不显示虚假 0%；一次绑定一个会话，不覆盖已有第三方 statusLine。真实订阅与不同版本兼容性仍待真实账户验证，不提供 Claude 七日 Token 图。

## 隐私、升级与边界

- 历史保留在本机，最多 30 天；提供导出与清空，不保存提示词、代码或 Codex OAuth token。
- Claude 接入会在本机备份原设置文件，其中可能包含原有密钥；备份权限为 `0600`。见[安全说明](SECURITY.md)。
- 不把百分比换算成 Token、费用或任务数量，不把多个 Provider 余额相加，不后台启动、迁移或执行任务。
- 由 Codex Quota 升级时退出旧副本，只保留一个活跃安装，不删除本地数据。当前产品是独立可移动面板，**不是系统小组件库里的 WidgetKit 组件**。
- 粒子实验与稳定玻璃版分开维护。没有 Windows 或 iOS 发行版。

## 开发与文档

需要完整 Xcode 16+。打开保留历史名称的 `CodexQuotaWidget.xcodeproj`，选择 `CodexQuota` scheme。语言资源、字体和边界回归见[本地化说明](docs/LOCALIZATION.md)与[布局约束](docs/LAYOUT_INVARIANTS.md)。

完整发布门禁只可在隔离 CI 用户运行，覆盖 macOS 14、15、26。真实鼠标拖动、悬停、透光与连续滑杆仍需桌面验收，详见[发布清单](RELEASE_CHECKLIST.md)。

[英文完整说明](README.md) · [Monitor / Insights](docs/MONITOR_INSIGHTS.md) · [Planner](docs/PLANNER.md) · [路线图](docs/TALLYGENT_ROADMAP.md) · [问题反馈](https://github.com/tonig0709/Tallygent/issues)

独立开源项目，不隶属于 OpenAI 或 Anthropic。源码采用 [MIT 许可](LICENSE)；服务名称及图标商标不包含在 MIT 授权中，见[商标说明](TRADEMARKS.md)。
