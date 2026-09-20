# Stage 6 最终验收报告（Stage6-Final-Acceptance-Report）

| 项目 | 大学生个人记账系统（Campus Ledger） |
| --- | --- |
| 阶段 | Stage 6：缺陷修复与交付整理 |
| 完成日期 | 2026-09-15 |
| 交付状态 | 可交付（毕业设计 / 答辩展示） |
| 验收平台 | Chrome（Flutter Web）+ Spring Boot 8080 + MySQL 8.0 |

---

## 一、修改列表

### 1.1 缺陷修复（Step 2）

| # | 文件 | 修改原因 | 修改内容 | 影响范围 |
| --- | --- | --- | --- | --- |
| 1 | `backend/src/main/java/com/campus/ledger/common/BillRules.java`（新增） | 金额/日期规则在 3 个 Service 里各写一遍，易出现"手工记账能存、导入被拒"的不一致 | 新增统一规则类：`checkAmount` / `checkBillDate`（抛业务异常）与 `amountError` / `billDateError`（返回原因，供导入预览使用），两者共用同一套判断 | 手工记账、导入预览、导入确认、预算四处校验 |
| 2 | `service/BillService.java` | 同上 | 删除本地 `MAX_AMOUNT` 与 4 段重复判断，改调 `BillRules` | 账单新增/修改校验（行为与提示文案不变） |
| 3 | `service/BillImportService.java` | 同上，且该类内部 `toBill()` 与 `checkImportable()` 也重复了一遍 | 两处都改调 `BillRules`，删除本地 `MAX_AMOUNT` | 导入预览、确认导入 |
| 4 | `service/BudgetService.java` | 同上 | `validateAmount` 改调 `BillRules.checkAmount(amount, "预算金额")`，保留"预算金额…"提示文案 | 预算新增/修改 |
| 5 | `common/Months.java` | 死代码 | 删除零引用的 `start()` / `end()` | 无（编译期即可确认无引用） |
| 6 | `common/GlobalExceptionHandler.java` | 参数缺失时提示拼接了 Spring 英文异常，与"界面中文"要求不符；另外 `?page=abc` 会落到通用异常返回 500 | ① 参数不完整改为固定中文提示，英文细节写日志；② 新增 `MethodArgumentTypeMismatchException` → 400「参数格式不正确：page」；③ 新增 `HttpMessageNotReadableException` → 400「请求内容格式不正确」 | 所有接口的错误响应 |
| 7 | `backend/src/test/java/com/campus/ledger/auth/JwtUtilTest.java` | **测试本身不稳定**：篡改用例改的是 token 最后两个字符，而 base64url 末尾带填充位，改动可能不影响解码结果，导致极小概率"篡改后仍通过校验"，答辩现场可能随机失败 | 改为修改签名段中前部的字符（一定落在有效位） | 后端测试稳定性 |
| 8 | `backend/src/test/java/com/campus/ledger/common/BillRulesTest.java`（新增） | 锁住统一后的规则 | 5 个用例：金额标准化、非法金额提示、预算文案、日期规则、抛异常版本与返回原因版本判断一致 | 后端测试（103 → 108） |
| 9 | `backend/src/main/resources/application.yml` | 环境变量命名与交付文档不一致 | `DB_USER` → `DB_USERNAME`（其余不变，仍保留本地默认值） | 数据库账号配置（可用环境变量覆盖） |

### 1.2 文档一致性修复（Step 2 / Step 5）

| # | 文件 | 修改原因 | 修改内容 |
| --- | --- | --- | --- |
| 10 | `docs/项目设计文档-v1.0.md` | 接口表路径与代码不一致（老师照文档点接口会 404） | §15.1 统计模块改为 `/statistics/monthly`、`/statistics/daily`；预算模块改为 `/api/budgets` 并补 `DELETE /api/budgets/{id}` |
| 11 | 同上 | 示例 JSON 用字符串 `"EXPENSE"`，代码返回数字 | 5 处示例改为 `"type": 1` + `"typeName": "支出"`；查询示例 `type=EXPENSE` → `type=1`；示例路径同步为实际路径 |
| 12 | 同上 | §14.1 页面清单与实现不符 | "路由"列改为"页面文件（示意）"；首页描述去掉"今日花费"、改为"本月收支结余（来自统计接口）"；账单列表去掉"左右滑动删除"，改为"点击进入详情/编辑页删除" |
| 13 | 同上 | 交付时需要"最终实现"汇总 | 新增**附录 E：最终实现总结**（最终功能清单、数据库实现、接口清单、架构说明、测试结果、与设计初稿的差异说明） |
| 14 | `docs/Stage6-Audit-Report.md` | 环境变量改名 | 同步 `DB_USERNAME` 说明 |

