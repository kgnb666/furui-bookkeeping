# Stage 4-C Documentation Sync Report

> Stage 4-C 第四步（文档同步与最终验证）的产出。
> 本阶段**只修改文档**：没有改动任何 Java / Dart / SQL / 配置 / 测试代码，
> 没有改动数据库结构，没有改动 Stage 4-C 已验收的算法与阈值。
> 验证时间：2026-09-18

---

## 1. 修改文件列表

| 文件 | 类型 | 变更 |
| --- | --- | --- |
| `README.md` | 修改 | 新增「10. 智能消费异常检测」功能章节；接口表新增 `/api/insights/anomalies` 行 + 接口细节小节；测试结果更新为 255 / 201（并区分离线 154 / 47）；新增 Stage 4-C 后端与前端覆盖说明；新增消费异常联调用例说明；新增 Stage 4-C 真实联调结论；开发阶段表新增 Stage 4-C 行 |
| `docs/项目设计文档-v1.0.md` | 修改 | 文末新增「附录 K：Stage 4-C 智能消费异常检测」（K.1~K.10）；附录 D 变更记录表新增附录 K 一行 |
| `docs/Stage4C-Doc-Review.md` | 新建（上一阶段） | 文档同步前审查 |
| `docs/Stage4C-Documentation-Verification.md` | 新建（本文件） | 文档同步完成报告 |

**未修改**：`backend/src/**`（Java）、`frontend/lib/**`、`frontend/test/**`、
`sql/schema.sql`、`pom.xml`、`pubspec.yaml`、`application.yml`、`docker-compose.yml`、
历史文档 `docs/Stage4-B-*.md`、`docs/Stage6-*.md`、`frontend/README.md`。

---

## 2. 功能文档同步结果

`README.md` 新增第 10 节，与 `SpendingAnomalyService` 实现逐条对应：

| 文档要点 | 代码依据 | 一致 |
| --- | --- | --- |
| 只分析当前登录用户自己的账单，身份来自 JWT | `InsightsController#anomalies` 传 `CurrentUser.get()` | 是 |
| 不接受前端传入 `userId` | 方法签名只有 `month` | 是 |
| 当前月 + 前 3 个自然月做分类/频次基线 | `BASELINE_MONTHS = 3` | 是 |
| 单笔异常用目标月之前 90 天同分类中位数 | `TRANSACTION_WINDOW_DAYS = 90` + `filterBefore()` | 是 |
| 最多返回 5 条 | `MAX_ITEMS = 5` | 是 |
| HIGH / MEDIUM 两级严重度 | `severityRank` / `severityLabel` | 是 |
| 四种状态各有明确含义 | `detect()` 的四个分支 | 是 |
| 只读分析，不修改任何账单数据 | 全程只读，结果不落库 | 是 |
| 不新增数据库表、字段、索引 | 只有 2 个新增 Mapper 查询方法 | 是 |

三类异常的阈值、缺月处理、排序规则均已写入 README 与附录 K，
并特别写明 `LARGE_TRANSACTION` 的基线边界是「目标月开始之前 90 天」，
明确排除"目标月末往前 90 天"的错误口径。

---

## 3. API 文档同步结果

| 检查项 | 文档 | 代码 | 一致 |
| --- | --- | --- | --- |
| 路径 | `GET /api/insights/anomalies` | `@RequestMapping("/api/insights")` + `@GetMapping("/anomalies")` | 是 |
| 参数 | `month`（`yyyy-MM`，必填） | `@RequestParam String month` + `Months.parse` | 是 |
| 鉴权 | 复用 JWT / `AuthInterceptor`，未登录 401 | `/api/**` 拦截（未加白名单） | 是 |
| 用户隔离 | 身份来自 `CurrentUser`，不接受 `userId` | `CurrentUser.get()` | 是 |
| 范围限制 | 最近 12 个自然月 | `MAX_BACK_MONTHS = 12` + `ensureWithinWindow` | 是 |
| 参数错误 | 格式错误 / 未来月份 / 超范围均 400 | `BizException(400, ...)` 三处 | 是 |
| 响应结构 | `month` / `status` / `message` / `baselineMonths` / `items` | `AnomaliesResponse` | 是 |
| Item 字段 | 12 个（无多余字段） | `AnomalyItem` 12 个 `final` 字段 | 是 |
| status 取值 | `OK` / `NO_DATA` / `NOT_ENOUGH_BASELINE` / `NO_ANOMALY` | 四处 `AnomaliesResponse.of(...)` | 是 |

