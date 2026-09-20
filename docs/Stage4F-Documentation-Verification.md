# Stage 4-F Documentation Sync Report

> Stage 4-F Step 4（文档同步与一致性验证）的产出。
> 本阶段**只修改 Markdown 文档**：没有改动任何 Java / Dart / SQL / 配置 / 测试代码，
> 没有修复历史 WARNING，没有改动任何历史阶段设计与报告快照。
> 验证时间：2026-09-19

---

## 1. 修改文件列表

| 文件 | 类型 | 变更 |
| --- | --- | --- |
| `README.md` | 修改 | 新增「13. 消费对象分析」功能章节（含 4-A~4-F 对照表）；统计页顺序补入新块（2 处）；智能能力接口表新增 merchants 行 + 「消费对象接口细节」小节；后端测试数字 326 → **367**；前端 290 → **339**、离线 225/65 → **264/75**；后端与前端覆盖说明各补一段；新增消费对象联调用例说明；新增 Stage 4-F 真实联调结论；开发阶段表新增 Stage 4-F 行 |
| `docs/项目设计文档-v1.0.md` | 修改 | 文末新增「附录 N：Stage 4-F 消费对象分析」（N.1~N.10）；附录 D 变更记录表新增一行 |
| `docs/Stage4F-Documentation-Verification.md` | 新建 | 本文件 |

---

## 2. 一致性验证链

```text
代码（SpendingMerchantService / InsightsController / 两个 DTO）   OK  未改动
  ↓
API（GET /api/insights/merchants?month=yyyy-MM）                 OK  路径、参数、字段、状态一致
  ↓
测试（后端 367 / 前端 339 / 离线 264+75）                        OK  均为实测数字
  ↓
README（### 13 消费对象分析）                                     OK  功能、接口、顺序、测试数字、阶段表
  ↓
设计文档附录 N（N.1~N.10）                                        OK  与实现逐项对应
```

---

## 3. 逐项检查结果

### 3.1 API 存在

| 检查 | 结果 |
| --- | --- |
| 代码 | `InsightsController` 第 99 行 `@GetMapping("/merchants")`（类级 `/api/insights`）⇒ `/api/insights/merchants` |
| README | 接口表新增一行 + 「消费对象接口细节」小节（共 3 处出现） |
| 设计文档 | 附录 N.6 |
| 结论 | 一致 |

### 3.2 DTO 与字段一致

| DTO | 字段数 | README | 附录 N |
| --- | --- | --- | --- |
| `SpendingMerchantResponse` | **13**（实测 `private final` 计数） | 已列出 | 已列出 |
| `MerchantSpendingItem` | **4** | 已列出 | 已列出 |

前端 `spending_merchant.dart` 与后端字段一一对应，未增加后端不存在的字段。

### 3.3 状态与阈值一致

| 项 | 代码（`SpendingMerchantService`） | 文档 |
| --- | --- | --- |
| 四种状态 | 第 65~68 行四个常量 | README 状态表 4 行 + N.6 状态表 4 行 |
| 消费天数门槛 | `MIN_COVERED_DAYS = 3`（第 48 行） | 两处均写「≥3 天」 |
| 对象数门槛 | `MIN_MERCHANT_COUNT = 2`（第 51 行） | 两处均写「≥2 个对象」 |
| 覆盖率门槛 | `MIN_MERCHANT_COVERAGE = 50`（第 54 行） | 两处均写「覆盖率 ≥50%」 |
| 明细上限 | `MAX_DETAIL_ROWS = 2000`（第 57 行） | 两处均写 `LIMIT 2000` |
| 排行上限 | `TOP_MERCHANT_LIMIT = 5`（第 60 行） | 两处均写「最多 5 项」 |
| 集中度口径 | `CONCENTRATION_SIZE = 3`（第 63 行） | 两处均写 Top3 |

### 3.4 算法公式一致

覆盖率 = 有对象的笔数 ÷ 总笔数 ×100；集中度 = Top3 金额 ÷ 总金额 ×100；客单价 = 总金额 ÷ 总笔数。
文档公式与代码实现一致，并与真实接口返回值吻合（1000.00 / 4 / 250.00 / 100.00 / 100.00）。
商户清洗规则（trim → 压缩空格 → 统一小写，**不剥离后缀**）在代码注释、README 与 N.5 三处表述一致。

### 3.5 Flutter 页面顺序一致

