# Stage 4-D：智能消费趋势预测设计审查报告

> Stage 4-D **Step 1（设计审查）** 产物。
> 本阶段**没有修改任何代码**：没有改 Java / Dart / SQL / YAML / 配置 / 测试，
> 只读了仓库现有实现与文档，并写出本报告。
> 审查时间：2026-09-18 ｜ 基线：Stage 4-C 已 CONDITIONAL PASS（唯一 WARNING 是
> `BillMapper#sumByCategoryAndMonth` 的索引注释不准确，本阶段不回头修改）。

---

## 1. 审查结论

**CONDITIONAL PASS** — 设计已完整，但有三处**范围判断与用户给出的示例不一致**，
需要用户确认后才能进入 Step 2。

### 必须先确认的三点

| # | 问题 | 我的建议 |
| --- | --- | --- |
| 1 | 用户示例中的「本月预计支出 ¥1,286」「预计达到预算的 87%」「预计 11 日左右达到预算」**已经由 Stage 4-A 实现**（见 §4.2 证据），Stage 4-D 若照做就是把同一件事做第二遍 | **把 Stage 4-D 的预测目标改为「下个月」（不依赖预算）**，而不是再预测一次本月 |
| 2 | 首页目前已经发 7 个请求、显示 6 个区块（见 §2.3） | **首页不新增预测卡片**（可在现有卡片里加一个跳转入口） |
| 3 | 分类级预测与未来 7 天预测在现有数据密度下噪声大于价值（见 §5、§17） | **本阶段延期**，不硬做 |

如果用户不同意第 1 点（坚持 Stage 4-D 也预测本月），那么 4-D 与 4-A 会出现
**同页面两个含义相同、数值相近的预测**，需要在 Step 2 前重新划分边界，否则不建议开工。

除此之外，其余设计（算法、冷启动、置信度、异常值、API、DTO、Mapper、性能、前端、测试矩阵）
均已完成且可在现有架构内实现，不需要新增表、字段、索引与第三方依赖。

---

## 2. 当前实现盘点

### 2.1 后端能力

| 能力 | 实现位置 | 口径 |
| --- | --- | --- |
| 月度收支 | `StatisticsService#monthly` → `BillMapper#sumByType` | `type IN (1,2)` 汇总，`type=3` 完全排除 |
| 分类支出 | `StatisticsService#category` → `sumByCategory` | 按月、按分类，降序 |
| 每日收支 | `StatisticsService#daily` → `sumByDay` | 整月补零，供折线图 |
| 支付来源 | `StatisticsService#source` → `sumBySource` | 只算支出 |
| 今日收支 | `StatisticsService#dailySummary` → `sumByType` | 单日 |
| **消费趋势** | `StatisticsService#trends` → `sumByType` ×2 | **本月 vs 上月实际支出**，只有"已发生"的对比，无预测 |
| 预算执行 | `BudgetService#list` → `BudgetMapper` | 预算 vs 已花 |
| **预算预测** | `BudgetPredictionService#predict` | 日均外推 + 风险分级（见 §4.2） |
| 消费洞察 | `InsightsService#monthly` | 预算 / 分类增长 / 整体变化 / 消费结构，最多 5 条 |
| 周期支出 | `RecurringBillService#detect` | 180 天窗口、四信号、不落库 |
| 消费异常 | `SpendingAnomalyService#detect` | 本月 vs 前 3 月、三类规则、最多 5 条 |

可复用的聚合查询（都在 `BillMapper`）：

| 方法 | 形态 | 是否可用于 4-D |
| --- | --- | --- |
| `sumByType(userId, start, end)` | 按 type 汇总 | 可用于"某个区间支出合计" |
| `sumByCategory(userId, start, end)` | 按分类汇总 | 单月可用，跨月需多次调用（会变成 N 次查询） |
| `sumByDay(userId, start, end)` | 按天汇总 | 可用于当前月节奏 |
| `sumByDayAndCategory` | 按天 + 分类 | 4-A 用；4-D 不需要 |
| `sumByCategoryAndMonth(userId, type, start, end, pattern)` | **按「分类 + 月份」汇总，且带 count** | **关键复用点**：一次查询即可覆盖任意多个月的月度合计 |
| `selectRecurringCandidates` / `selectExpenseDetails` | 明细 | 4-D 不需要（4-D 只需月度金额，不看明细） |

**结论**：Stage 4-D 需要的数据（最近若干个月的每月支出合计）**已经被
`sumByCategoryAndMonth` 一条 SQL 覆盖**，把同月的各分类金额相加即可得到月度合计。
这意味着 4-D **可以不新增任何 Mapper 方法、不新增任何 SQL**。

### 2.2 数据现实（实测）

对本地测试库 `campus-ledger-mysql-test` 的实测：

```text
每个测试用户账单数：最多 124 条，最多覆盖 7 个自然月
全库按月分布：2026-03 → 2026-09 共 7 个月有数据
月度支出波动很大（不同用户 / 月份量级差距明显）
```

含义：

1. **历史月数上限很浅**（现实中的学生用户通常 3~6 个月），因此任何需要 24~36 个数据点的
   时间序列模型（ARIMA / Prophet 等）在这套数据上不成立（见 §5 方案 E）；
2. 数据量小反而适合"可解释的加权平均 + 稳健统计"，而不是复杂模型；
3. 月度波动大，因此**必须**有异常月处理与置信度分级，否则预测会随单笔大额消费剧烈跳动。

### 2.3 前端现状

