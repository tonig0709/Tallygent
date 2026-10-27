# 稳定玻璃版与粒子实验分支

2026-10-26：用户要求将当前 build 49 备份到粒子实验开发区，之后在独立分支开发，方便将来合并。

## 共同基线

- build 49 源码提交：`bd514e65080de9e8a14e16be1267d1e8bcec2625`。
- 新粒子开发分支：`codex/particle-tallygent`，从上述稳定面板基线创建，而不是从旧 WidgetKit 粒子实现继续合并。
- 稳定发布候选：`codex/release-v0.7.0`。v0.7.0 / build 50 仅递增版本元数据和发布资料，功能与 build 49 相同。
- 本机独立开发区：`.particle-experiment/`，不进入稳定发布载荷；源码使用真正的 Git checkout，安装包另存在备份目录。
- 备份不包含账号、偏好、Planner 私人记录或 Application Support 数据。

## 保留旧成果

保留 `codex/particle-theme-saved`、`codex/fix-particle-config` 及旧 v0.6.0 / v0.6.1 粒子预发布。它们只是视觉和实现参考，不覆盖、不移动旧标签，也不将旧组件注册、WidgetKit 或 AppIntent 元数据带回 panel-only 产品。

## 后续开发与合并

1. 在 `codex/particle-tallygent` 提交新的粒子面板实现；此轮只保存基线，不声称新粒子效果已经完成。
2. 稳定版的修复先通过现有门禁，再以普通 merge 合入粒子分支，保留共同历史；不要复制整份源码覆盖、强推或改写稳定标签。
3. 粒子功能成熟时，从粒子分支向稳定分支提交可审查的合并请求。粒子效果与额度/历史/Planner 数据层分开，不能降低非黑屏、同步、单面板和内部布局检查。
4. 未通过完整 Xcode 双架构、三系统门禁和真实桌面验收前，不把粒子实验列为稳定版默认效果。

本机 build 49 安装包备份的 SHA-256：

```text
f50d7dae4a3c838e6aaccc678970dd0bc60f460b3ae3b5acc76ac75da97b33ca
```