---

## 4. 架构文档同步结果

附录 K.2 记录的分派关系与 `InsightsController` 实际构造一致：

```text
InsightsController
        ├── GET /monthly    → InsightsService
        ├── GET /recurring  → RecurringBillService
        └── GET /anomalies  → SpendingAnomalyService
```

`SpendingAnomalyService` 的三个规则（`CATEGORY_SPIKE` / `LARGE_TRANSACTION` / `FREQUENCY_SPIKE`）
与两个 Mapper 查询（`sumByCategoryAndMonth` / `selectExpenseDetails`）均有对应说明；
「为什么独立成 Service」以「月度结构 vs 偏离常态」的职责划分写明。

---

## 5. 前端文档同步结果

| 检查项 | 文档 | 代码 | 一致 |
| --- | --- | --- | --- |
| 接入位置 | 统计页新增「消费异常提醒」 | `pages/statistics_page.dart:273` | 是 |
| 区块顺序 | 预算预测 → 周期支出 → 消费异常 → 消费洞察 → 分类 → 来源 → 趋势 | 源码顺序：`BudgetPredictionSection`(265) → `_buildRecurringSection`(271) → `_buildAnomalySection`(273) → `_buildInsightsSection`(275) → `_buildCategorySection`(289) → `_buildSourceSection`(291) → `_buildDailySection`(293) | 是 |
| 首页不展示 | 明确写「首页不展示消费异常提醒」 | `home_page.dart` 中 `anomal` / `异常` 命中 0 | 是 |
| 状态 UI | loading / OK / NO_DATA / NOT_ENOUGH_BASELINE / NO_ANOMALY / error | `AnomalyCardSection._buildBody` 六个分支 | 是 |
| 配色 | 后端不负责颜色，HIGH 品牌红 / MEDIUM 品牌橙 | `AnomalyCard.severityColor` | 是 |

---

## 6. 测试数据同步结果

本阶段**重新实测**（不是引用历史数字）：

```text
后端：mvn test        → Tests run: 255, Failures: 0, Errors: 0, Skipped: 0 / BUILD SUCCESS
前端：flutter analyze → No issues found (ran in 5.1s)
      flutter test    → 201 passed / 0 skipped / 0 failed（后端运行中）
      flutter test    → 154 passed / 47 skipped / 0 failed（后端不可用，联调用例自动跳过）
      flutter build web --release → Built build\web
      flutter build apk --release → Built build\app\outputs\flutter-apk\app-release.apk (58.9MB)
```

README 中的测试数字已更新为 255 / 201，并把「后端不可用时 154 passed / 47 skipped」
单独成段说明，避免与正常在线结果混淆。

---

## 7. 一致性检查结果

### 7.1 README 关键词

| 关键词 | 命中 |
| --- | --- |
| `Stage 4-C` | 3 |
| `消费异常` | 10 |
| `/api/insights/anomalies` | 3 |
| `SpendingAnomalyService` | 1 |
| `255` | 1 |
| `201` | 1 |

### 7.2 设计文档关键词

| 关键词 | 命中 |
| --- | --- |
| `附录 K` | 2 |
| `CATEGORY_SPIKE` | 8 |
| `LARGE_TRANSACTION` | 5 |
| `FREQUENCY_SPIKE` | 8 |
| `BIG_EXPENSE` | 9（迁移说明与新旧对比） |
| `SpendingAnomalyService` | 5 |

### 7.3 阈值逐项核对