| 页面 | 当前区块 / 请求 |
| --- | --- |
| 首页 `home_page.dart` | 区块：概览卡（今日 + 本月 + 趋势）→ 智能预算预测 → 周期提醒 → 洞察摘要 → 分类快捷入口 → 最近账单；请求：`dailySummary`、`monthly`、`trends`、`insights/monthly`、`budgets/predictions`、`insights/recurring`、`bills?size=5` = **7 个** |
| 统计页 `statistics_page.dart` | 概览 → 预算卡 → 预算预测 → 周期支出 → 消费异常 → 本月消费洞察 → 分类统计 → 来源统计 → 趋势图；请求：`monthly`、`category`、`source`、`daily`、`budgets`、`insights/monthly`、`budgets/predictions`、`insights/recurring`、`insights/anomalies` = **9 个** |

可复用组件：`Card` + 区块模式（3 个智能区块结构一致）、`BudgetRiskStyle`（风险配色）、
`InsightList`、`EmptyView`、`fl_chart`（`stat_charts.dart` 已有环形图与折线图）。

`MonthSelector` 允许翻到任意月份（含未来月），因此预测接口必须能对"非当前月"返回明确状态。

---

## 3. Stage 4-D 最终目标

一句话：**在不依赖任何预算的前提下，用用户自己的历史消费节奏，给出"下一个月大概会花多少"的可解释预估。**

用户能看到的结论形态：

```text
下月预计支出 ¥1,238
比本月（¥1,250）少 ¥12，基本持平
依据：近 3 个月加权（8月 ¥1,250 ×3、7月 ¥1,180 ×2、6月 ¥1,320 ×1）
可信度：中等（3 个月样本，最高与最低相差 11.9%）
```

明确**不**包含（与 4-A 的差异见 §4）：

- 不判断"会不会超预算"（那是 4-A）；
- 不预测分类明细（延期）；
- 不预测未来 7 天（延期）；
- 不出"预计哪一天达到预算"（那是 4-A 的 `overDate`）。

---

## 4. 与既有能力边界

### 4.1 边界表

| 能力 | 回答的问题 | 时间方向 | 是否依赖预算 | 输出粒度 |
| --- | --- | --- | --- | --- |
| Stage 3 消费洞察 | 这个月的**结构**是什么（占比、环比、预算提醒） | 过去 | 否（预算规则是附加） | 一句话 + 最多 5 条结论 |
| Stage 4-A 智能预算预测 | **当前预算**是否可能被突破，超多少、何时触顶 | 本月 → 月末 | **是**（无预算直接 `NO_BUDGET`） | 每个预算一条 |
| Stage 4-B 周期性支出 | 哪些支出**会重复出现** | 过去 180 天 | 否 | 每个商户一条 |
| Stage 4-C 消费异常 | 本月哪些消费**偏离了自己的常态** | 本月 vs 前 3 月 | 否 | 最多 5 条异常 |
| **Stage 4-D 趋势预测** | **下个月大概会花多少** | 本月 → 下月 | **否** | 1 条总体预估 + 置信度 |

### 4.2 关键证据：用户示例与 4-A 的重叠

`BudgetPredictionService`（`backend/src/main/java/com/campus/ledger/service/BudgetPredictionService.java`）已经实现：

```text
dailyAverage   = spent / elapsedDays                      （第 168 行）
projected      = dailyAverage × daysInMonth               （第 170 行）
projectedOver  = projected − budgetAmount                 （第 172 行）
usageRate      = projected / budgetAmount × 100           （第 174 行）
overDate       = budgetAmount / dailyAverage 向上取整      （第 215 行）
riskLevel      = SAFE / LOW / MEDIUM / HIGH / OVER        （第 196 行）
```

对照用户给出的 Stage 4-D 示例：

| 用户示例 | 现有归属 | 结论 |
| --- | --- | --- |
| 「按当前消费节奏，本月预计支出 ¥1,286」 | 4-A `projected` | **已实现** |
| 「预计比上月增加 ¥186」 | 4-A 无；`/statistics/trends` 给了本月 vs 上月的实际变化率 | 半实现 |
| 「预计达到月度预算的 87%」 | 4-A `projectedUsageRate` | **已实现** |
| 「预计本月将在 xx 日左右达到预算」 | 4-A `overDate` | **已实现** |
| 「预计本月不会超过预算」 | 4-A `message` | **已实现** |
| 「餐饮仍是主要支出来源」 | Stage 3 `topCategory` | **已实现** |
| 「未来 7 天预计支出 ¥xxx」 | 无 | 新，但建议延期（§17） |
| **「下个月预计支出」** | **无**（全仓库 `forecast` / `下月` 命中 0） | **真正的空白点** |

**所以 Stage 4-D 的价值点只有一个**：回答"**下个月**会花多少"。
如果照抄用户的示例清单，4-D 会变成"4-A 的无预算版本"，在同一个统计页上并排显示两个
含义相同、数值相近的数字，用户无法理解区别 —— 这是本报告最主要的 Push Back。

### 4.3 与 4-A 的分工说明（写进文档与页面的措辞）

```text
Stage 4-A：我有预算 → 照这个速度，月底会不会超？
Stage 4-D：我没有预算 → 照我过去的节奏，下个月大概会花多少？
```

两者都可以独立存在：4-A 在无预算时显示引导设置预算，4-D 永远可用（只要有历史）。

---

## 5. 算法方案对比

### 方案 A：当前月线性外推

```text
predicted = (本月已支出 / 本月已过天数) × 本月总天数
```

| 维度 | 评价 |
| --- | --- |
| 优点 | 极简、稳定、用户能心算 |
| 缺点 | **与 4-A 逐字相同**；完全不用历史；月初 3 天内极不稳定 |
| 结论 | **不作为 4-D 核心**。仅作为 4-A 已有的能力保留，4-D 不重复实现 |

