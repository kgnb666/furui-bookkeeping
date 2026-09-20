# Stage 6 审计报告（Stage6-Audit-Report）

| 项目 | 大学生个人记账系统（Campus Ledger） |
| --- | --- |
| 审计阶段 | Stage 6 - Step 1（只审计，不改代码） |
| 审计日期 | 2026-09-15 |
| 审计范围 | backend（53 个源文件）、frontend（39 个 lib 文件 + 9 个测试文件）、docs、sql、README |
| 审计方式 | 静态代码扫描（结构/重复/死代码/硬编码/安全）+ 已有测试与构建结果复核 |
| 审计结论 | 无严重问题；4 项高优先级（2 项纯文档、1 项重复代码、1 项中文提示混英文）；11 项优化建议 |

---

## 一、严重问题（P0）

**无。**

系统可以正常构建、启动、运行：后端 `mvn clean test` 103/103 通过、`mvn clean package` 成功；前端 `flutter analyze` 无问题、`flutter test` 44/44 通过、`flutter build web` 成功。没有发现会导致运行失败、数据损坏或无法答辩的缺陷。

---

## 二、高优先级问题（P1，建议在答辩前修复）

### P1-1 设计文档接口表与代码路径不一致

- **位置**：`docs/项目设计文档-v1.0.md` 第 15.1 节接口总览（第 1209-1220 行）
- **现象**：

| 文档表格写的 | 代码实际实现的 |
| --- | --- |
| `GET /api/statistics/month` | `GET /api/statistics/monthly` |
| `GET /api/statistics/trend` | `GET /api/statistics/daily` |
| `GET /api/budget`、`POST /api/budget`、`PUT /api/budget/{id}` | `GET /api/budgets`、`POST /api/budgets`、`PUT /api/budgets/{id}` |
| （表格中缺失） | `DELETE /api/budgets/{id}` |

- **影响**：老师按文档逐个点接口会得到 404；文档下方虽有一句"实现说明"注明最终路径，但表格本身仍是旧路径，容易被当成文档没更新。
- **建议**：只改表格里的 4 行路径 + 补 1 行 DELETE（纯文档，不动代码）。

### P1-2 设计文档示例 JSON 的 `type` 与实现不符

- **位置**：设计文档 15.2.3 / 15.3 / 18 章的示例（第 1296、1339、1384、1426、1435、1448、1457 行等）
- **现象**：示例写的是 `"type": "EXPENSE"` 等字符串枚举；代码实际返回 `"type": 1` 加 `"typeName": "支出"`（Stage 2 定稿）。
- **影响**：与 P1-1 同类，属于"文档示例未同步"，答辩时若对照示例调接口会困惑。
- **建议**：示例改成数字，或在示例上方加一行说明"实际返回数字 1/2/3，示例用可读写法表示含义"。

### P1-3 金额与日期校验规则在后端重复三处

- **位置**：
  - `service/BillService.java:29,139-155`（手工记账）
  - `service/BillImportService.java:48,273-288,320-324`（导入确认 + 预览预检，**同一个类里写了两遍**）
  - `service/BudgetService.java:34,165-172`（预算）
- **现象**：`MAX_AMOUNT = 99999999.99` 常量声明 3 次；"金额 > 0 / 最多两位小数 / 不超过上限 / 日期不能晚于今天"这四类规则在 5 个位置各写一遍。
- **影响**：将来只改一处就会出现"手工记账能存、导入被拒"这类不一致——Stage 5 修复的 Bug（预览说可导入、确认才失败）正是这种重复导致的。
- **建议**：抽一个 `common/BillRules`（与已有 `Category` 同级的工具类）提供静态校验方法，三处调用；不新增分层、不引入框架，改完重跑 103 + 44 测试。

### P1-4 参数缺失时的 400 提示混入英文

- **位置**：`common/GlobalExceptionHandler.java:59`
- **现象**：`"请求参数不完整：" + e.getMessage()`，而 `e.getMessage()` 是 Spring 的英文信息，例如缺 `month` 参数时会返回：
  `请求参数不完整：Required request parameter 'month' for method parameter type String is not present`
- **影响**：与"用户界面中文统一"的要求不一致（前端会原样显示这句话）。
- **建议**：改成固定中文提示（如"请求参数不完整，请检查后重试"），把 `e.getMessage()` 只写进日志。

### P1-5 设计文档页面清单与实际实现不符

- **位置**：设计文档 14.1 节（第 1115-1130 行）
- **现象**：
  1. 表格里写了"账单列表：左右滑动删除"——实际删除入口在账单详情页/编辑页（含确认弹窗），列表没有滑动删除；
  2. 首页写了"今日花费"——实际首页展示"本月收入/支出/结余 + 最近账单 + 快捷入口"；
  3. "路由"列写的是 `/login`、`/home` 这类路径，但 Flutter 端没有命名路由表，实际用 `Navigator.push(MaterialPageRoute(...))` 直接跳转。
- **影响**：属于设计初稿与最终实现的差异，老师按文档点功能可能追问。
- **建议**：把该表格的"路由"列改为"页面文件"或注明"示意路径"，并把两处功能描述改成实际实现。