### 1.3 前端体验优化（Step 3）

| # | 文件 | 修改原因 | 修改内容 |
| --- | --- | --- | --- |
| 15 | `frontend/lib/pages/bill_edit_page.dart` | 保存/删除后没有成功反馈 | 保存后提示"记账成功 / 账单已保存"，删除后提示"账单已删除" |
| 16 | `frontend/lib/pages/bill_detail_page.dart` | 删除后没有成功反馈 | 删除后提示"账单已删除" |
| 17 | `frontend/lib/pages/budget_page.dart` | 预算保存/删除后没有成功反馈 | 提示"预算已保存" / "预算已删除" |
| 18 | `frontend/lib/pages/profile_page.dart` | 资料加载失败只有文字提示，没有重试入口 | 错误提示旁增加"重试"按钮 |

> 样式一致性已复核：所有页面用 `EdgeInsets.all(16)` 或 `fromLTRB(16, …)` 的内边距、卡片统一 `margin: EdgeInsets.zero` + `SizedBox` 间距、区块标题统一 `titleMedium`，空状态 / 加载 / 错误 / 删除确认已全覆盖，因此本阶段没有做样式重构。

### 1.4 交付文档与截图（Step 6 / Step 7）

| # | 文件 | 内容 |
| --- | --- | --- |
| 19 | `README.md` | 全面重写：项目介绍（含账单导入合规说明）、系统功能、技术栈、系统架构、项目截图、快速开始（环境要求/数据库初始化/后端启动/前端启动/演示账号）、接口说明、测试与构建结果、部署说明（含 Nginx 示例）、常见问题、目录结构、开发阶段 |
| 20 | `docs/screenshots/*.png`（9 张） | 登录、首页、账单列表、记账、导入、导入预览、统计、预算、我的 |

### 1.5 修复过程中自己发现并修复的问题

| 问题 | 说明 |
| --- | --- |
| **YAML 缩进被改坏** | Step 5 改 `application.yml` 时 `username` 一行多缩进了两格，导致 Spring 启动报 `mapping values are not allowed here`。**单元测试不加载 Spring 上下文，因此没有拦住**，是在 Step 8 启动真实环境时发现的；已把缩进改回 4 空格并重新打包验证。这条也说明当前缺少"启动冒烟测试"，已记入遗留问题。 |

---

## 二、测试结果

### 2.1 后端（`mvn clean test`）

```
Tests run: 108, Failures: 0, Errors: 0, Skipped: 0
BUILD SUCCESS
```

较审计前的 103 个增加 5 个（`BillRulesTest`），**没有删除或跳过任何已有用例**；并且连续执行 3 次结果一致（用于确认 JWT 篡改用例已不再偶发失败）。

### 2.2 前端（`flutter test`）

```
00:03 +44: All tests passed!
```

后端处于运行状态，因此 8 个真实联调用例全部实际执行（不是 skipped）。

### 2.3 真实环境全流程验证

在"MySQL + Spring Boot + Flutter Web"真实环境下用一个全新账号跑通（19 项断言全部 PASS）：

| 分组 | 验证内容 | 结果 |
| --- | --- | --- |
| 认证 | 注册、登录 | PASS |
| 账单 | 新增支出 / 收入 / 不计收支、列表、按类型筛选、关键词搜索、修改、删除、删除后查询 404 | PASS |
| 导入 | 微信 preview + confirm、支付宝 preview + confirm、重复导入检测（新增 0 / 重复 12）、导入历史 | PASS |
| 统计 | 月度 / 分类 / 来源 / 每日四个接口；**来源合计 230.50 == 分类合计 == 月支出** | PASS |
| 预算 | 设置总预算 500、设置餐饮预算 5.00 制造超支（显示"已超支"）、修改预算、删除预算 | PASS |
| 隔离 | B 读 A 的账单 → 404、B 改 A 的预算 → 404、B 自己的账单 0 条、来源统计 0 项 | PASS |
| 异常 | `?page=abc` → 400、缺 `month` → 400、非法 JSON → 400、金额 0 → 400、未来日期 → 400、非法 token → 401、无 token → 401 | PASS |

异常提示文案全部为中文（本次修复项）：

```text
参数格式不正确：page
请求参数不完整，请检查后重试
请求内容格式不正确
金额必须大于 0
日期不能晚于今天
```

---

## 三、构建结果