### 方案 B：历史月度加权 + 当前月进度

```text
基础值：最近 3 个「可用历史月」按时间倒序加权（3 : 2 : 1）
可选修正：当前月已过 ≥3 天且支出天数 ≥3 时，用本月节奏做少量修正
```

| 维度 | 评价 |
| --- | --- |
| 优点 | 真正用了历史；权重可解释（"最近的月份更重要"）；实现简单；可单测 |
| 缺点 | 需要定义"可用月"、缺月、异常月；权重取值有主观成分（需说明理由） |
| 结论 | **推荐作为核心**，但**不做当前月混合修正**（理由见 §6.3） |

### 方案 C：历史同星期 / 同日期结构

考虑"周末花得多""生活费到账后猛花"等结构。

| 维度 | 评价 |
| --- | --- |
| 数据要求 | 每个星期几至少 8 个样本（≈2 个月密集数据），且要求用户**每天都有记录** |
| 现实情况 | 学生个人记账普遍稀疏（很多天 0 条）；实测测试库用户仅 ~124 条 / 7 个月 |
| 风险 | 稀疏样本下的"星期效应"几乎全是噪声；还会与 4-A 的日均口径冲突 |
| 结论 | **明确否决**。理由：数据密度不支持，收益无法验证，纯增加复杂度 |

### 方案 D：指数移动平均（EWMA）

```text
EWMA_t = α × amount_t + (1 − α) × EWMA_{t−1}
```

| 维度 | 评价 |
| --- | --- |
| 参数选择 | α 没有业务含义，用户无法理解"为什么是 0.5" |
| 等价性 | 在 3 个月样本上，α=0.5 的权重 ≈ 4 : 2 : 1，与方案 B 的 3 : 2 : 1 几乎等价 |
| 冷启动 | 与方案 B 完全相同（都需要前 2~3 个月的种子值） |
| 可解释性 | 比"加权平均"差：无法用一句话说明"预测值是怎么来的" |
| 结论 | **不作为核心**。若未来需要"更重视近期"，直接调方案 B 的权重即可，不必引入 α |

### 方案 E：机器学习 / 时间序列（ARIMA / Prophet / XGBoost / LSTM）

| 维度 | 评估 |
| --- | --- |
| 数据量 | 需要至少 24~36 个稳定观测点（2~3 年）；本项目用户实测量级是 **3~7 个月**且波动大 |
| 部署复杂度 | 需要一个 Python 服务或 JVM 端模型运行时，**破坏当前 Spring Boot 单模块架构**，答辩环境多一个进程要维护 |
| 预测稳定性 | 在 3~7 个点上学出来的参数本质是过拟合，跨用户泛化无从验证 |
| 可解释性 | 与项目既有"每条结论都能手工复核"的原则直接冲突 |
| 结论 | **明确否决**。不是"暂时不做"，而是当前数据规模下**技术上不成立** |

### 5.1 结论

```text
A：当前月线性外推 → 否决（与 4-A 重复）
B：历史月度加权   → 采用（核心）
C：星期结构       → 否决（数据密度不足）
D：EWMA          → 否决（可解释性更差、与 B 等价）
E：机器学习       → 否决（数据量、部署、可解释性三重不成立）
```

---

## 6. 最终推荐算法

### 6.1 样本选择

```text
窗口：最近 6 个完整自然月（不含当前月）+ 当前月（只用于展示"本月进行中"，不参与预测）

可用月（usable month）判定：该自然月内至少有 1 条 type=1（支出）账单
取样顺序：按时间倒序取最近 min(3, 可用月数) 个月
```

### 6.2 加权公式

```text
权重：最近月 w=3，次近月 w=2，第三近月 w=1（不足 3 个月时按 3、2 顺延）

predictedAmount = Σ(w_i × amount_i) / Σ(w_i)        （四舍五入到分）
```

权重取 3 : 2 : 1 的理由：它是"最近 3 个月里，最近一个月占一半权重"的整数近似，
与"生活费按月发放、消费习惯按月变化"的直觉一致，且三人可验算的整数比
比小数权重更容易在答辩时解释。

示例（对应 §3 的展示）：6 月 ¥1,320、7 月 ¥1,180、8 月 ¥1,250

```text
predicted = (1250×3 + 1180×2 + 1320×1) / 6 = 7430 / 6 = ¥1,238.33
```

### 6.3 为什么不混合"当前月节奏"

曾考虑：`predicted = 0.7 × 历史加权 + 0.3 × 本月线性外推`。**否决**，原因：

1. 混合公式里再次出现 4-A 的 `日均 × 月天数`，两个能力的口径会互相渗透，边界变模糊；
2. 两个权重（0.7 / 0.3）没有客观依据，用户无法复核；
3. 当前月的节奏已经通过"本月已支出 ¥X（已过 N 天）"这行文字给用户看，不需要进入预测值。

### 6.4 与上月对比

```text
previousMonthAmount    = 上一个完整自然月的实际支出（可能无数据）
predictedDifference    = predictedAmount − previousMonthAmount
predictedChangePercent = (predictedAmount − previousMonthAmount) / previousMonthAmount × 100
                         （上月无数据或为 0 时返回 null，前端显示"暂无对比"）
```

这里刻意复用 `/statistics/trends` 已确立的口径（`previousHasData` + 可空变化率），
让前端"暂无对比数据"的处理方式保持一致。

---

## 7. 冷启动方案

### 7.1 状态定义

