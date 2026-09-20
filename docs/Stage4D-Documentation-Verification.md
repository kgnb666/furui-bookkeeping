# Stage 4-D Documentation Sync Report

> Stage 4-D Step 4（文档同步与一致性验证）的产出。
> 本阶段**只修改 Markdown 文档**：没有改动任何 Java / Dart / SQL / YAML / 配置 / 测试代码，
> 没有改动数据库结构，没有修复历史 WARNING，没有改动任何历史阶段报告与历史附录。
> 验证时间：2026-09-18

---

## 1. 修改文件列表

| 文件 | 类型 | 变更 |
| --- | --- | --- |
| `README.md` | 修改 | 新增「11. 智能下月支出预估」功能章节；统计页顺序补入新块；智能能力接口表新增 forecast 行 + 「下月预估接口细节」小节；后端测试数字 255 → **292**；前端 201 → **251**、离线 154/47 → **195/56**；后端与前端覆盖说明各补一段；新增预估联调用例说明；新增 Stage 4-D 真实联调结论；开发阶段表新增 Stage 4-D 行 |
| `docs/项目设计文档-v1.0.md` | 修改 | 文末新增「附录 L：Stage 4-D 智能下月支出预估」（L.1~L.10）；附录 D 变更记录表新增一行 |
| `docs/Stage4D-Documentation-Verification.md` | 新建 | 本文件 |

本阶段被写入的文件仅两个（实测时间戳）：

```text
README.md                              2026-09-18 21:20:23
docs/项目设计文档-v1.0.md               2026-09-18 21:21:30
```

代码文件的最后修改时间均早于本阶段（`SpendingForecastService.java` 14:50、
`InsightsController.java` 14:49、`statistics_page.dart` 21:04、`forecast_card.dart` 21:04），
证明 Step 4 **没有触碰任何代码**。

未修改清单：`backend/src/` 下的全部 Java、`frontend/lib/`、`frontend/test/` 下的全部 Dart、
`sql/` 下的全部 SQL、`pom.xml`、`pubspec.yaml`、`application.yml`、
`docs/Stage4D-Design-Review.md`、`docs/Stage4B-*.md`、`docs/Stage4C-*.md`、`docs/Stage6-*.md`、附录 E~K。

---

## 2. 一致性验证链

```text
代码（SpendingForecastService / InsightsController / DTO）   OK  未改动
  ↓
API（GET /api/insights/forecast?month=yyyy-MM）              OK  路径、参数、字段、状态一致
  ↓
测试（后端 292 / 前端 251 / 离线 195+56）                     OK  均为实测数字
  ↓
README                                                      OK  功能、接口、顺序、测试数字、阶段表
  ↓
设计文档附录 L                                               OK  L.1~L.10 齐全
```

---

## 3. 逐项检查结果

### 3.1 forecast 接口存在

| 检查 | 结果 |
| --- | --- |
| 代码 | `InsightsController` 第 69~70 行：`@GetMapping("/forecast")` + `@RequestParam String month`；类级 `@RequestMapping("/api/insights")` ⇒ `/api/insights/forecast` |
| README | 接口表新增 `GET /api/insights/forecast?month=2026-09` 行，并新增「下月预估接口细节」小节（共 3 处出现） |
| 设计文档 | 附录 L.6 记录完整路径、参数与响应 |
| 结论 | 一致 |

### 3.2 SpendingForecastService 存在

| 检查 | 结果 |
| --- | --- |
| 代码 | `service/SpendingForecastService.java`：`HISTORY_WINDOW_MONTHS=6`、`SAMPLE_MONTHS=3`、`MIN_SAMPLE_MONTHS=3`、`WEIGHTS={3,2,1}`、`OUTLIER_MULTIPLIER=2`、`OUTLIER_WEIGHT=1`、`HIGH_SPREAD=0.30`、`MEDIUM_SPREAD=0.60`，以及四个 status 常量与四个 confidence 常量 |
| README | 「11. 智能下月支出预估 → 实现位置」写明 `SpendingForecastService`、`SpendingForecastResponse`、`ForecastSampleMonth` |
| 设计文档 | 附录 L.2 架构图与 L.4 算法 |
| 结论 | 一致 |

### 3.3 README 描述一致

| README 要点 | 代码依据 | 一致 |
| --- | --- | --- |
| 不依赖预算、只预测下个月 | `forecast()` 不查询 `budget` 表，`targetMonth = reference.plusMonths(1)` | 是 |
| 最近 3 个有效完整自然月 | `SAMPLE_MONTHS = 3` + `recentSamples()` 跳过空月 | 是 |
| 3 : 2 : 1 加权 | `WEIGHTS = {3, 2, 1}` + `weightedSum / weightTotal` | 是 |
| 异常月 = 高于中位数 2 倍 → 权重降为 1 | `OUTLIER_MULTIPLIER = 2`、`OUTLIER_WEIGHT = 1` | 是 |
| 置信度 HIGH / MEDIUM / LOW | `HIGH_SPREAD = 0.30`、`MEDIUM_SPREAD = 0.60` | 是 |
| 四种状态 | `STATUS_OK / STATUS_INSUFFICIENT_DATA / STATUS_NO_DATA / STATUS_NOT_APPLICABLE` | 是 |
| 当前月不参与预测 | `recentSamples()` 从 `current.minusMonths(1)` 开始取 | 是 |
| 一次聚合查询、无 N+1 | 只调用 `sumByCategoryAndMonth`，单测 `verify(times(1))` | 是 |
| 不新增表 / 字段 / 索引 / Mapper | 仅复用 Stage 4-C 引入的 Mapper 方法 | 是 |

