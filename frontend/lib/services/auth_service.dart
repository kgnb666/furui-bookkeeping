import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/models/user.dart';
import 'package:campus_ledger/services/api_client.dart';

/// 登录状态与用户资料。token 存在 shared_preferences 里。
class AuthService {
  AuthService._();

  static const String _tokenKey = 'token';
  static const String _userKey = 'user';

  static User? currentUser;

  static bool get isLoggedIn => ApiClient.token != null && ApiClient.token!.isNotEmpty;

  /// App 启动时读取本地 token
  static Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) {
      return;
    }
    ApiClient.token = token;
    final userJson = prefs.getString(_userKey);
    if (userJson != null && userJson.isNotEmpty) {
      try {
        currentUser = User.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      } catch (_) {
        currentUser = null;
      }
    }
  }

  static Future<User> login(String username, String password) async {
    final data = await ApiClient.post('/auth/login', body: {
      'username': username,
      'password': password,
    }) as Map<String, dynamic>;
    ApiClient.token = data['token'] as String?;
    final user = User.fromJson(data['user'] as Map<String, dynamic>);
    currentUser = user;
    await _save(user);
    return user;
  }

  static Future<User> register({
    required String username,
    required String password,
    String? nickname,
  }) async {
    final body = <String, dynamic>{
      'username': username,
      'password': password,
    };
    if (nickname != null && nickname.isNotEmpty) {
      body['nickname'] = nickname;
    }
    final data = await ApiClient.post('/auth/register', body: body) as Map<String, dynamic>;
    return User.fromJson(data);
  }

  static Future<User> loadProfile() async {
    final data = await ApiClient.get('/user/profile') as Map<String, dynamic>;
    final user = User.fromJson(data);
    currentUser = user;
    await _save(user);
    return user;
  }

  static Future<User> updateProfile({String? nickname, String? email}) async {
    final body = <String, dynamic>{};
    if (nickname != null) {
      body['nickname'] = nickname;
    }
    if (email != null) {
      body['email'] = email;
    }
    final data = await ApiClient.put('/user/profile', body: body) as Map<String, dynamic>;
    final user = User.fromJson(data);
    currentUser = user;
    await _save(user);
    return user;
  }

  static Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await ApiClient.put('/user/password', body: {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    });
  }

  static Future<void> logout() async {
    ApiClient.token = null;
    currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  static Future<void> _save(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final token = ApiClient.token;
    if (token != null) {
      await prefs.setString(_tokenKey, token);
    }
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }
}