| 状态 | 触发条件（全部客观可测） | 页面表现 |
| --- | --- | --- |
| `NOT_APPLICABLE` | `month` 不是服务器当前月 | 「下月预估仅对当前月份有效」 |
| `NO_DATA` | 最近 6 个完整月 + 当前月**没有任何支出账单** | 「记录几笔账单后，这里会给出下月预估」 |
| `INSUFFICIENT_DATA` | 有支出，但**可用完整月 < 2**（即只有 1 个月或 0 个月有记录） | 「再记录满 1 个完整月份，预测会更准」+ 展示已有月份的事实值 |
| `OK` | 可用完整月 ≥ 2 | 展示预估卡片 |

### 7.2 为什么"可用月 < 2"就不预测

- 只有 1 个月的数据时，"趋势"无从谈起，预测值等于那一个月的金额，没有信息量；
- 与 4-A 的 `MIN_SPENT_DAYS = 3`（本月消费天数 < 3 天不预测）是同一设计哲学：
  **数据不足时宁可不预测**，避免用户把噪声当成结论。

### 7.3 关于"本月只有 1~2 天数据"

因为 4-D 预测的是**下个月**，当前月只是展示项、不进入计算，
因此"本月只有 1~2 天"**不会**影响预测本身，只会让 `currentMonthAmount` 显得很小。
卡片文案对当前月只做事实陈述（"本月已过 N 天，已支出 ¥X"），不给任何推断。

### 7.4 已知边界（如实记录）

用户"开始记账的第一个月"通常是月中起记，天然不完整。本设计**不**单独识别该月，
而是把它当作普通可用月参与计算；若它同时是唯一可用月，`INSUFFICIENT_DATA` 会自然挡住。
这属于已知偏差，记录在 §16 风险表，不额外增加查询。

---

## 8. 置信度规则

置信度**只由客观条件决定**，不使用任何主观判断：

```text
n      = 参与计算的可用月数（2 或 3）
W      = 加权预测值
spread = (max(amount_i) − min(amount_i)) / W      ← 样本的"极差比"

n < 2 → 不预测（INSUFFICIENT_DATA），没有置信度
```

| 置信度 | 条件 | 文案 |
| --- | --- | --- |
| `HIGH` | `n ≥ 3` 且 `spread ≤ 0.30` | 高可信 |
| `MEDIUM` | `n ≥ 3` 且 `spread ≤ 0.60`，或 `n = 2` 且 `spread ≤ 0.30` | 中等可信 |
| `LOW` | 其余可预测情形 | 仅供参考 |

**封顶规则**：若样本中存在被判定为"异常月"而降权的月份（§9），置信度最高只能到 `MEDIUM`。

阈值 0.30 / 0.60 的取法：3 个月样本里，最高月与最低月相差不超过 30% 可认为消费节奏稳定；
超过 60% 说明月度之间几乎没有可比性，只能"仅供参考"。
该阈值作为常量集中定义，便于后续调整与单测锁定。

`confidenceReason` 由后端生成客观描述，例如：

```text
近 3 个月最高 ¥1,320、最低 ¥1,180，相差 11.9%
仅 2 个月样本，可信度有限
某月支出明显高于其他月份，已降低其权重
```

---

## 9. 异常值处理

### 9.1 问题

```text
平时月消费 ¥1,500
某月因为买电脑变成 ¥8,500
→ 直接平均会把预测值拉到 ¥2,000 以上
```

### 9.2 设计（与 Stage 4-C **不重叠**）

```text
1. 取所有可用月金额的中位数 median
2. 若某月 amount > 2 × median → 判定为「异常月」
3. 异常月不剔除，而是把权重降为 1（保留信息，但不让它主导结果）
4. 置信度上限降为 MEDIUM，并在 confidenceReason 里说明
```

| 备选做法 | 为什么不用 |
| --- | --- |
| 直接剔除异常月 | 丢信息；如果用户确实每月都在高位消费，会被误剔 |
| 截尾（把异常月金额改成阈值） | 会造出一个现实中不存在的金额，违背"可解释" |
| 用平均数 | 正是被异常值拉爆的那个方案 |
| 复用 Stage 4-C 的异常检测结果 | 见 §9.3 |

### 9.3 明确不复用 Stage 4-C（并说明依赖关系）

**结论：4-D 不调用 `SpendingAnomalyService`，两者算法独立。**

理由：

1. **语义不同**：4-C 判定的是"某分类本月金额 vs 该分类前 3 月基线"与"单笔异常"；
   4-D 需要的是"**某个月的总额**是否整体偏离常态"。用 4-C 的结果去筛月份，
   需要把分类级异常拼装成月级异常，反而更复杂。
2. **失败耦合**：若复用，4-C 的窗口与阈值（`BASELINE_MONTHS=3`、`MIN_ABSOLUTE_DELTA=100` 等）
   一旦调整，4-D 的预测就会跟着变，两个已验收阶段的语义会互相牵制。
3. **成本**：复用意味着同一个请求里再跑一次 4-C 的两条查询。

4-D 只需要一次聚合查询（§12），异常月处理是内存里对 ≤3 个数字做的中位数比较，
**零额外查询、零额外服务依赖**。

---

## 10. API 设计

### 10.1 归属选择：`/api/insights/forecast`

| 候选 | 理由评估 |
| --- | --- |
| `/api/statistics/forecast` | `/api/statistics/*` 现在是"**事实**统计"家族：monthly / category / daily / source / daily-summary / trends，全部来自账单的确定性汇总，不含推断。把"预测"放进去会打破这一族的一致性 |
| **`/api/insights/forecast`（推荐）** | `/api/insights/*` 现在是"**推断**"家族：monthly（规则洞察）、recurring（模式识别）、anomalies（偏离检测），三个接口都返回 `status` + `message` + 可解释理由，与预测的形态完全一致 |
| `/api/budgets/forecast` | 4-D **不依赖预算**，挂到预算域名下会让"没有预算就用不了"的误解扩散 |