---

## 三、优化建议（P2，可不改）

| # | 问题 | 位置 | 说明 |
| --- | --- | --- | --- |
| 1 | 死代码：`Months.start()` / `Months.end()` 零引用 | `common/Months.java` | 实际只用了 `Months.parse()`，删掉即可 |
| 2 | "错误 + 重试" UI 在 6 个页面重复 | home / bill_list / bill_detail / statistics / budget / import_history | 可抽一个 `ErrorRetry` widget，减少重复 |
| 3 | 刷新没有防重复触发 | `home_page`、`statistics_page`、`import_history_page` | 刷新按钮与下拉刷新没有 guard，连点会产生并发请求（无副作用，只是多一次查询） |
| 4 | 加载失败只有文字、没有"重试"按钮 | `profile_page.dart` | 有下拉刷新可恢复，但不如按钮直观 |
| 5 | 魔法数字 | `bill_list_page.dart:409,425`（FAB 留白 88）、`BillImportService.java:258`（`LIMIT 50`）、`BillService.java:90`（页大小上限 100）、图表尺寸 38/58/64/200 | 部分可提取为常量；UI 尺寸类可保持 |
| 6 | 分类集合前后端各一份 | `frontend/lib/utils/categories.dart` ↔ `backend/.../common/Category.java` | 需要人工同步；建议在 README 注明"改分类要同时改两处" |
| 7 | 上传大小仅由 multipart 配置限制 | `application.yml:20` | Service 未二次校验；xlsx 解压后大小也未额外限制（POI 有内置防护） |
| 8 | 登录页硬编码演示账号密码 | `login_page.dart:147` | 答辩方便；如不想暴露可删 |
| 9 | JWT 存在 localStorage（Web），无主动失效 | `api_client.dart` / `auth_service.dart` | 无状态 JWT 的固有取舍，改密后旧 token 7 天内仍有效 |
| 10 | 超时常量写死在 ApiClient | `api_client.dart`（30s / 120s） | 可提到常量区 |
| 11 | 阶段命名口径不一致 | README 与设计文档写 Stage 0-7，本次任务叫 Stage 5/6 | 建议统一口径，避免答辩时对不上 |

---

## 四、可以保持现状（已检查、确认无需修改）

### 1. 代码结构与规模

| 检查项 | 结论 |
| --- | --- |
| 后端包结构 | 合理：`controller`(6) / `service`(6) / `mapper`(4) / `entity`(4) / `dto`(26) / `importer`(6) / `common`(7) / `auth`(3) / `config`(2) |
| Controller 是否过重 | 不需要：34~65 行，只做参数接收、`CurrentUser.get()`、调用 Service、包装统一响应，无业务代码 |
| Service 职责 | 清晰：`BillService`(165) 手工账单、`BillImportService`(423) 导入、`StatisticsService`(154) 统计、`BudgetService`(177) 预算、`UserService`(98) 用户、`CategoryMatcher`(106) 分类 |
| Mapper SQL | 规范：全部 `@Select` 注解 + `#{}` 参数，无 XML 碎片；查询条件都带 `user_id` |
| 前端结构 | 清晰：`pages`(16) / `services`(4) / `models`(5) / `widgets`(4) / `utils`(3) / `config`(1) |
| 未使用文件 | 无：39 个 lib 文件全部被引用（含被测试引用） |
| 测试残留 / 临时文件 | 无：源码目录内没有 png/log/tmp/bak/har 等临时文件，也没有 `test_`、`debug_` 之类的临时类 |

### 2. 安全

| 检查项 | 结论 | 证据 |
| --- | --- | --- |
| 用户身份来源 | 只来自 JWT | Controller 中 19 处 `CurrentUser.get()`；所有请求 DTO 都没有 `userId` 字段；实测 URL/请求体伪造 userId 被忽略 |
| JWT 校验 | 完整 | `JwtUtil` HS256 签名 + 7 天有效期；`AuthInterceptor` 校验 `Bearer` 前缀与签名；无效/过期/错误签名一律 401（已用自制过期 token 实测） |
| 密码存储 | BCrypt | `spring-security-crypto` 的 `BCryptPasswordEncoder`；数据库实测 `$2a$10$...`（60 字符），无明文，日志不打印密码 |
| SQL 注入 | 无风险 | 无 `${}` 拼接（扫描命中的都是 Spring `@Value` 占位符），全部 `#{}`；唯一原生片段 `.last("LIMIT 50")` 是常量 |
| 越权访问 | 已阻断 | 所有查询带 `user_id`；访问他人资源统一 404（不是 403/500），实测通过 |
| 文件上传 | 受限 | 5MB 上限（超限返回 413 中文提示）、仅 `.csv`/`.xlsx`、文件名只取 basename 并截断 128 字符、文件只在内存解析不落盘 |
| 敏感信息泄露 | 无 | 500 只返回"服务器开小差了"，登录失败统一"用户名或密码错误"（不暴露账号是否存在）；前端不含任何数据库连接信息；配置中的库口令与 JWT 密钥支持环境变量覆盖 |

