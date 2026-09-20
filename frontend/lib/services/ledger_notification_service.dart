import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/services/api_client.dart';

/// 手机通知栏常驻看板（今日开支 / 本月预算 / 结余）的桥接。
///
/// 只在 Android 上生效：常驻通知依赖 Android 的 NotificationManager，
/// 其它平台（Web / Windows）所有方法都是空操作，不会抛异常。
///
/// 职责划分：
/// - Flutter 侧负责把 token 与接口地址同步给原生、以及触发「立即刷新」；
/// - 后台每 30 分钟的定时刷新由原生侧的 WorkManager 独立完成，不依赖 Flutter 引擎存活。
class LedgerNotificationService {
  LedgerNotificationService._();

  static const MethodChannel _channel = MethodChannel('campus_ledger/notification');

  /// 用户是否开启过常驻通知（存在 Flutter 侧，用于登录后自动恢复）
  static const String _prefKey = 'ledger_notification_enabled';

  /// 只有 Android 有常驻通知；Web / Windows / iOS 走空实现。
  /// 这里用 defaultTargetPlatform 而不是 dart:io 的 Platform，
  /// 因为 dart:io 在 Web 构建里不可用。
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 用户上次的开关状态
  static Future<bool> preference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> _setPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }

  /// 原生侧当前是否处于开启状态
  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 打开常驻通知。返回 true 表示通知权限已拿到（Android 13+ 会弹系统授权框）。
  static Future<bool> enable() async {
    if (!isSupported) return false;
    final token = ApiClient.token;
    if (token == null || token.isEmpty) return false;
    try {
      final granted = await _channel.invokeMethod<bool>('enable', {
        'token': token,
        'baseUrl': ApiClient.effectiveBaseUrl,
      });
      if (granted == true) {
        await _setPreference(true);
      }
      return granted ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 关闭常驻通知，并取消后台刷新。
  /// 保留用户偏好，重新登录后仍会自动恢复。
  static Future<void> disable() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('disable');
    } on PlatformException {
      // 关闭失败无需打扰用户
    } on MissingPluginException {
      // 非 Android 平台或插件未注册
    }
  }

  /// 立即刷新一次通知内容（记账后、切回 App 时调用）。
  static Future<void> refresh() async {
    if (!isSupported) return;
    final token = ApiClient.token;
    if (token == null || token.isEmpty) return;
    if (!await isEnabled()) return;
    try {
      await _channel.invokeMethod<bool>('refresh', {
        'token': token,
        'baseUrl': ApiClient.effectiveBaseUrl,
      });
    } on PlatformException {
      // 刷新失败不影响主流程
    } on MissingPluginException {
      // 忽略
    }
  }

  /// 登录成功后调用：如果用户之前开着，就用新 token 重新挂上。
  static Future<void> onLogin() async {
    if (!isSupported) return;
    if (!await preference()) return;
    await enable();
  }

  /// 退出登录时调用：停掉刷新并收起通知，避免显示上一个账号的数据。
  static Future<void> onLogout() async {
    if (!isSupported) return;
    await disable();
  }
}