**推荐**：复用现有 `InsightsController`（`@RequestMapping("/api/insights")`）新增一个 GET，
不新建 Controller。

> 备注：`/api/statistics/trends` 也带一点"分析"色彩，属于历史遗留；
> 本阶段**不调整**它的位置（"不改已有 API"是硬约束）。

### 10.2 接口定义

```text
GET /api/insights/forecast?month=yyyy-MM
```

| 项 | 说明 |
| --- | --- |
| `month` | **参考月**，即页面上当前选中的月份（与统计页其它区块保持同一个参数语义） |
| 语义 | 当且仅当 `month` = 服务器当前月时，预测**下一个月**；其他月份返回 `NOT_APPLICABLE` |
| 鉴权 | 复用 `AuthInterceptor` + JWT；未登录 401 |
| 用户隔离 | `userId` 只来自 `CurrentUser.get()`，方法签名不接受 `userId` |
| 参数校验 | 空值 / 格式错误 → 400（复用 `Months.parse`） |
| 范围限制 | 参考月是未来月份 → `NOT_APPLICABLE`（与 4-A 一致，不抛错） |

**为什么 `month` 是"参考月"而不是"目标月"**：统计页所有区块都用同一个 `_month`；
如果 4-D 改成"目标月"，前端就必须为它单独 +1 个月，破坏"一个月份驱动整页"的既有约定。
采用"参考月"后，前端**不需要任何特殊处理**。

### 10.3 与相邻接口的边界（一句话对照）

```text
/api/insights/monthly     本月结构（过去）
/api/insights/recurring   会重复的支出（过去 → 模式）
/api/insights/anomalies   本月偏离常态的地方（过去 vs 过去）
/api/insights/forecast    下个月大概花多少（未来）        ← 新增
/api/budgets/predictions  本月会不会超预算（本月 → 月末，依赖预算）
```

---

## 11. DTO 设计

| 字段 | 采用 | 理由 |
| --- | --- | --- |
| `month` | 采用 | 参考月，前端用来对齐区块 |
| `targetMonth` | 采用 | 被预测的月份（当前月 + 1），页面要写"预计 2026-10 支出 …" |
| `status` | 采用 | `OK` / `INSUFFICIENT_DATA` / `NO_DATA` / `NOT_APPLICABLE` |
| `message` | 采用 | 一句话结论，直接展示 |
| `confidence` | 采用 | `HIGH` / `MEDIUM` / `LOW`，非 OK 时为 `NONE` |
| `confidenceLabel` | 采用 | 高可信 / 中等可信 / 仅供参考（与 4-B、4-C 的 `severityLabel` 风格一致） |
| `confidenceReason` | 采用 | 置信度的客观依据，可解释性的核心 |
| `predictedAmount` | 采用 | 预估金额（字符串，两位小数） |
| `previousMonthAmount` | 采用 | 对比基准（上月实际支出） |
| `predictedDifference` | 采用 | 与上月的差额（可解释"多花 / 少花多少"） |
| `predictedChangePercent` | 采用 | 变化率；上月无数据时为 `null` |
| `currentMonthAmount` | 采用 | 本月至今实际支出（事实陈述，用于锚定语境） |
| `elapsedDays` | 采用 | 本月已过天数（事实陈述） |
| `sampleMonths` | 采用 | `[{month, amount, weight}]`，≤3 条，让用户能手工复核 |
| `historicalAverage` | **不采用** | 与 `predictedAmount` 完全等价（本设计不做混合），两个字段会让人误以为预测值另有来源 |
| `remainingPredictedAmount` | **不采用** | 语义是"本月剩余天数预计还要花多少"，属 4-A 的领地，会造成重复 |
| `totalDays` | **不采用** | 前端可由 `targetMonth` 推出，且本设计不需要月天数参与计算 |

最终响应结构：

```text
ForecastResponse
├── month                    参考月（yyyy-MM）
├── targetMonth              预测目标月（yyyy-MM）
├── status                   OK / INSUFFICIENT_DATA / NO_DATA / NOT_APPLICABLE
├── message                  一句话结论
├── confidence               HIGH / MEDIUM / LOW / NONE
├── confidenceLabel          高可信 / 中等可信 / 仅供参考 / —
├── confidenceReason         置信度依据（可空）
├── predictedAmount          预估金额（status != OK 时为 "0.00"）
├── previousMonthAmount      上月实际支出（无数据时 "0.00"）
├── predictedDifference      预计差额（可空）
├── predictedChangePercent   预计变化率（可空）
├── currentMonthAmount       本月至今实际支出
├── elapsedDays              本月已过天数
└── sampleMonths             参与计算的月份（最多 3 条，含权重）
```

金额一律为字符串（项目既有约定：`BigDecimal` → 字符串，前端用整数分做展示计算）。

---

## 12. 数据库 / Mapper 设计

### 12.1 数据库

```text
新增表：无
新增字段：无
新增索引：无
数据迁移：无
```

仍然只有 `user` / `bill` / `budget` / `import_batch` 四张表。

### 12.2 查询设计：**0 个新 Mapper 方法，1 次查询**

复用 `BillMapper#sumByCategoryAndMonth(userId, type, start, end, pattern)`：

```text
start = 6 个完整月之前那个月的 1 日
end   = 今天
type  = 1（支出）
```