### 3. 数据一致性

| 检查项 | 结论 |
| --- | --- |
| 金额类型 | 后端**完全没有** `double`/`float`，20 个文件使用 `BigDecimal`；数据库 `DECIMAL(10,2)` |
| 前端金额计算 | `utils/money.dart` 用整数分（`toCents`/`fromCents`），`double` 只用于 `percentage`/`usageRate` 等比例展示与图表坐标 |
| 日期与时区 | 后端 `LocalDate` + MySQL `DATE`；数据源与 Jackson 都固定 `Asia/Shanghai`；接口日期统一 `yyyy-MM-dd`，时间戳统一 `yyyy-MM-dd HH:mm:ss` |
| 枚举一致性 | `type`：1 支出 / 2 收入 / 3 不计收支（前后端一致）；`source`：MANUAL / WECHAT / ALIPAY（前端直接用后端返回的 `sourceName` 中文名展示） |
| 错误码 | 统一：成功 `code=0`，失败 `code` 与 HTTP 状态一致（400/401/404/409/413/500） |

### 4. 前端体验

| 页面 | loading | 空状态 | 错误提示 | 防重复点击 |
| --- | --- | --- | --- | --- |
| 登录 / 注册 | 有 | - | 有（内联） | 有 |
| 首页 | 有 | 有 | 有 + 重试 | 刷新无 guard（P2-3） |
| 账单列表 | 有 | 有 | 有 + 重试 | 有 |
| 记账 / 编辑 | 有 | - | 有（内联） | 有 |
| 账单详情 | 有 | - | 有 + 重试 | 有 |
| 导入 | 有（遮罩） | - | 有（内联） | 有 |
| 导入预览 | 有 | 有 | 有（SnackBar） | 有 |
| 导入结果 | -（静态页） | - | - | - |
| 统计 | 有 | 有 | 有 + 重试 | 刷新无 guard（P2-3） |
| 预算 | 有 | 有 | 有 + 重试 | 有 |
| 我的 / 资料 / 改密 | 有 | - | 有（内联） | 有 |

其他已确认的体验项：

- **危险操作确认**：删除账单（详情页 + 编辑页）、删除预算、退出登录都有确认弹窗，共 4 处。
- **token 过期**：`ApiClient` 收到 401 → 回调 `main.dart` 的 `_backToLogin` → 清除本地 token 并 `pushAndRemoveUntil` 回登录页。
- **网络异常**：统一提示"无法连接服务器，请确认后端已启动"，页面显示重试按钮，不出现白屏或异常堆栈。
- **刷新后保持登录**：token 存 shared_preferences，未登录直接进登录页，退出后刷新仍在登录页（已实测）。

### 5. 配置与依赖

| 检查项 | 结论 |
| --- | --- |
| 数据库配置 | 全部走环境变量并保留本地默认值：`DB_HOST` / `DB_PORT` / `DB_NAME` / `DB_USERNAME` / `DB_PASSWORD`（Stage 6 已将 `DB_USER` 统一为 `DB_USERNAME`） |
| JWT 密钥 | `JWT_SECRET` 环境变量优先，保留开发默认值 |
| 前端接口地址 | `api_config.dart` 三套环境（local / android 模拟器 / 局域网）用 `--dart-define=API_ENV=xxx` 切换 |
| 依赖 | 后端 13 个（无冗余、无 Redis/MQ/ES/Docker）；前端 6 个（http、shared_preferences、file_picker、intl、fl_chart、cupertino_icons），无 dio/retrofit/provider/riverpod/bloc |

---

## 五、修复建议汇总（供 Step 2 使用）

| 优先级 | 项目 | 是否影响答辩 | 预计工作量 |
| --- | --- | --- | --- |
| P1-1 | 设计文档接口表路径同步 | 会（老师照文档点接口 404） | 5 分钟，纯文档 |
| P1-2 | 设计文档示例 JSON 的 type 同步 | 会（轻微） | 5 分钟，纯文档 |
| P1-5 | 设计文档页面清单与实现同步 | 会（轻微） | 5 分钟，纯文档 |
| P1-4 | 400 参数提示改为纯中文 | 轻微 | 5 分钟，改 1 行 |
| P1-3 | 抽出 `BillRules` 收敛重复校验 | 不会（但提升质量） | 约 30 分钟含回归测试 |
| P2-1 | 删除 `Months.start/end` 死代码 | 不会 | 2 分钟 |
| P2-4 | 我的页加载失败加重试按钮 | 不会 | 5 分钟 |
| P2-6 | README 注明分类需前后端同步 | 不会 | 2 分钟，纯文档 |

**不建议在答辩前改动**：P2-2（抽公共组件）、P2-3（刷新 guard）、以及任何拆分长文件的重构——收益低于改动风险。

---

## 六、审计说明

1. 本次审计**未修改任何代码与文档**，只做静态扫描与结果复核。
2. 报告中的行号来自当前代码，若后续修改代码，行号可能变化。
3. 所有结论均可在报告中给出的文件位置复核，未使用推测性描述。
