/// 接口异常：message 直接取后端返回的提示，展示给用户看。
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  /// 网络不通、后端没启动这类情况统一用 0
  bool get isNetworkError => statusCode == 0;

  @override
  String toString() => message;
}