返回行 = 「分类 × 月份」，最多 7 个月 × 10 个分类 = **≤70 行**；
在内存里按月份求和 → 得到每月支出合计、有数据的月份集合、以及当前月已支出。

也就是说，**一次查询同时满足**：

1. 历史各月支出（预测输入）；
2. 哪些月份有数据（可用月判定）；
3. 当前月已支出（展示用）。

### 12.3 依赖关系（必须写清楚）

```text
ForecastService ──依赖──▶ BillMapper（数据访问层）
        ✗ 不依赖 SpendingAnomalyService
        ✗ 不依赖 BudgetPredictionService
        ✗ 不依赖 InsightsService
```

`sumByCategoryAndMonth` 是 Stage 4-C 引入的 Mapper 方法，4-D 复用它是**方法级复用**，
不是服务级耦合：它的 SQL 语义（`user_id` + `type` + 日期区间，按「分类 + 月份」聚合）
与本需求完全一致。

> Step 2 实现时**不改动**该方法的注释与实现（避免动到已验收代码），
> 只在新的 Service 里写清楚"复用它的原因"。

### 12.4 备选方案与取舍

| 备选 | 取舍 |
| --- | --- |
| 新增 `sumExpenseByMonth` | 更贴合语意，但属于**重复 SQL**（同一张表、同一个索引、几乎相同的 WHERE），违背"先复用后新增" |
| 按月份循环调用 `sumByType` | 6~7 次查询，**制造 N+1**，直接否决 |
| 复用 `selectExpenseDetails`（明细） | 月度合计不需要逐笔明细，取数过重 |

---

## 13. 性能设计

| 项 | 设计值 |
| --- | --- |
| 查询次数 | **固定 1 次**（历史聚合）；`NOT_APPLICABLE` 时为 0 次 |
| 数据范围 | 最近 7 个月（6 个完整月 + 当前月） |
| 返回行数 | ≤ 70 行（月份 × 分类） |
| 内存计算 | O(月份数) ≤ 7，外加一次 ≤3 个元素的中位数比较 |
| 使用索引 | 既有 `idx_bill_user_date`（`user_id` + `bill_date`）或 `idx_bill_user_type_date`（多一个 `type` 条件），**不新增索引** |
| LIMIT | **不需要**：结果行数由"月份数 × 分类数"决定，与账单条数无关 |
| N+1 | 不存在（无按月份 / 按分类的循环查询） |
| 对照实测 | Stage 4-C 在同一环境用 12000 条账单实测 `/api/insights/anomalies` 中位数 27.5 ms（两次查询，其中一次是带 `LIMIT 2000` 的明细查询）。4-D 只有一次聚合、且不取明细，**预期不高于该量级** |

极端情况讨论（单个用户 100,000 条账单）：

- 4-D 只做**范围聚合**，不取明细、不排序、不分页；扫描量与该用户在 7 个月窗口内的账单数成正比；
- 即使该用户在 7 个月内累计 10 万条（≈14,000 条 / 月，属异常极端），也仍是索引区间扫描 + 分组，
  没有明细排序、没有 `LIMIT` 截断风险，最坏情况是耗时随行数线性增长；
- **不引入缓存、不引入新索引**。Step 2 用 EXPLAIN + 一次 12000 条规模实测来验证，
  与 Stage 4-B / 4-C 的验证方法保持一致。

---

## 14. Frontend 设计

### 14.1 统计页（唯一接入点）

相对现在只插入一个区块：

```text
本月概览
→ 预算卡
→ 智能预算预测        （4-A：有预算时的"会不会超"）
→ 周期性支出提醒      （4-B）
→ 消费异常提醒        （4-C）
→ 消费趋势预测        （4-D：下月预估）      ← 新增
→ 本月消费洞察        （Stage 3）
→ 分类统计 / 来源统计 / 趋势图（事实）
```

理由：两个"提醒类"区块连着放，然后进入"预测"这种分析型内容，最后落到"事实类"的统计与图表。
用户阅读路径是"先看提醒 → 再看结论 → 最后看数据"。

### 14.2 首页：建议**不新增卡片**

证据：首页当前已经发 **7 个请求**、显示 6 个区块（§2.3）。
再加一个"下月预估"会产生两个问题：

1. **信息过载**：首页会同时出现"本月概览 + 比上月 ↑/↓"（`/statistics/trends`）、
   "本月预算预测"（4-A）、"下月预估"（4-D）三个相邻的金额结论；
2. **概念混淆**：普通用户很难区分"本月预计支出"与"下月预计支出"，
   尤其 4-A 的 `projected` 与 4-D 的 `predictedAmount` 都叫"预计"。

替代方案（三选一，交给用户定）：

| 方案 | 说明 |
| --- | --- |
| **H1（推荐）** | 首页不加内容。想看预测去统计页（那里本来就有完整分析区） |
| H2 | 在现有「本月消费概览」卡片底部加一行文字入口「查看下月消费预测 →」，点击切到统计页；**不新增请求** |
| H3 | 首页加一张极简卡片，只在 `confidence = HIGH` 时显示，复用同一个接口（+1 个请求） |

### 14.3 组件与文件（预计）

```text
lib/models/forecast.dart          新增：ForecastResponse + MonthSample（防御性解析）
lib/services/insight_service.dart 扩展：forecast(month)（复用 ApiClient，不新建 Service）
lib/widgets/forecast_card.dart    新增：ForecastCard + ForecastSection（结构对齐 anomaly_card.dart）
lib/pages/statistics_page.dart    修改：新增字段 + 独立 try/catch + 插入区块
复用：Money / Brand / Card 区块模式；不新增工具类
```

