/// 后端接口地址配置。
/// 通过 --dart-define=API_ENV=android 切换环境，避免地址散落在各个页面里。
class ApiConfig {
  ApiConfig._();

  /// Chrome / Windows 直接访问本机后端
  static const String _localUrl = 'http://localhost:8080/api';

  /// Android 模拟器访问宿主机
  static const String _androidUrl = 'http://10.0.2.2:8080/api';

  /// Android 真机：电脑的局域网 IP
  /// 换网络时不用改代码，打包时用参数覆盖即可：
  /// flutter build apk --release --dart-define=API_ENV=lan --dart-define=API_BASE_URL=http://192.168.x.x:8080/api
  static const String _lanUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.31.232:8080/api',
  );

  static const String env = String.fromEnvironment('API_ENV', defaultValue: 'local');

  /// 部署/演示时可直接用参数指定完整接口地址，优先级最高：
  /// flutter build web --dart-define=API_BASE_URL=http://服务器IP:8090/api
  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) {
      return _override;
    }
    switch (env) {
      case 'android':
        return _androidUrl;
      case 'lan':
        return _lanUrl;
      default:
        return _localUrl;
    }
  }
}
