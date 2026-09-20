# Stage 4-C 文档同步前审查

> 本文件是 Stage 4-C 第四步（文档同步）的**第一阶段产物**。
> 本阶段只做只读扫描 + 输出审查结论，**不修改任何业务代码、测试、数据库与配置**。
> 审查时间：2026-09-17

---

## 当前文档状态

### 1. 项目内 markdown 文件清单

| 文件 | 大小 | 最后修改 | 定位 |
| --- | --- | --- | --- |
| `README.md` | 36 KB / 751 行 | 2026-09-17 22:11 | 面向使用者的主文档：功能介绍、技术栈、架构、接口表、测试结果、部署、开发阶段 |
| `docs/项目设计文档-v1.0.md` | 134 KB / 2814 行 | 2026-09-17 22:11 | 毕业设计设计文档：设计基线 + 附录 E~J 记录各阶段最终实现 |
| `docs/Stage4-B-智能周期性账单识别设计评审.md` | 38 KB | 2026-09-17 16:59 | Stage 4-B 阶段产物（设计评审） |
| `docs/Stage6-Audit-Report.md` | 13 KB | 2026-09-15 22:45 | Stage 6 历史审计报告 |
| `docs/Stage6-Final-Acceptance-Report.md` | 12 KB | 2026-09-15 22:53 | Stage 6 历史验收报告 |
| `frontend/README.md` | 2 KB | 2026-09-16 14:37 | 前端运行 / 构建 / 测试 / 品牌资源说明 |

`backend/docs/` 与 `frontend/docs/` **不存在**（前端说明直接放在 `frontend/README.md`）。
`docs/screenshots/` 下有 10 张历史截图，与本次同步无关。

### 2. 现有「洞察 / 智能」相关内容

| 位置 | 内容 |
| --- | --- |
| `README.md:82` | `### 7. 智能记账与消费洞察`（分类推荐 + 消费洞察） |
| `README.md:94` | `### 8. 智能预算预测` |
| `README.md:156` | `### 9. 智能周期性支出识别` |
| `README.md:506` | `### 智能能力（不调用任何大模型）` 接口表（3 条：recommend / monthly / recurring） |
| `README.md:516` | `## 八、测试与构建结果` |
| `README.md:736` | `## 十二、开发阶段`（末行止于 Stage 4-B） |
| `docs/项目设计文档-v1.0.md:1173` | `15.1 接口总览`（末节为预算模块，无智能接口） |
| `docs/项目设计文档-v1.0.md:2304` | 附录 H：Stage 3 智能记账与消费洞察 |
| `docs/项目设计文档-v1.0.md:2408` | 附录 I：Stage 4-A 智能预算预测 |
| `docs/项目设计文档-v1.0.md:2575` | 附录 J：Stage 4-B 智能周期性账单识别（文档末尾） |

### 3. 代码侧实际状态（本次同步的比对基准）

| 项 | 实际实现 | 证据位置 |
| --- | --- | --- |
| 接口 | `GET /api/insights/anomalies?month=yyyy-MM` | `controller/InsightsController.java:54` |
| 用户身份 | 只取自 `CurrentUser.get()`，方法签名不接收 userId | `InsightsController.java:55` |
| 服务 | `service/SpendingAnomalyService.java`（独立于 `InsightsService`） | 常量见 41~90 行，`detect()` 见 100 行 |
| 三类异常 | `CATEGORY_SPIKE` / `LARGE_TRANSACTION` / `FREQUENCY_SPIKE` | `SpendingAnomalyService` |
| 阈值 | 基线 3 个月、单笔窗口 90 天、样本 ≥5、`×1.5 / ×2.5`、`×3 / ×5`、频次 `×2 / ×3`、绝对差 ≥100、最多 5 条、明细上限 2000 行、最多回溯 12 个月 | 常量 `BASELINE_MONTHS`…`MAX_BACK_MONTHS` |
| 查询 | `sumByCategoryAndMonth()`、`selectExpenseDetails()`（均带 `user_id`） | `mapper/BillMapper.java:144`、`:169` |
| 旧规则 | `InsightsService` 中已无 `BIG_EXPENSE`（全文 0 命中） | `InsightsService.java` 无 BIG 常量与方法 |
| 前端 | 统计页新增区块，位于周期识别与消费洞察之间 | `pages/statistics_page.dart:273` |
| 前端文件 | `models/spending_anomaly.dart`、`widgets/anomaly_card.dart` | 已存在 |

---

## 发现的问题

### P0 — 必须补齐（否则「文档 = 代码」不成立）

1. **缺少「消费异常提醒」功能说明**
   全项目 md 搜索 `消费异常` / `anomal` / `SpendingAnomaly` **0 命中**。
   README「二、系统功能」只写到第 9 节（智能周期性支出识别），没有第 10 节。