| 阈值 | 代码常量 | 文档写法 | 一致 |
| --- | --- | --- | --- |
| 分类上涨触发 | `CATEGORY_SPIKE_RATIO = 1.5` | `current >= baseline × 1.5` | 是 |
| 分类上涨严重 | `CATEGORY_SPIKE_HIGH_RATIO = 2.5` | `current >= baseline × 2.5` | 是 |
| 单笔触发 | `TRANSACTION_RATIO = 3` | `amount >= median × 3` | 是 |
| 单笔严重 | `TRANSACTION_HIGH_RATIO = 5` | `amount >= median × 5` | 是 |
| 绝对差额 | `MIN_ABSOLUTE_DELTA = 100` | `>= ¥100` | 是 |
| 单笔样本 | `MIN_CATEGORY_SAMPLES = 5` | 样本 >= 5 笔 | 是 |
| 频次触发 | `FREQUENCY_SPIKE_RATIO = 2` | `currentCount >= baselineCount × 2` | 是 |
| 频次严重 | `FREQUENCY_SPIKE_HIGH_RATIO = 3` | `>= baselineCount × 3` | 是 |
| 频次增量 | `FREQUENCY_SPIKE_MIN_DELTA = 5` | 多 >= 5 笔 | 是 |
| 频次常态下限 | `MIN_BASELINE_COUNT = 2` | `baselineCount >= 2` | 是 |
| 基线月数 | `BASELINE_MONTHS = 3` | 前 3 个自然月 | 是 |
| 单笔窗口 | `TRANSACTION_WINDOW_DAYS = 90` | 目标月开始前 90 天 | 是 |
| 条数上限 | `MAX_ITEMS = 5` | 最多 5 条 | 是 |
| 明细上限 | `MAX_DETAIL_ROWS = 2000` | `LIMIT 2000` | 是 |
| 月份回溯 | `MAX_BACK_MONTHS = 12` | 最近 12 个自然月 | 是 |
| 排序 | 严重度降序 → 差额降序 → 分类字典序 | 同 | 是 |

### 7.4 数据库一致性

实测 MySQL（`campus-ledger-mysql-test`）：

```text
tables        = 4     （user / bill / budget / import_batch）
indexes_total = 13    （bill 7 个，其余三表各 2 个，均含主键）
indexes_no_pk = 9
```

文档只声明「无新增表 / 无新增字段 / 无新增索引」，与实测一致。
验证过程中临时插入的 12000 条压测数据与临时账号已在验证后删除，
`bill` 表行数回到 2575（与验证前一致）。

### 7.5 历史快照保护

附录 E~J 的历史测试数字**未被改动**，逐条复核如下：

| 附录 | 后端数字 | 前端数字 | 状态 |
| --- | --- | --- | --- |
| E（Stage 6） | 108 | 44 | 原样保留 |
| F（品牌化 + 2-A） | 113 | 51 | 原样保留 |
| G（Stage 2.5） | 125 | 70 | 原样保留 |
| H（Stage 3） | 153 | 87 | 原样保留 |
| I（Stage 4-A） | 175 | 122 | 原样保留 |
| J（Stage 4-B） | 213 | 160 | 原样保留 |
| K（Stage 4-C，本次新增） | **255** | **201** | 新增 |

README 中代表**当前状态**的数字已更新为 255 / 201。
设计文档正文（第 14 章页面清单、附录 J.9 的区块顺序）属于历史基线与本阶段之前的快照，
**按项目既有约定不回改**，最新顺序统一记录在附录 K.7。

---

## 8. 遗留问题

### WARNING（非阻塞，本阶段不修改代码）

| # | 问题 | 影响 | 处理 |
| --- | --- | --- | --- |
| 1 | `BillMapper#sumByCategoryAndMonth` 的注释写「走 `idx_bill_user_type_date` 索引」，实测执行计划选择 `uk_bill_user_dedup` | 仅注释描述不准。两者都是既有索引，查询无退化（无全表扫描、无 N+1），实测约 28 ms | 已记入附录 K.9，本阶段不修改代码 |
| 2 | `BillMapper#selectRecurringCandidates` 的注释与执行计划不一致（Stage 4-B 遗留） | 同上，已在附录 J.13 记录 | 维持原状 |

