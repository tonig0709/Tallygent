# Planner 自适应推荐引擎：本地算法升级

日期：2026-10-30（Asia/Shanghai）。本轮只修改本地代码，不发布、不改版本号、不替换已安装应用。实际源码仍位于 `Codex Quota`；新 `Tallygent` 目录为空。

本文记录的是 `Shared/Planner.swift` 的 Policy 2 实现，不是待实现架构的功能宣称。此前那轮规则优化见 [原算法审查](PLANNER_ALGORITHM_REVIEW.md)；该轮报告的通过结果不能自动视为本轮验证结果。

## 1. 先审查，再增量升级

既有实现已经具备：简繁与英文词边界分类、复杂度／风险／不确定性护栏、实时模型目录与 effort 校验、5h／周窗口检查、手动覆盖、最多两个替代配置、五条反馈门槛、账户隔离及版本化本地任务记录。这些能力保留，不重写监测、玻璃渲染或持久化层。

本轮相对于这一已优化基线的缺口及修改：

| 基线缺口 | 本轮实现 |
| --- | --- |
| 任务主要归结为单一规模等级，格式、孤立修复、跨服务及长上下文的差异不充分 | `PlannerTaskDimensions` 独立记录范围、集成、上下文与验证需求；未匹配维度保持未知，含糊输入降低分类证据 |
| 仅按模型角色和目标 effort 排序，容易把没有质量依据的备选当作等价替代 | 先筛合法组合，再检查启发式质量底线；无满足底线的候选时仍可展示条件备选，但明确 `qualitySatisfied = false`、低置信度及需确认状态 |
| 保留量等待与来源真实耗尽未结构化区分 | `providerExhausted` 区分新鲜当前窗口的 0% 与用户保留量；调整保留量不会创造来源额度 |
| 低额度只产生等待提示，缺少使用节奏信号 | 复用 Insights 同范围、同周期的近期速度，产生有上限的条件压力；共享窗口取最大压力，不相加 |
| 只有任意结果的 Token 摘要，不能可靠比较完成一个任务的资源负担 | 保留原摘要；另仅用足量、已完成且验证通过、无手动返工记录形成完成 Token 摘要；全体候选均可比时才统一比较该单位 |
| 有反馈降序，但较旧或不同任务维度的记录仍可能混入 | 加入可配置反馈时效、维度相等条件与样本平滑；仍保留 UUID 去重、时间顺序、有效性和账户／来源隔离 |

模型的实际订阅耗额单价、任务成功概率、上下文上限、推理延迟、隔离任务资源流依然缺失。算法不会用 API 价格、公开基准或随意的常数补造这些数据。

## 2. 四个逻辑职责，复用现有类型

- **TaskProfiler：** `PlannerProfile.classify/resolved` 和可选 `PlannerTaskDimensions`。最多分析 10,000 字符；不扫描仓库、不发送文本、不因描述长就提高难度。自动化验证标志仅表示检测到测试要求，不证明测试存在、充分或已通过。显式手工特征保留；文本检测到的敏感风险仍有原护栏。
- **ModelCapabilityRegistry：** 复用 `PlannerModel` 的本机目录、来源、发现时间、角色和支持 effort。目录仍为 30 分钟有效；同 ID 冲突排除。角色是目录描述／用户声明的序数先验，不是能力基准；没有新增硬编码模型名单。
- **QuotaAwareOptimizer：** `PlannerEngine.advise`、`quotaPressure` 与 `PlannerPolicy`。所有主推荐和替代项共用合法性、质量和证据规则。
- **RecommendationFeedbackEngine：** 复用 `PlannerEngine.summary`、`PlannerTaskRecord`、`PlannerStore` 和原文件存储。选择／保存一个建议不算任务成功；完成、验证、重试、返工和 Token 仍须用户明确记录。

推荐输入、当前候选评估和真实反馈分别保留。`PlannerAdvice` 的候选评估是本次内存结果，不是已完成任务观测；目前没有新增持久化预测账本或自动执行层。

## 3. 实际决策策略

### 3.1 合法性和质量先于资源比较