**不需要新页面**（不做独立"预测详情页"），**不需要新图表依赖**。
可选增强（建议延后）：用已有的 `fl_chart` 画"近 3 个月 + 预计下月"的小柱状图；
首版以**文字 + 样本明细**为主，可解释性优先、实现风险最低。

### 14.4 如何避免"预测被当成事实"

1. 区块标题用 **「消费趋势预测」**，不出现"将会""一定"等措辞；
2. 金额统一带 **「预计」** 前缀（`预计 ¥1,238`），不写裸数字；
3. 始终显示 **置信度标签**（高可信 / 中等可信 / 仅供参考）；
4. 始终显示 **依据**（`近 3 个月加权：8月 ¥1,250×3、7月 ¥1,180×2、6月 ¥1,320×1`）；
5. 卡片底部固定一行说明：**「按你过去的记账节奏推算，仅供参考，不代表实际支出」**；
6. `INSUFFICIENT_DATA` / `NO_DATA` 时不显示任何金额，只显示引导文案（不硬凑数字）。

### 14.5 状态与降级

| 状态 | UI |
| --- | --- |
| `loading` | 「正在计算下月预估…」+ 转圈（区块独立 loading） |
| `error` | 错误文案 + 「重试」（区块独立，不影响其他区块） |
| `OK` | 预估卡片 + 置信度 + 依据 + 免责说明 |
| `INSUFFICIENT_DATA` | 引导文案 + 已有月份的事实值 |
| `NO_DATA` | 「记录几笔账单后，这里会给出下月预估」 |
| `NOT_APPLICABLE` | 「下月预估仅对当前月份有效」（切换历史月份时出现），不占大块空白 |

与现有 3 个智能区块完全一致的降级策略：`_load()` 内独立 `try/catch`，失败只隐藏本区块。

---

## 15. 测试矩阵

### 15.1 后端（预计 ≥ 32 个用例，新建 `ForecastServiceTest`）

| 分组 | 用例 |
| --- | --- |
| 冷启动 | 无任何账单 → `NO_DATA`；只有当前月账单 → `INSUFFICIENT_DATA`；只有 1 个完整月 → `INSUFFICIENT_DATA` |
| 样本 | 2 个可用月 → `OK`；3 个可用月 → `OK`；有 6 个月数据 → 只取最近 3 个 |
| 缺月 | 中间某月无账单（跳过该月，按剩余月份加权）；6 个月中只有 2 个月有数据 |
| 加权 | 3:2:1 逐位核对；2 个月时按 3:2；该月有记录但金额为 0 的处理 |
| 异常月 | 某月 > 2×中位数 → 权重降为 1 且置信度封顶 MEDIUM；两个异常月；所有月份金额相同（无异常月） |
| 对比 | 上月有数据 → 差额 / 变化率正确；上月无数据 → `null`；上月为 0 → `null` |
| 置信度 | `n=3` 且 spread ≤ 0.30 → HIGH；`n=3` 且 0.30 < spread ≤ 0.60 → MEDIUM；`n=2` 且 spread ≤ 0.30 → MEDIUM；`n=2` 且 spread > 0.30 → LOW；存在异常月时封顶 MEDIUM |
| 参数 | 非法 month 格式 → 400；空 month → 400；未来月份 → `NOT_APPLICABLE`；历史月份 → `NOT_APPLICABLE` |
| 边界 | 跨年（参考月为次年 1 月 → `targetMonth` 正确）；闰年 2 月；当月 31 号；当月 1 号（本月仅 1 天） |
| 金额 | 大金额（8 位整数）；两位小数不进位丢失；`type=2/3` 不参与 |
| 安全 | 两个用户互不可见；查询固定带当前用户 |
| 性能 | 查询次数固定为 1（`verify(times(1))`），无 N+1 |

### 15.2 前端（预计 ≥ 16 个用例，新建 `forecast_test.dart` + `forecast_integration_test.dart`）

| 分组 | 用例 |
| --- | --- |
| 解析 | 完整 JSON；缺 `sampleMonths`；`sampleMonths` 为 null / 含非对象元素；未知字段忽略；金额非法字符串容错；`predictedChangePercent` 为 null |
| 状态 | `OK` / `INSUFFICIENT_DATA` / `NO_DATA` / `NOT_APPLICABLE` 四种渲染；无预估金额时不渲染金额行 |
| 置信度 | HIGH / MEDIUM / LOW 三档文案与配色；未知值安全降级 |
| 展示 | 金额 `¥1,238.33` 格式；变化率 `+x%` / `-x%`；样本月份明细渲染；免责说明固定存在 |
| 交互 | loading；error + 重试回调；API 失败时区块隐藏且不影响其他区块 |
| 联调 | 有 3 个月历史 → `OK`；只有当前月 → `INSUFFICIENT_DATA`；空账号 → `NO_DATA`；历史月份 → `NOT_APPLICABLE`；用户隔离（B 看不到 A 的预测）；后端未启动时自动 skip |

---

## 16. 风险清单