### 已知功能限制（不是缺陷，如实记录）

1. `LIMIT 2000` 明细上限；
2. 高数据量用户的历史基线覆盖可能被截断；
3. 没有季度 / 年度周期异常；
4. 商户为空时用分类回退展示；
5. `CATEGORY_SPIKE` 与 `FREQUENCY_SPIKE` 可能同时出现（刻意保留）；
6. 异常检测只在统计页，首页不展示；
7. 没有人工截图的视觉确认（执行环境浏览器自动化不可用，渲染正确性由真实数据 + Widget 断言覆盖）。

### 文档口径纠偏（本阶段）

| # | 原计划 | 实际处理 | 原因 |
| --- | --- | --- | --- |
| 1 | 在附录 J.9 追加一行"最新顺序见附录 K" | **未改动 J.9** | 项目既有约定是"附录 E 起不改动前面章节与既有附录"，最新顺序统一写在 K.7，并在 K.7 说明 J.9 是 Stage 4-B 时的状态 |
| 2 | 在设计文档 14.1 页面清单中补"消费异常区块" | **未改动 14.1** | 同上，属设计基线章节，不因实现阶段回改；页面最终形态记录在 K.7 |
| 3 | 附录 K.6 原写"4 张表、7 个索引" | 改为「4 张表；索引结构与数量完全未变，实测共 13 个索引对象（`bill` 7 个、其余三表各 2 个，均含主键）」 | 实测 `information_schema.statistics` 全库为 13 个索引对象，"7 个"实际是 `bill` 单表的索引数，写成"整库 7 个索引"会与实测不符 |
| 4 | 附录 K.9 原写"两个查询使用 `idx_bill_user_date`、对照 `/insights/monthly` 约 24.4 ms" | 改为实测执行计划（查询 1 走 `uk_bill_user_dedup`、查询 2 走 `idx_bill_user_date`）+ 实测耗时表（anomalies 约 28 ms、monthly 约 27.5 ms、recurring 约 17.4 ms） | 原文的两个数字无法复现，改用本轮 12000 条账单的真实测量值 |

---

## 9. 是否允许进入 Stage 4-D

### 最终 Gate：**CONDITIONAL PASS**

判定依据（逐环节核对）：

```text
代码（SpendingAnomalyService / InsightsController / BillMapper）  OK  未改动，行为与 Stage 4-C 第二步验收一致
  ↓
API（GET /api/insights/anomalies）                                OK  路径、参数、12 个 Item 字段、四种 status 与文档一致
  ↓
测试（后端 255 / 前端 201、离线 154+47、analyze 通过）             OK  本阶段实测
  ↓
构建（Web / APK）                                                  OK  本阶段实测
  ↓
README                                                            OK  已同步功能、接口、测试数字、阶段表
  ↓
设计文档附录 K                                                     OK  已新增 K.1~K.10
  ↓
Stage4C Documentation Verification（本文件）                       OK
```

**唯一未闭合项**：一条 WARNING —— `BillMapper#sumByCategoryAndMonth` 的索引注释与实测执行计划不符
（注释提到 `idx_bill_user_type_date`，实测走 `uk_bill_user_dedup`）。
它属于**注释描述问题**，不影响接口行为、数据、算法、性能与测试结果，
按本阶段"只允许修改文档、代码问题只记录不修改"的约束保持原样。

因此本阶段结论为 **CONDITIONAL PASS**：

- 文档层面的目标（文档状态 = 代码真实状态）**已达成**；
- 未闭合的是 Stage 4-C 代码里的一处注释不准确，需由后续阶段（或用户指定）决定是否在允许改代码的阶段修正。

**是否进入 Stage 4-D 由用户决定，本阶段不自行推进。**