### 3.4 附录 L 存在

| 小节 | 行号 | 内容 |
| --- | --- | --- |
| L.1 功能目标 | 3218 | 预测下月总支出、不依赖预算、与 4-A 的对照表 |
| L.2 架构设计 | 3236 | 后端 4 个文件 / 前端 4 个文件的职责 |
| L.3 数据流程 | 3255 | 统计页 → Service → Controller → Mapper → 内存计算 → DTO |
| L.4 算法设计 | 3282 | 有效月份定义、样本、3:2:1 公式、异常月降权、对比口径 |
| L.5 置信度 | 3325 | 极差比公式、三档阈值、依据文案、前端映射 |
| L.6 API | 3352 | 路径、鉴权、参数、范围、响应 14 字段、四种状态 |
| L.7 前端设计 | 3394 | 统计页位置、首页不展示、六种 UI 状态 |
| L.8 测试结果 | 3419 | 后端 292 / 前端 251 / 离线 195+56 / 真实接口 9 项 |
| L.9 性能 | 3464 | 查询次数 1、索引现状、12000 条实测 median 15.5 ms |
| L.10 已知限制 | 3485 | 8 条限制 |

附录 D 变更记录表已新增「附录 L」一行（第 2085 行）。

### 3.5 测试数字一致

见第 4 节。

### 3.6 没有修改代码文件

本阶段被写入的只有 `README.md` 与 `docs/项目设计文档-v1.0.md`。
该目录不是 Git 仓库，因此用文件系统时间戳作为证据：

| 类别 | 本阶段是否变化 |
| --- | --- |
| Java（main / test） | 否（最后一次修改 14:49~14:50） |
| Dart（lib / test） | 否（最后一次修改 21:04~21:06） |
| SQL / Flyway / schema | 否（没有任何 SQL 文件被写入） |
| pom.xml / pubspec.yaml / application.yml | 否 |
| 数据库结构 | 否（4 张表 / 13 个索引对象，与 Stage 4-C 验证时一致） |

### 3.7 没有修改历史附录

附录 E~K 的历史测试数字逐条复核，全部保持原值：

| 附录 | 后端数字 | 前端数字 | 状态 |
| --- | --- | --- | --- |
| E（Stage 6） | 108 | 44 | 原样 |
| F（品牌化 + 2-A） | 113 | 51 | 原样 |
| G（Stage 2.5） | 125 | 70 | 原样 |
| H（Stage 3） | 153 | 87 | 原样 |
| I（Stage 4-A） | 175 | 122 | 原样 |
| J（Stage 4-B） | 213 | 160 | 原样 |
| K（Stage 4-C） | 255 | 201 | 原样 |
| **L（Stage 4-D，本次新增）** | **292** | **251** | 新增 |

`docs/Stage4D-Design-Review.md`（Step 1 设计快照）与 `docs/Stage4C-*.md`、`docs/Stage6-*.md` 均未被修改。

---

## 4. 测试数字核对

本节数字全部来自 Step 2 / Step 3 的真实执行结果：

| 项 | 数字 | 来源 | 文档位置 |
| --- | --- | --- | --- |
| 后端全量 | `Tests run: 292, Failures: 0, Errors: 0, Skipped: 0` | `mvn clean test` / `mvn package` | README「八、测试与构建结果」+ 附录 L.8 |
| 后端新增 | 37（`SpendingForecastServiceTest`） | Step 2 | README「Stage 4-D 追加覆盖（37 个用例）」+ L.8 |
| 前端在线 | 251 passed / 0 skipped / 0 failed | `flutter test --dart-define=API_BASE_URL=…` | README + L.8 |
| 前端离线 | 195 passed / 56 skipped / 0 failed | `flutter test`（后端停止） | README + L.8 |
| 前端新增 | 41（单元/Widget）+ 9（真实联调） | Step 3 | README + L.8 |
| 真实接口联调 | 9/9 PASS | Step 3 联调用例 | README「真实联调」+ L.8 |
| 构建 | `flutter analyze` 无问题；web 与 apk 构建成功（58.9 MB） | Step 3 | README + L.8 |
| 性能 | 12000 条账单：median 15.5 ms、avg 15.6 ms、cold 74.6 ms | Step 2 | 附录 L.9 |

README 中已不存在过期数字（`Tests run: 255`、`201 个用例`、`154 passed` 均已被替换，实测无残留）。