1. 只接受当前来源的有效、新鲜目录条目。枚举模型实际声明的、语义可识别的 `(model, effort)` 组合；未知 effort 不自动排序。
2. 普通小任务最低 `low`、普通中任务最低 `medium`；高复杂度、高风险或高不确定性最低 `high`。质量偏好和保守任务要求复杂任务角色，普通中任务至少通用角色，小任务可使用效率角色。上述是可解释启发式底线，不是实测质量阈值。
3. 有满足质量底线的候选时，只在该集合内优化。若全部不满足角色底线，不把弱备选伪装成等价答案；保留明确警告及需补充信息状态。没有合法 effort 组合时不发明配置。
4. 每个模型优先采用离需求最近的充分 effort，同距离选择更低档。更高 effort 不被当成必然质量提升，也不能为逃避该配置的负面反馈而盲目升级。
5. 用户仍可手动选择目录支持的配置。低于护栏或未知 effort 会降低置信度并提示，绝不写入 Codex 设置或自动执行。

### 3.2 条件额度压力，不是价格或精确 runway

对每个有合格近期速度的窗口 `w`：

```text
projected_w = recent_percentage_points_per_hour_w × hours_until_reset_w
usable_w    = max(1, remaining_percent_w − voluntary_reserve_percent)
pressure_w  = clamp(projected_w / usable_w, 1, maximumPressure)
pressure    = max_w(pressure_w)
```

`recent_percentage_points_per_hour` 来自现有 Insights 最近一小时的当前连续区段：不跨账户／会话、来源、额度池、周期、重置、负向跳变或长缺测连接。至少四次观测、跨度五分钟、净变化三个百分点才提供速度；它不是按“一周已过去多久”推断的固定平均速度。

引擎再次验证来源和 scope、窗口 ID、重置点、余量及接收时间；拒绝冲突重复、未来／陈旧、非有限或不足变化的速度。Codex 保鲜 120 秒，Claude 被动记录 300 秒。没有可用速度时 `quotaPressure = nil`，不当作零压力、无限容量或耗尽。某个窗口速度有效也不证明缺失的另一个窗口可运行，额度完整性仍由独立 assessment 判断。

短／周额度通常约束同一使用事件，因此不把两者当作两份独立预算相加。临近重置时投影自然变小，压力最低为 1；没有“快过期所以要多花”的奖励。压力只是“近期速度若延续”的条件信号，不能预测某项任务需要多少额度，也不能跨重置保证容量。

### 3.3 有次序的多目标比较，不混合单位

本轮采用字典序，而非把美元、Token、百分比和能力分数塞进一个任意权重总和。确定每个模型的最近充分 effort 后，按以下顺序比较：

1. 质量底线是否满足；保守任务是否落到效率角色。
2. effort 与任务目标的距离。
3. 足量同类负面反馈是否达到现有降序门槛。
4. 非节省模式先比较角色适配；节省模式先比较资源负担。
5. 只有所有保留候选均有足量可比反馈时，才细比平滑后的不良反馈负担；否则跳过这一轴，不奖励未知样本为零失败。之后比较角色适配、目录核验、默认标记、effort 及稳定配置 ID。

**质量优先：** 保持质量角色和充分 effort 底线，优先角色适配。**平衡：** 正常先角色适配；有效条件压力大于 1 时，在同样的质量底线内优先资源负担。**效率优先：** 此处是额度节省取向，在质量底线内优先资源负担，不声称已测量更低执行延迟。额度、紧急和偏好都不会静默下调保守推理底线。

资源负担必须在整个候选集合使用同一依据：所有保留候选均有足量可比的验证完成 Token 时，统一比较其中位数；否则全体退回角色序数先验。不能让缺失成本在某次两两比较中变成零，也不能在另一对候选中突然换单位；这种混合会产生不传递排序。未知角色的 `ordinalResourceTier` 保持 `nil`，并不意味着免费或零能力。

这不是完整 Pareto 优化器。当前缺失可比的延迟、实测质量与订阅成本，新增“前沿”名义不能改善证据，因此本轮不虚构这些轴。

### 3.4 小样本反馈与成本边界

仅比较相同配置、类别、复杂度、风险、不确定性、维度及账户／会话范围的有效反馈，排除重复、未来、倒置时间和过旧记录。

```text
adverseBurden = (adverse_count + 1) / (evaluated_count + 2)
```

只有所有保留候选均达到 `minimumSamples`，该细排轴才参与排序。两个伪样本把小集合负担向中性拉回；这只是有限样本的排序稳定器，不是经过校准的失败概率。单个配置达到样本门槛且不良反馈达到 40% 时仍可保守降序；默认门槛五条，统一服从策略配置。相同 UUID 的相同记录只计一次，内容冲突的同 UUID 全部排除，不能依输入顺序任选一种反馈。

原 `tokenEstimate` 仍摘要有效用户填报总量；新增 `completionTokens` 仅摘要已成功、验证通过且无手动返工的记录。不保证这些自报总量涵盖所有重试、失败升级及验证开销；没有逐尝试遥测，不能推导未来完整完成成本。中位数和观测最小–最大值不是统计预测区间，不换算订阅百分比。