2. **缺少 `/api/insights/anomalies` 接口文档**
   `README.md` 的智能接口表（506~512 行）只有 recommend / monthly / recurring 三行；
   设计文档 `15.1 接口总览`（1173 行起）连智能接口都未收录（历史遗留，本节按同一原则只补 Stage 4-C 一条并注明）。
3. **缺少 `SpendingAnomalyService` 架构说明**
   设计文档附录 J 记录的是 `InsightsService` + `RecurringBillService` 结构，未记录异常检测独立成 Service 的原因与职责边界。
4. **测试数量已过期**
   - `README.md:522` 写 `Tests run: 213` → 实际 **255**
   - `README.md:551` 写 `160 个用例全部通过` → 实际 **201**
   - 后端实测：`mvn test` → `Tests run: 255, Failures: 0, Errors: 0, Skipped: 0`，`BUILD SUCCESS`
   - 前端实测：后端在线 201 passed / 0 skipped；后端离线 154 passed / 47 skipped / 0 failed
5. **缺少 Stage 4-C 的阶段记录**
   `README.md:736` 开发阶段表末行为 Stage 4-B；
   设计文档附录 D 变更记录表（2075 行表头，末行附录 J 在 2083 行）末行为附录 J，文档正文末尾（2814 行）也停在 J.13。

### P1 — 应当补齐（影响可读性与答辩一致性）

6. **统计页区块顺序说明未更新**
   设计文档 `J.9`（2721 行）写「智能预算预测 → 周期性支出提醒 → 本月消费洞察」，
   实际顺序已变为「智能预算预测 → 周期性支出提醒 → **消费异常提醒** → 本月消费洞察 → 分类统计 → 来源统计 → 趋势图」。
7. **前端测试覆盖描述未包含异常模块**
   `README.md:557~562` 与设计文档 `J.12` 的覆盖清单只到周期识别。
8. **设计文档 14.1 页面清单未体现统计页新增分析区块**（统计行在 1125 行，仍写「月度收支卡片、分类占比饼图…来源统计」）。
9. **前端联调用例数量描述过期**
   `README.md:551` 与设计文档 `J.12`（2784 行）写「38 个联调用例」，实际为 **47 个**（新增异常模块 9 个）。

### P2 — 只记录、不修改

10. `BIG_EXPENSE` 旧描述在 md 中已 **0 命中**，无需删除；仅在附录 K 记录迁移前后差异即可。
11. `BillMapper#selectRecurringCandidates` 的注释与执行计划不一致（Stage 4-B 已记录为 P2 文档项），本次不重复处理。
12. 本次新接口的 `LARGE_TRANSACTION` 基线取「目标月之前 90 天同分类中位数」，与 J.11 记录的 2000 行取数上限共用同一保护策略，附录 K 需沿用同一说明口径。

### 无问题的部分（扫描确认）

- 全项目 md 中**不存在** `BIG_EXPENSE`、`bigExpense` 残留描述；
- 全项目 md 中**不存在**把 `LARGE_TRANSACTION` 误写成「全局平均大额消费」的旧口径；
- `frontend/README.md` 只讲运行/构建/品牌资源，不含智能模块清单，**无需改动**。

---

## 需要修改的文件

| 文件 | 修改类型 | 目的 |
| --- | --- | --- |
| `README.md` | 增量修改 | 新增「10. 消费异常提醒」功能章节；接口表补 anomalies 行；测试结果更新为 255 / 201 与 47 个联调用例；开发阶段表补 Stage 4-C 行 |
| `docs/项目设计文档-v1.0.md` | 增量修改 | 新增「附录 K：Stage 4-C 智能消费异常检测」；附录 D 变更记录补一行；14.1 页面清单与 J.9 顺序说明按同一口径补充 |
| `docs/Stage4C-Doc-Review.md` | 新建（本文件） | 第一阶段审查结论 |
| `docs/Stage4C-Documentation-Verification.md` | 新建（第三阶段） | 文档同步完成报告 |

---

## 不修改的文件

### 代码与数据（本阶段绝对禁止）

- 所有 `*.java`（含 `SpendingAnomalyService`、`InsightsController`、`BillMapper`、DTO）
- 所有 `*.dart`（含 `spending_anomaly.dart`、`anomaly_card.dart`、`statistics_page.dart`）
- 所有测试代码（后端 `SpendingAnomalyServiceTest` 等 255 个用例、前端 201 个用例）
- `sql/schema.sql` 与任何 SQL；数据库结构（`user` / `bill` / `budget` / `import_batch` 四张表保持不变）
- `application.yml`、`pubspec.yaml`、`api_config.dart` 等配置

