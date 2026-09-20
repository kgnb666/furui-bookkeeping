# 福瑞记账 前端（Flutter）

记下每一笔 · 收获更好的自己

Flutter Web / Android 客户端，通过 HTTP 调用 `backend/` 提供的 Spring Boot 接口。
Dart 包名仍为 `campus_ledger`（技术标识，与品牌名称无关）。

## 环境要求

| 项目 | 版本 |
| --- | --- |
| Flutter | 3.47.x（Dart 3.13） |
| JDK（构建 Android 时用） | 17 |
| Android SDK | API 34 及以上 |

## 运行

```bash
flutter pub get

# Chrome：后端默认 http://localhost:8080/api
flutter run -d chrome

# 指定后端地址（部署或真机调试）
flutter run -d chrome --dart-define=API_BASE_URL=http://192.168.1.10:8080/api
```

接口地址在 `lib/config/api_config.dart` 统一配置，支持 `API_ENV=local|android|lan` 或
直接用 `API_BASE_URL` 覆盖，不需要改代码。

## 构建

```bash
flutter build web --release
flutter build apk --release --dart-define=API_ENV=android
```

> Windows 构建若报 `Building with plugins requires symlink support`，需在「设置 → 隐私和安全性 →
> 开发者选项」中打开开发者模式。这是环境限制，不影响业务代码。

## 测试

```bash
flutter analyze
flutter test
```

`test/` 下分两类：

* 单元与 Widget 测试：不依赖后端，直接运行。
* 联调测试（`api_integration_test.dart` 等）：真实访问 `http://localhost:8080`，
  后端未启动时自动跳过，不影响其余用例。

## 品牌资源

品牌图由 `tool/brand_assets.py` 从设计稿生成 `assets/brand/`，App 图标由
`flutter_launcher_icons` 生成：

```bash
python tool/brand_assets.py      # 生成品牌图与图标源图
dart run flutter_launcher_icons  # 生成 Android / Web / Windows 图标
```

## 目录结构

```text
lib/
  config/     接口地址等配置
  models/     数据模型
  pages/      页面
  services/   接口调用
  utils/      金额、日期、分类、品牌常量
  widgets/    可复用组件
```