`PlannerPolicy` 版本为 2：默认至少五条样本、反馈最多 90 天、压力上限 4；允许通过初始化参数调整，对参数做边界约束，之后不可变。保留既有样本门槛，时效和上限用于限制陈旧证据与外推影响，并非学习得到的最优常数；界面未新增对应设置。历史不足时总体置信度为低，而非中／高，更不是成功概率。

## 4. UI、数据与隐私兼容

`PlannerView.recommend()` 从 `server.insights.panelReport` 提取各窗口速度，传入原纯推荐入口。复用的是独立 24h Insights 缓存，切换 Insights 页面的查看范围不会截短 Planner 的观察基础；没有新增采集连接、计时器或后台服务。

新历史到达时直接传递 `$panelReport` 发布的报告值；`@Published` 在 `willSet` 阶段发布，若忽略回调值再读存储属性会落后一批。`check-planner.sh` 同时检查此接线，避免仅定时重算掩盖延迟。

此改动不重新设计窗口、候选选择器或桌面面板，也不改玻璃、同步、拖动和布局；三语只补充新解释文本。任务原文只用于本地分析，不进入新增维度。原主动保存短标题行为不变。

`PlannerProfile.dimensions` 是可选字段，旧 Schema 1 没有该字段时解码为 `nil`，不补造历史要求。记录文件路径、schema、权限和上限保持原样。没有维度的旧反馈与新增维度反馈不当作同一校准集合，可能需要重新积累足量样本；旧记录不会因此删除或改写。

## 5. 五项开源研究：固定版本与适配边界

以下为 2026-10-30 核验的固定提交。仅借鉴决策思想，没有复制整个实现、导入包或第三方模型；若未来复制实质代码，仍须保留相应版权／许可证及 Apache 适用通知。