### 历史文档（属于阶段快照，不应回改）

| 文件 | 原因 |
| --- | --- |
| `docs/Stage4-B-智能周期性账单识别设计评审.md` | Stage 4-B 的设计评审快照 |
| `docs/Stage6-Audit-Report.md` | Stage 6 历史审计报告 |
| `docs/Stage6-Final-Acceptance-Report.md` | Stage 6 历史验收报告 |
| 设计文档附录 E~J 中的历史测试数字（108 / 113 / 125 / 153 / 175 / 213 与 44 / 51 / 70 / 87 / 122 / 160） | 每份附录记录「该阶段当时的测试结果」，属于时间点快照，改掉反而失真；只需在附录 K 写当前值 |
| `frontend/README.md` | 内容与品牌/运行相关，无 Stage 4-C 信息需要同步 |

---

## 修改计划

### 1. `README.md`

| # | 位置 | 计划 |
| --- | --- | --- |
| 1.1 | 第 240 行前（`## 三、技术栈` 之前） | 新增 `### 10. 消费异常提醒`：功能定位、三类异常（`CATEGORY_SPIKE` / `LARGE_TRANSACTION` / `FREQUENCY_SPIKE`）的规则与阈值、严重度 HIGH/MEDIUM、四种状态、最多 5 条、只读分析 |
| 1.2 | 506~512 行接口表 | 追加一行 `GET /api/insights/anomalies?month=2026-09`，注明「最近 12 个月、不接受 `userId`、`month` 必填」 |
| 1.3 | 518~595 行测试结果 | 后端 213 → **255**；前端 160 → **201**；追加 Stage 4-C 覆盖说明；联调用例 38 → **47**；补异常模块的联调命令 |
| 1.4 | 736 行开发阶段表 | 追加 `\| Stage 4-C \| 智能消费异常检测（分类上涨 / 单笔异常 / 频次异常，独立 Service + 最多 5 条）\| 已完成 \|` |
| 1.5 | 594 行「真实联调」段末 | 追加 Stage 4-C 的真实数据核对结论（三类异常、四种状态、401/400、`userId` 注入无效） |

### 2. `docs/项目设计文档-v1.0.md`

| # | 位置 | 计划 |
| --- | --- | --- |
| 2.1 | 文档末尾（2814 行后） | 新增 `## 附录 K：Stage 4-C 智能消费异常检测`，含：功能定位、设计原则、数据来源、算法设计、三类异常规则、严重度模型、状态模型、API 设计、前端展示设计、数据库影响、性能分析、测试结果、风险与限制 |
| 2.2 | 附录 D 变更记录表（末行附录 J 在 2083 行） | 追加 `\| 附录 K \| 2026-09-17 \| Stage 4-C：智能消费异常检测（同分类基线、三类异常、最多 5 条、最近 12 个月）\|` |
| 2.3 | 14.1 页面清单（统计行在 1125 行） | 在「统计」行内容中补「消费异常提醒区块」，标注为 Stage 4-C 增量 |
| 2.4 | J.9（2721 行） | 追加一句说明：Stage 4-C 之后统计页区块顺序为 预算预测 → 周期支出 → 消费异常 → 消费洞察 → 分类 → 来源 → 趋势（不改动原文，只在附录 K 中记录最新顺序） |

### 3. 一致性验证（第三阶段）

- 功能一致性：逐条比对文档描述与 `SpendingAnomalyService` 常量值（1.5 / 2.5 / 3 / 5 / 90 天 / ≥5 样本 / ≥100 / 最多 5 条 / 12 个月）
- API 一致性：路径、参数、响应字段（12 个）、四个 status 与 `AnomaliesResponse` / `AnomalyItem` 完全对齐
- 架构一致性：`InsightsController` 分派 `monthly()` 与 `anomalies()`、`SpendingAnomalyService` 三方法的说明齐备
- 测试一致性：文档数字与实测结果逐一对齐（255 / 201 / 47 / analyze PASS / web PASS / apk PASS）
- 产出 `docs/Stage4C-Documentation-Verification.md`

### 4. 本阶段不做的事

- 不修复审查中发现的任何代码问题（只记录）
- 不改历史附录与历史报告中的测试数字
- 不进入 Stage 4-D，不同步 Stage 4-D 相关文档

---

## 审查结论

文档与代码的差距集中在**同一个方向**：Stage 4-C 的消费异常检测完全没有进入文档。
代码侧（接口、服务、阈值、前端区块）已经稳定并通过验证，因此本次同步是**纯补充**，
不需要删除任何旧描述（`BIG_EXPENSE` 已不存在），也不存在需要先修代码才能写文档的阻塞项。

**请确认后再执行第二阶段（文档同步）。**