| # | 风险 | 等级 | 说明与缓解 |
| --- | --- | --- | --- |
| 1 | **与 4-A 概念混淆** | 高 | 同页同时出现"本月预计支出"（4-A）与"下月预计支出"（4-D）。缓解：标题、文案、免责说明严格区分；4-D 文案不出现"预算"二字 |
| 2 | 首个记账月不完整导致低估 | 中 | 用户月中开始记账，该月被当作完整月参与加权。缓解：记为已知限制；样本少时置信度自然下降 |
| 3 | 月度样本过少（2 个月）时预测不稳 | 中 | 通过 `INSUFFICIENT_DATA`（<2 个月）与 LOW 置信度缓解 |
| 4 | 单笔大额污染预测 | 中 | 通过"中位数 × 2 判异常 + 降权 + 置信度封顶"缓解 |
| 5 | 用户把预测当承诺 | 中 | 通过"预计"措辞 + 置信度标签 + 依据展示 + 免责说明缓解 |
| 6 | 与 4-C 口径互相渗透 | 低 | 明确不复用 4-C；异常月判定只在内存对 ≤3 个数字做中位数比较 |
| 7 | 复用 4-C 引入的 Mapper 方法带来的隐性依赖 | 低 | 只依赖 Mapper（SQL 语义稳定），不依赖 Service；在 Service 注释中写明复用原因 |
| 8 | 首页信息过载 | 中 | 已建议首页不新增卡片（§14.2） |
| 9 | 统计页请求数达到 10 个 | 低 | 统计页当前 9 个请求，新增 1 个为串行；若感到慢，可在 Step 2 顺带评估并发化（**不属于本阶段范围**） |
| 10 | Stage 4-C 的 WARNING（Mapper 注释）被"顺手修掉" | 低 | 明确禁止；本阶段只记录 |

---

## 17. 明确不做事项

### 17.1 本阶段（Step 1）不做

- 不写任何 Java / Dart / SQL / YAML / JSON；
- 不改数据库、不改配置、不改测试；
- 不修改 Stage 4-A / 4-B / 4-C 的任何代码与文档快照；
- 不修复 Stage 4-C 的 `sumByCategoryAndMonth` 注释 WARNING（只记录）。

### 17.2 Stage 4-D 整体不做

| 不做的事 | 理由 |
| --- | --- |
| 机器学习 / ARIMA / Prophet / LSTM / Python 服务 | 3~7 个月的个人数据不足以支撑，且破坏单体架构与可解释性（§5 方案 E） |
| 星期 / 日期结构建模 | 个人记账数据稀疏，噪声大于信号（§5 方案 C） |
| EWMA | 与方案 B 等价但更难解释（§5 方案 D） |
| **未来 7 天预测** | 需要更强的"周内季节性"，现有数据不支持；且它与 4-A 的本月外推在数值上高度重叠，会产生两个几乎一样的数字。**延期** |
| **分类级预测（餐饮 ¥620 / 交通 ¥120 …）** | 单分类月度样本更稀疏（医疗、学习等分类可能几个月才出现一次），噪声远大于总额波动。**延期**。若后续要做，应限定"最近 3 个月中至少出现 2 次的分类"并只出 Top 3 |
| 新增数据库表 / 字段 / 索引 | 需求可用既有表与既有索引完全覆盖 |
| 新增页面 / 新增图表依赖 | 复用现有 Card 区块与 `fl_chart`（图表本身也建议延后） |
| 预测"哪一天会花完生活费""下月会不会超预算" | 属 4-A 语义，不重复 |
| 修改 `/api/statistics/trends` | 既有 API 语义冻结 |
| 顺手修复无关问题 | 明确禁止 |

---

## 18. 下一步实施建议

若用户确认 §1 的三点，建议 Step 2 按下列顺序实施（每步跑完测试再进入下一步）：

```text
Step 2-1  DTO + Service 算法（含全部后端单测）→ mvn test
Step 2-2  Controller 新增 GET /api/insights/forecast（含参数与状态分支测试）→ mvn test
Step 2-3  前端 model + service + widget + 统计页接入 → flutter analyze / flutter test
Step 2-4  真实联调（3 个月数据 / 空账号 / 单月账号 × 两个用户验证隔离）
Step 2-5  构建（web / apk）+ 性能实测（EXPLAIN + 12000 条规模）
Step 2-6  文档同步（README + 设计文档附录 L）
```

预计改动面：

```text
新增：backend dto/ForecastResponse.java、dto/ForecastMonthSample.java、service/ForecastService.java
      frontend lib/models/forecast.dart、lib/widgets/forecast_card.dart
      测试 ForecastServiceTest.java、forecast_test.dart、forecast_integration_test.dart
修改：backend controller/InsightsController.java（+1 个 GET）
      frontend lib/services/insight_service.dart（+1 个方法）、lib/pages/statistics_page.dart（+1 个区块）
不改：数据库、Mapper（0 个新方法）、配置、既有 Service、既有 DTO、既有测试
```

---

## 附：本报告依赖的事实来源

| 结论 | 证据 |
| --- | --- |
| 4-A 已实现本月预计支出 / 使用率 / 触顶日 | `BudgetPredictionService.java:168-215`；`BudgetPredictionItem` 的 `projected` / `projectedUsageRate` / `overDate` |
| 系统内没有任何"下月 / 未来"预测 | 全仓库搜索 `forecast`、`Forecast`、`下月`、`未来 7 天` → 0 命中（`预测` 仅出现在 4-A 相关文件） |
| 已有一条可覆盖多月的月度聚合 SQL | `BillMapper#sumByCategoryAndMonth`（返回 category / month / amount / count） |
| 首页已发 7 个请求、6 个区块 | `home_page.dart` `_load()` 与 build 主体（209~224 行） |
| 统计页当前 9 个请求、区块顺序 | `statistics_page.dart` `_load()` 与 build 列表（265~293 行） |
| 数据深度只有 3~7 个月 | 本地测试库实测：单用户最多 124 条 / 7 个月；全库按月分布 2026-03 ~ 2026-09 |
| `MonthSelector` 可以翻到未来月份 | `frontend/lib/widgets/month_selector.dart`（无上下界） |
| 4-C 的唯一 WARNING 是 Mapper 注释 | `docs/Stage4C-Documentation-Verification.md` §8 |