| 命令 | 结果 |
| --- | --- |
| `mvn clean test` | Tests run: 108, Failures: 0, Errors: 0, Skipped: 0，BUILD SUCCESS |
| `mvn clean package` | BUILD SUCCESS，产物 `backend/target/campus-ledger-backend-1.0.0.jar`（45.1 MB） |
| `flutter pub get` | Got dependencies! |
| `flutter analyze` | **No issues found!** |
| `flutter test` | 44/44 通过 |
| `flutter build web` | 构建成功，产物 `frontend/build/web` |

---

## 四、运行截图列表

截图均来自真实运行页面（Flutter Web 产物 + 真实后端数据），已归档到 `docs/screenshots/`：

| 文件 | 页面 | 说明 |
| --- | --- | --- |
| `01-login.png` | 登录页 | 未登录状态 |
| `02-home.png` | 首页 | 本月收支结余、最近账单、快捷入口 |
| `03-bill-list.png` | 账单列表 | 筛选条件、来源标记、收支配色 |
| `04-bill-edit.png` | 记一笔 / 编辑账单 | 类型、金额、分类、日期、商户、备注 |
| `05-import.png` | 导入账单 | 选择来源与文件、导出指引 |
| `06-import-preview.png` | 导入预览 | 四类数量统计、重复记录默认不勾选 |
| `07-statistics.png` | 统计页 | 概览 + 预算入口 + 分类环形图 + **支付来源** + 每日趋势 |
| `08-budget.png` | 预算页 | 总预算与分类预算执行情况（含"已超支 ¥22.50"） |
| `09-profile.png` | 我的 | 资料、修改密码、导入记录、关于、退出登录 |

---

## 五、剩余已知问题（均为 P2，不影响交付与答辩）

| # | 问题 | 说明与建议 |
| --- | --- | --- |
| 1 | 后端缺少"启动冒烟测试" | 现有 108 个测试都是单元测试（Mockito），不加载 Spring 上下文，因此配置类错误（如本次的 YAML 缩进）只能靠启动发现。建议后续加 1 个 `@SpringBootTest` 冒烟用例（启动上下文 + 调 1 个接口） |
| 2 | 前端"错误 + 重试"UI 在 6 个页面重复 | 可抽 `ErrorRetry` 组件；属重构，答辩前不建议动 |
| 3 | 首页 / 统计 / 导入记录的刷新没有防连点 | 连续点击会产生并发查询（无副作用），可选优化 |
| 4 | 少量魔法数字 | FAB 留白 `88`、导入历史 `LIMIT 50`、分页上限 `100`；可提取为常量 |
| 5 | 分类集合前后端各一份 | `utils/categories.dart` ↔ `common/Category.java`，改动需同步（已写入 README 常见问题） |
| 6 | 上传大小只由 multipart 配置限制 | Service 未二次校验；xlsx 解压后大小未额外限制（POI 有内置防护），5MB 限制下风险很低 |
| 7 | 登录页显示演示账号密码 | 便于答辩演示；如不想暴露可删掉该提示 |
| 8 | JWT 无主动失效机制 | 改密后旧 token 在 7 天内仍有效（无状态 JWT 的固有取舍，前端已在改密后清本地 token） |
| 9 | 设计文档 §21 阶段划分仍是 Stage 0-7 的计划 | 实际执行到 Stage 6（含 Stage 4.5 补丁），README 的阶段表已按实际口径更新；设计文档保留为原始计划 |

---

## 六、交付状态小结

| 验收项 | 状态 |
| --- | --- |
| 功能闭环（记账 → 导入 → 统计 → 预算 → 个人中心） | 完成 |
| 用户数据隔离（账单 / 预算 / 导入历史 / 统计） | 完成，越权返回 404 |
| 密码与鉴权安全（BCrypt + JWT） | 完成 |
| 金额精度（BigDecimal / DECIMAL(10,2)，无 double） | 完成 |
| 导入能力（微信 UTF-8、支付宝 GBK、xlsx、去重、异常文件提示） | 完成 |
| 统计口径统一（不计收支完全排除） | 完成，接口与数据库、页面三方一致 |
| 后端测试 / 前端测试 / 静态检查 / 构建 | 108 / 44 / 0 issue / 全部成功 |
| 文档（README、设计文档、审计报告、验收报告、9 张截图） | 完成 |
| 数据库结构 | 未修改（与 Stage 0 设计一致） |

**结论：项目达到毕业设计交付级别与答辩展示级别。** 剩余问题均为可选的工程优化项，不影响功能、测试与演示。
