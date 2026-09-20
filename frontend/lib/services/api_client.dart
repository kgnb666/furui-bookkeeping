import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:campus_ledger/config/api_config.dart';
import 'package:campus_ledger/models/api_exception.dart';

/// 统一的 HTTP 客户端：拼接地址、带 JWT、解析统一响应体、转换错误提示。
class ApiClient {
  ApiClient._();

  static String? token;

  /// 收到 401 时的回调，由 App 入口设置成“清除 token 并回登录页”
  static void Function()? onUnauthorized;

  /// 运行时覆盖接口地址，默认使用 ApiConfig 里的环境配置
  static String? _baseUrlOverride;

  static void overrideBaseUrl(String? baseUrl) {
    _baseUrlOverride = baseUrl;
  }

  static const Duration _timeout = Duration(seconds: 30);
  static const Duration _uploadTimeout = Duration(seconds: 120);

  static final http.Client _defaultClient = http.Client();
  static http.Client _client = _defaultClient;

  /// 仅供测试使用：替换底层 HTTP 客户端，让 Widget 测试可以构造后端响应，
  /// 无需真的起一个后端。传 null 恢复默认客户端。
  @visibleForTesting
  static set testClient(http.Client? client) {
    _client = client ?? _defaultClient;
  }

  static Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse('${_baseUrlOverride ?? ApiConfig.baseUrl}/');
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    final uri = base.resolve(normalized);
    if (query == null || query.isEmpty) {
      return uri;
    }
    final params = <String, String>{};
    query.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        params[key] = value.toString();
      }
    });
    if (params.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: {...uri.queryParameters, ...params});
  }

  static Map<String, String> _headers({bool withBody = false}) {
    final headers = <String, String>{};
    if (withBody) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }
    if (token != null && token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Future<dynamic> get(String path, {Map<String, dynamic>? query}) {
    return _send('GET', path, query: query);
  }

  static Future<dynamic> post(String path, {Object? body}) {
    return _send('POST', path, body: body);
  }

  static Future<dynamic> put(String path, {Object? body}) {
    return _send('PUT', path, body: body);
  }

  static Future<dynamic> delete(String path) {
    return _send('DELETE', path);
  }

  static Future<dynamic> _send(String method, String path,
      {Object? body, Map<String, dynamic>? query}) async {
    try {
      final uri = _uri(path, query);
      final http.Response response;
      switch (method) {
        case 'POST':
          response = await _client
              .post(uri, headers: _headers(withBody: true), body: body == null ? null : jsonEncode(body))
              .timeout(_timeout);
        case 'PUT':
          response = await _client
              .put(uri, headers: _headers(withBody: true), body: body == null ? null : jsonEncode(body))
              .timeout(_timeout);
        case 'DELETE':
          response = await _client.delete(uri, headers: _headers()).timeout(_timeout);
        default:
          response = await _client.get(uri, headers: _headers()).timeout(_timeout);
      }
      return _handle(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(0, '请求超时，请检查网络或稍后重试');
    } on http.ClientException {
      throw ApiException(0, '无法连接服务器，请确认后端已启动');
    } catch (e) {
      throw ApiException(0, '请求失败：$e');
    }
  }

  /// multipart 上传账单文件
  static Future<dynamic> upload(String path,
      {required List<int> bytes,
      required String fileName,
      required Map<String, String> fields}) async {
    try {
      final request = http.MultipartRequest('POST', _uri(path));
      if (token != null && token!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.fields.addAll(fields);
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
      final streamed = await request.send().timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamed);
      return _handle(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(0, '上传超时，请检查网络或稍后重试');
    } on http.ClientException {
      throw ApiException(0, '无法连接服务器，请确认后端已启动');
    } catch (e) {
      throw ApiException(0, '上传失败：$e');
    }
  }

  static dynamic _handle(http.Response response) {
    final status = response.statusCode;
    dynamic decoded;
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
    }
    if (status == 401) {
      // 只有在“已登录还带 token”的情况下才当成登录失效，避免登录页输错密码也被跳转
      if (token != null && token!.isNotEmpty) {
        onUnauthorized?.call();
      }
      throw ApiException(401, _message(decoded) ?? '登录已过期，请重新登录');
    }
    if (status >= 200 && status < 300) {
      if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
        return decoded['data'];
      }
      return decoded;
    }
    throw ApiException(status, _message(decoded) ?? _defaultMessage(status));
  }

  /// 下载二进制文件（账单导出）：成功返回字节与文件名，失败按统一规则抛 ApiException
  static Future<({List<int> bytes, String fileName})> download(String path,
      {Map<String, dynamic>? query}) async {
    try {
      final uri = _uri(path, query);
      final response = await _client.get(uri, headers: _headers()).timeout(_timeout);
      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        return (
          bytes: response.bodyBytes,
          fileName: _fileName(response.headers['content-disposition'], response.headers['x-export-filename']),
        );
      }
      // 失败时后端返回的仍然是统一响应体，交给 _handle 统一转成中文提示
      _handle(response);
      throw ApiException(status, _defaultMessage(status));
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(0, '导出超时，请稍后重试');
    } on http.ClientException {
      throw ApiException(0, '无法连接服务器，请确认后端已启动');
    } catch (e) {
      throw ApiException(0, '导出失败：$e');
    }
  }

  /// 从响应头解析文件名：优先用后端给的 X-Export-Filename（已 URL 编码）
  static String _fileName(String? contentDisposition, String? exportHeader) {
    if (exportHeader != null && exportHeader.isNotEmpty) {
      return Uri.decodeComponent(exportHeader);
    }
    if (contentDisposition != null) {
      final match = RegExp(r"filename\*=UTF-8''([^;]+)").firstMatch(contentDisposition);
      if (match != null) {
        return Uri.decodeComponent(match.group(1)!);
      }
      final plain = RegExp(r'filename="([^"]+)"').firstMatch(contentDisposition);
      if (plain != null) {
        return plain.group(1)!;
      }
    }
    return 'furui_bill_export';
  }

  static String? _message(dynamic decoded) {
    if (decoded is Map && decoded['message'] is String) {
      final message = decoded['message'] as String;
      return message.isEmpty ? null : message;
    }
    return null;
  }

  static String _defaultMessage(int status) {
    switch (status) {
      case 400:
        return '请求参数有误';
      case 403:
        return '没有权限访问该数据';
      case 404:
        return '数据不存在';
      case 409:
        return '数据已存在';
      case 413:
        return '文件太大';
      case 500:
        return '服务器开小差了，请稍后重试';
      default:
        return '请求失败（$status）';
    }
  }
}
