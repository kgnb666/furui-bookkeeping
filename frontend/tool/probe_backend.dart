// ignore_for_file: avoid_print

import 'dart:io';

/// 快速探测本地后端是否可达，用于联调前自检。
/// 用法：dart run tool/probe_backend.dart [http://127.0.0.1:8080/api]
Future<void> main(List<String> args) async {
  final base = args.isEmpty ? 'http://127.0.0.1:8080/api' : args.first;
  final uri = Uri.parse('$base/health');
  final stopwatch = Stopwatch()..start();
  try {
    final response = await HttpClient()
        .getUrl(uri)
        .timeout(const Duration(seconds: 3))
        .then((request) => request.close())
        .timeout(const Duration(seconds: 3));
    await response.drain<void>();
    print('$uri -> ${response.statusCode}  (${stopwatch.elapsedMilliseconds}ms)');
  } catch (e) {
    print('$uri -> 不可达：$e  (${stopwatch.elapsedMilliseconds}ms)');
  }
}