---

## 5. 其他一致性检查

### 5.1 响应字段一致

`SpendingForecastResponse` 共 14 个字段，README 接口细节、附录 L.6 与 DTO 逐项对应：

```text
month / targetMonth / status / message / confidence / confidenceLabel / confidenceReason /
predictedAmount / previousMonthAmount / predictedDifference / predictedChangePercent /
currentMonthAmount / elapsedDays / sampleMonths
```

前端模型 `spending_forecast.dart` 的字段与之一一对应，未增加后端不存在的字段。

### 5.2 状态枚举一致

```text
代码   OK / INSUFFICIENT_DATA / NO_DATA / NOT_APPLICABLE（四个 STATUS 常量）
文档   README「状态说明」4 行 + 附录 L.6 状态表 4 行
前端   isOk / isInsufficient / isNoData / isNotApplicable + 四状态 UI 分支
```

### 5.3 算法公式一致

```text
代码   weightedSum = Σ(amount_i × WEIGHTS[i])；predicted = weightedSum / weightTotal
文档   (m1 × 3 + m2 × 2 + m3 × 1) / 6
实测   (1250×3 + 1180×2 + 1320×1) / 6 = 1238.33 → 接口返回 predictedAmount = 1238.33
```

### 5.4 前端页面顺序一致

```text
代码   statistics_page.dart 子节点顺序
       BudgetPredictionSection → RecurringBillSection → AnomalyCardSection → ForecastSection → 洞察 → 分类 → 来源 → 趋势
文档   README 与附录 L.7
       智能预算预测 → 周期性支出提醒 → 消费异常提醒 → 下月支出预估 → 本月消费洞察 → 分类统计 → 来源统计 → 趋势图
测试   spending_forecast_test.dart「预估区块位于消费异常与消费洞察之间」按控件类型索引断言顺序
```

首页未接入下月预估（README 与 L.7 均写明；代码中 `home_page.dart` 无 forecast 引用）。

### 5.5 Stage 4-A / 4-D 边界一致

| 维度 | Stage 4-A | Stage 4-D | README | 附录 L.1 |
| --- | --- | --- | --- | --- |
| 时间方向 | 本月 → 月末 | 本月 → 下月 | 已写明 | 已写明 |
| 依赖预算 | 依赖（无预算 `NO_BUDGET`） | 不依赖 | 已写明 | 已写明 |
| 计算方式 | 日均 × 当月天数 | 3:2:1 历史加权 | 已写明 | 已写明 |
| 结果形态 | 每个预算一条风险提示 | 一条总量 + 置信度 | 已写明 | 已写明 |

两份文档中不再存在把两个模块笼统称作「支出预测」的表述。

---

## 6. 已知限制

1. **用户最早那个月可能不完整**：月中开始记账的用户，其首个有支出的月份会被当作完整月参与加权，可能略微低估（样本少时置信度自动下降）；
2. **异常月降权后仍占 25% 权重**（`1 / 2 / 1`），只是不再主导结果；
3. **只预测总支出**，不拆分分类；**不预测未来 7 天**；
4. **不使用机器学习模型**：现实数据只有 3~7 个月，长序列模型在如此短的数据上等于过拟合；
5. **历史跨度有限**：只读参考月之前 6 个完整自然月；
6. **没有人工截图的视觉确认**：执行环境浏览器自动化不可用，前端渲染正确性由「真实后端数据 + Widget 渲染断言」覆盖；
7. **既有 WARNING 未修复（按规则）**：`BillMapper#sumByCategoryAndMonth` 的索引注释与执行计划不一致（Stage 4-C 遗留，附录 K.9 已记录），本阶段不处理；
8. **Step 1 设计快照与最终实现存在差异（按规则不回改）**：`docs/Stage4D-Design-Review.md` 中「OK 需 ≥2 个有效月」「置信度文案 = 高可信」是设计阶段口径；最终实现按后续确认收紧为「≥3 个有效月」，前端展示映射为「较稳定 / 一般 / 波动较大」，最终口径以附录 L 为准。

---

## 7. 最终 Gate

**PASS** — 文档状态已与真实代码状态一致：

| 维度 | 结果 |
| --- | --- |
| forecast 接口 | 代码 / README / 附录 L 三处一致 |
| SpendingForecastService | 代码 / README / 附录 L 三处一致 |
| 响应字段与状态枚举 | 后端 DTO、前端模型、两份文档全部一致 |
| 算法与公式 | 文档公式 = 代码实现 = 真实接口返回值（1238.33） |
| 前端页面顺序 | 代码子节点顺序 = 文档顺序 = 顺序断言 |
| 4-A / 4-D 边界 | 两份文档均有对照表，不再混淆 |
| 测试数字 | README 与附录 L 均为实测值（292 / 251 / 195+56） |
| 历史快照 | 附录 E~K 与历史报告零改动 |
| 代码改动 | 本阶段 0 行代码改动 |

**允许进入下一阶段**，本阶段到此停止，不自行推进。