```text
代码   statistics_page.dart：分类统计(351) → 来源统计(353) → 消费对象分析(355) → 消费节奏分析(357) → 趋势图(359)
README 同一顺序（2 处顺序块已更新）
附录N  N.7 同一顺序
测试   spending_merchant_test.dart「消费对象区块位于来源统计之后消费节奏之前」按控件类型索引断言
```

首页未接入（README 与 N.7 均写明；`home_page.dart` 无 merchants 引用）。

### 3.6 测试数字一致

见第 4 节。

### 3.7 无代码修改

本阶段被写入的只有 `README.md` 与 `docs/项目设计文档-v1.0.md`（+ 本报告）；
Java 最后修改为 10:41~10:43、Dart 为 11:02~11:09，均早于本阶段。

| 类别 | 本阶段是否变化 |
| --- | --- |
| Java（main / test） | 否 |
| Dart（lib / test） | 否 |
| SQL / schema | 否 |
| 配置（pom.xml / pubspec.yaml / application.yml） | 否 |
| 历史设计快照（Stage4F-Design-Review.md、Stage4E-*、Stage4D-*、Stage4C-*、Stage4B-*、Stage6-*） | 否 |
| 数据库结构 | 否（4 张表 / 13 个索引对象） |

### 3.8 历史附录未被修改

附录 E~M 的历史测试数字逐条复核，全部保持原值（108 / 113 / 125 / 153 / 175 / 213 / 255 / 292 / 326），
本次新增附录 N 记录 **367 / 339**。

---

## 4. 测试数字核对

| 项 | 数字 | 来源 | 文档位置 |
| --- | --- | --- | --- |
| 后端全量 | `Tests run: 367, Failures: 0, Errors: 0, Skipped: 0` | Step 2 `mvn clean test` / `mvn package` | README「八」+ 附录 N.8 |
| 后端新增 | **41**（`SpendingMerchantServiceTest`） | Step 2 | README「Stage 4-F 追加覆盖（41 个用例）」+ N.8 |
| 前端在线 | **339** passed / 0 skipped / 0 failed | Step 3 `flutter test --dart-define=…` | README + N.8 |
| 前端离线 | **264** passed / **75** skipped / 0 failed | Step 3 `flutter test`（后端停止） | README + N.8 |
| 前端新增 | **39**（单元 / Widget）+ **10**（真实联调） | Step 3 | README + N.8 |
| 真实接口联调 | 10/10 PASS | Step 3 | README「真实联调」+ N.8 |
| 构建 | analyze 无问题；web 成功；apk 59.0 MB | Step 3 | README + N.8 |
| 性能 | 12000 条账单：SQL=1、median 22.2 ms、avg 25.1 ms、cold 152.2 ms | Step 2 | 附录 N.9 |

README 中已不存在过期数字（`Tests run: 326`、`290 个用例`、`225 passed` 均已被替换）。

---

## 5. 已知限制（如实记录）

1. **`LIMIT 2000` 截断**：单月支出超过 2000 笔时只分析最近 2000 笔（Step 2 压测已实测触发：12000 笔 → `totalCount=2000`），前端目前不提示；
2. **展示名取"第一条记录"**的写法（分组键统一小写）；
3. **刻意不做商户合并**：`星巴克` 与 `星巴克店` 是两个对象；
4. **覆盖率是笔数口径**，与金额口径的未填写占比不同；
5. **统计页已达 12 个区块 / 11 个请求**，页面较长；
6. **无浏览器可视化确认**（执行环境限制）；
7. **历史 WARNING 未修复**（按约束）：`BillMapper#sumByCategoryAndMonth` 的索引注释问题仍在附录 K.9；
8. **联调测试会在测试库留下账号**（项目既有行为，本轮创建的 `s4f3*` 已清理）。

---

## 6. 最终 Gate

**PASS** — 文档状态已与真实代码状态一致：

| 维度 | 结果 |
| --- | --- |
| API 存在 | 代码 / README / 附录 N 三处一致 |
| DTO 与字段 | 13 + 4 个字段三处一致 |
| 状态与阈值 | 四个状态与三个门槛值与代码常量逐一对应 |
| 算法公式 | 覆盖率 / 集中度 / 客单价公式与实现及真实返回值吻合 |
| Flutter 顺序 | 代码子节点顺序 = README = 附录 N = 顺序断言 |
| 测试数字 | README 与附录 N 均为实测值（367 / 339 / 264+75） |
| 历史快照 | 附录 E~M 与历史报告零改动 |
| 代码改动 | 本阶段 0 行代码改动 |

**Stage 4-F 全部四步完成**，可继续后续工作项。