| 参考与固定提交 | 实际研究位置、许可 | 本轮适配 |
| --- | --- | --- |
| RouteLLM `0b64fdafe049e596a3f5657c219329f24af24198` | [routers.py](https://github.com/lm-sys/RouteLLM/blob/0b64fdafe049e596a3f5657c219329f24af24198/routellm/routers/routers.py)、[calibrate_threshold.py](https://github.com/lm-sys/RouteLLM/blob/0b64fdafe049e596a3f5657c219329f24af24198/routellm/calibrate_threshold.py)；[Apache-2.0](https://github.com/lm-sys/RouteLLM/blob/0b64fdafe049e596a3f5657c219329f24af24198/LICENSE) | 质量与资源取舍需要阈值和验证；保留质量底线，不借用预训练路由器、偏好预测或节省比例 |
| FrugalGPT `2b23e6acbd4b39f71912816640dcc59e45aa4b5e` | [optimizer.py](https://github.com/stanford-futuredata/FrugalGPT/blob/2b23e6acbd4b39f71912816640dcc59e45aa4b5e/src/FrugalGPT/optimizer.py)、[llmchain.py](https://github.com/stanford-futuredata/FrugalGPT/blob/2b23e6acbd4b39f71912816640dcc59e45aa4b5e/src/FrugalGPT/llmchain.py)、[llmcascade.py](https://github.com/stanford-futuredata/FrugalGPT/blob/2b23e6acbd4b39f71912816640dcc59e45aa4b5e/src/FrugalGPT/llmcascade.py)；[Apache-2.0](https://github.com/stanford-futuredata/FrugalGPT/blob/2b23e6acbd4b39f71912816640dcc59e45aa4b5e/LICENSE) | 关注完成任务而非仅首轮调用的成本；证据不足不生成廉价优先级联，不把答复分数当作编码任务成功保证 |
| LiteLLM `b71491c6c910c15bc1580e9469b6d3ecb3b376b1` | [budget_limiter.py](https://github.com/BerriAI/litellm/blob/b71491c6c910c15bc1580e9469b6d3ecb3b376b1/litellm/router_strategy/budget_limiter.py)、[cooldown_handlers.py](https://github.com/BerriAI/litellm/blob/b71491c6c910c15bc1580e9469b6d3ecb3b376b1/litellm/router_utils/cooldown_handlers.py)、[fallback_event_handlers.py](https://github.com/BerriAI/litellm/blob/b71491c6c910c15bc1580e9469b6d3ecb3b376b1/litellm/router_utils/fallback_event_handlers.py)；根目录 [MIT](https://github.com/BerriAI/litellm/blob/b71491c6c910c15bc1580e9469b6d3ecb3b376b1/LICENSE)，不涉及 enterprise | 先筛真实可用配置、额度限制和回退合法性；不把每 deployment 的 API 预算映射成 Codex 独立订阅池 |
| vLLM Semantic Router `a68021bd4c2f21c52368fbb81c4047a9b8ba2a07` | [multi_factor.go](https://github.com/vllm-project/semantic-router/blob/a68021bd4c2f21c52368fbb81c4047a9b8ba2a07/src/semantic-router/pkg/selection/multi_factor.go)、[multi_factor_objective.go](https://github.com/vllm-project/semantic-router/blob/a68021bd4c2f21c52368fbb81c4047a9b8ba2a07/src/semantic-router/pkg/selection/multi_factor_objective.go)、[evidence.go](https://github.com/vllm-project/semantic-router/blob/a68021bd4c2f21c52368fbb81c4047a9b8ba2a07/src/semantic-router/pkg/selection/evidence.go)；[Apache-2.0](https://github.com/vllm-project/semantic-router/blob/a68021bd4c2f21c52368fbb81c4047a9b8ba2a07/LICENSE) | 分开信号、硬约束和候选优化，使用字典序优先级及缺失证据标志；不导入 embeddings／分类模型或把排序差值叫成功概率 |
| auto-model-router `80a09591e4da97c5ee141c976d10b4afbefe36aa` | [quota.py](https://github.com/fstandhartinger/auto-model-router/blob/80a09591e4da97c5ee141c976d10b4afbefe36aa/auto_router/quota.py)、[policies.py](https://github.com/fstandhartinger/auto-model-router/blob/80a09591e4da97c5ee141c976d10b4afbefe36aa/auto_router/policies.py)、[economics.py](https://github.com/fstandhartinger/auto-model-router/blob/80a09591e4da97c5ee141c976d10b4afbefe36aa/auto_router/economics.py)、[decision.py](https://github.com/fstandhartinger/auto-model-router/blob/80a09591e4da97c5ee141c976d10b4afbefe36aa/auto_router/decision.py)；[MIT](https://github.com/fstandhartinger/auto-model-router/blob/80a09591e4da97c5ee141c976d10b4afbefe36aa/LICENSE) | 条件稀缺压力、完成成本视角及预测／观测分离；不照搬其美元影子价格、固定周期均速、陈旧即关闭、拟合成功率或缓存价格 |

auto-model-router 的[公开评估](https://github.com/fstandhartinger/auto-model-router/blob/80a09591e4da97c5ee141c976d10b4afbefe36aa/evaluation/antseed-irp-eval-20261017/wave3/summary.md)不能证明其策略普遍胜过固定强模型；其中符合质量条件的部分设置实际始终选择同一强模型。本轮测试不执行外部模型，不能借用其结果宣称 Tallygent 节省额度或提高真实任务质量。

## 6. 实现范围、验证口径与后续优先级

**P0 已实现于代码：** 既有审查、多维任务画像、真实 model／effort 组合过滤、窗口与质量约束、确定性排序、条件备选、缺失数据提示、主／替代项解释、可运行回归及合成基线对照。

**具备现有证据的 P1：** 复用近期速度的有界压力、同类用户反馈的保守平滑、可比验证完成 Token 摘要。验证／重试和阶段拆分只提供条件说明，不冒充已优化的可执行级联或多模型计划。

**明确未实现：** 可校准的任务成功概率、独立订阅耗额单价、端到端期望完成成本、具有完整观测维度的 Pareto 前沿、自动切模／执行、学得路由、bandit、AI 分类器，以及节省比例承诺。高风险直接建议充分配置；低风险有测试信号时提示先验证再人工重评，不能据此声称廉价优先更优。

验证以本轮实际命令输出为准。`Gate/PlannerProbe.swift` 检查分类、兼容性、额度、反馈及迁移；`Gate/PlannerBenchmark.swift` 的确定性合成场景比较当前策略、始终强模型、名义最低资源配置及静态规则，脚本可另传固定的升级前源码运行同组场景。名义最低资源基线仅按声明角色和 effort 序数排序；成本和成功概率字段保持未知，不代表订阅收费、真实任务成功率或统计实证。测量结果与未完成项目由主验收记录追加，不能把编译、语法解析、静态图或模拟测试当作完整 App／真实桌面验收。

下一步按证据增量推进：

1. 收集经用户确认的实际配置、验证、逐尝试用量和完整完成结果；补足上下文／特性可用性元数据，并保留隐私最小化与授权。
2. 在分离评估集上验证能力底线、压力敏感性、失败后的条件重试成本及跨时间稳健性；有证据后再比较单模型、人工升级与分阶段策略的协调开销。
3. 仅在已有数据支持且用户选择启用时，考虑个性化估计或可选本地分类；自动执行始终是独立授权功能，不作为 Planner 免费可用的前提。

## 7. 本轮实际验证与前后对照

升级前源码快照为 `outputs/planner-adaptive/baseline-Planner.swift`，SHA-256 `a0856d2bd3caedc32e8c836adbd722bbe71c30445103f8b362b138b7f4b1548f`；未重置或覆盖原工作区改动。相同 378 个固定任务／偏好／额度／目录案例，对照四种策略，不执行任何模型。结果保存在 `outputs/planner-adaptive/before.json` 与 `current.json`。

| 合成政策契约指标 | 原已优化引擎 | 本轮 Policy 2 |
| --- | ---: | ---: |
| 未附条件却违反夹具序数质量底线 | 12 | 0 |
| 明确条件建议中的质量底线不匹配 | 37 | 15 |
| 目录／不确定排序／耗尽／未知数据违规 | 各 0 | 各 0 |
| 本次本机平均决策计算耗时 | 2.36 ms | 4.86 ms |

对照的 always-strong、名义最低资源及静态默认规则，未附条件底线不匹配分别为 33、72、45。这里包含无足够能力目录时是否诚实标注 fallback 的差异，不能据此推断强模型真实质量差，亦不能推断模型成功率或节省幅度。原／新引擎有 127 个主要配置或决策状态变化；部分改善来自更准确的条件状态，不是新测量出的性能。计算耗时只是一次本机信息性测量，不是模型执行延迟或稳定性能基准。

| 命令／检查 | 本轮实际结果 |
| --- | --- |
| `sh scripts/check-planner.sh` | 通过；原有回归、新边界以及自动接入的 378 案例策略门禁；不会只输出比较而忽略违规 |
| `sh scripts/check-planner-benchmark.sh Shared/Planner.swift outputs/planner-adaptive/current.json` | 通过；当前引擎强制检查目录、确定性、质量、耗尽、未知和解释契约；原源码对照保留差异而不伪装通过新政策 |
| `sh scripts/check-localization.sh` | 通过；436 个键、三语覆盖、安全格式、七种原生语言选择／回退进程 |
| `sh scripts/check-observation-history.sh` | 通过；锁、并发、迁移、隐私、保留期与来源接收 |
| `sh scripts/check-usage-insights.sh` | 通过；分段、新鲜度、整数分辨率、回放、重置与提醒去重 |
| `sh scripts/check-panel-trend.sh` | 通过；图表单位、范围、偏好、独立缓存、作用域、缺测与 DST |
| `sh scripts/check-agent-providers.sh` | 通过；解析、私有缓存、可逆设置、选择与新鲜度 |
| `sh scripts/check-codex-discovery.sh` | 通过；只读 CLI 发现，不调用推理 |
| Planner probe arm64 | 编译并运行通过；使用临时夹具，不读写用户任务历史 |
| Planner probe x86_64/macOS 14 目标 | 交叉编译通过；未声称已在 Intel／Rosetta 实际运行 |
| `swiftc -parse App/PlannerView.swift`、脚本语法及 `git diff --check` | 通过；语法解析不等于完整界面类型检查 |
| 完整 App 构建／真实桌面操作 | 未执行：本机仅 Command Line Tools，无完整 Xcode；未用个人桌面或真实账户运行全量 runtime 门禁 |

独立子 Agent 审查暴露并修正：缺失反馈被当成零失败优势、自报 Token 覆盖措辞过度、可变策略把样本门槛改为零导致中位数崩溃、未知手动 effort 被 99 哨兵误当满足质量、历史冲突 UUID 依输入顺序取样，以及 `@Published` 报告接收时的上一批数据问题。第一次并发编辑期间编译失败的尝试不计通过，之后稳定源码完整重跑通过。

本轮修改文件：`Shared/Planner.swift`、`App/PlannerView.swift`、`Gate/PlannerProbe.swift`、新增 `Gate/PlannerBenchmark.swift`、`scripts/check-planner.sh`、新增 `scripts/check-planner-benchmark.sh`、三份 `Resources/*/Localizable.strings`、`docs/PLANNER.md` 和本文。没有引入依赖、修改模型名单、修改版本号、创建 DMG、提交远程分支或发布 Release，也没有替换已安装 App。
