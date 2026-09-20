// 演示数据种子脚本（答辩 / 截图 / 部署验证用）。
//
// 用法：
//   dart run tool/seed_demo_data.dart [--base http://127.0.0.1:8080/api] [--user demo_furui] [--password 123456]
//
// 它会创建一个演示账号，并在最近 6 个自然月里写入结构化的账单与预算，
// 使七个智能能力都有可展示的结果：
//   4-A 预算预测    → 当月设置了总预算与分类预算，且消费节奏足以预测
//   4-B 周期识别    → 腾讯视频VIP 每月一笔（≥4 次样本）
//   4-C 异常检测    → 当月餐饮明显高于前 3 个月基线 + 一笔大额消费
//   4-D 下月预估    → 前 3 个完整月都有支出
//   4-E 节奏分析    → 当月分布在多个日期与星期
//   4-F 消费对象    → 多个消费对象、覆盖率 100%
//   4-G 收支结余    → 每月都有生活费与兼职收入
//
// 脚本可重复执行：账单带备注前缀，重复导入不会命中既有去重键（手动记账 dedup_key 为 NULL），
// 因此如需重置请直接删除该演示账号（其账单会随外键级联删除）。
import 'dart:convert';
import 'dart:io';

const _defaultBase = 'http://127.0.0.1:8080/api';
const _defaultUser = 'demo_furui';
const _defaultPassword = '123456';

/// 演示数据里用到的分类（与后端固定分类集合一致）
const _canyin = '餐饮';
const _jiaotong = '交通';
const _gouwu = '购物';
const _yule = '娱乐';
const _shenghuofei = '生活费';
const _jianzhi = '兼职收入';

/// 演示数据里用到的交易对象
const _shangtang = '第一食堂';
const _chaoshi = '校园超市';
const _gongjiao = '城市公交';
const _naicha = '奶茶店';
const _tencent = '腾讯视频VIP';
const _wenju = '文具店';

Future<void> main(List<String> args) async {
  final base = _arg(args, '--base') ?? _defaultBase;
  final username = _arg(args, '--user') ?? _defaultUser;
  final password = _arg(args, '--password') ?? _defaultPassword;

  final client = HttpClient();
  final api = _Api(client, base);

  stdout.writeln('目标后端：$base');
  stdout.writeln('演示账号：$username');

  // 1. 注册（已存在时忽略）+ 登录
  await api.post('/auth/register', {'username': username, 'password': password, 'nickname': '演示账号'},
      ignoreError: true);
  final login = await api.post('/auth/login', {'username': username, 'password': password});
  final token = (login['data'] as Map)['token'] as String;
  api.token = token;
  stdout.writeln('登录成功');

  final now = DateTime.now();
  final currentMonth = DateTime(now.year, now.month, 1);
  var created = 0;
  var skipped = 0;

  Future<void> addBill(int type, String amount, String category, String date, String merchant,
      {String remark = '演示数据'}) async {
    final result = await api.post('/bills', {
      'type': type.toString(),
      'amount': amount,
      'category': category,
      'billDate': date,
      'merchant': merchant,
      'remark': remark,
    }, ignoreError: true);
    if (result['code'] == 0) {
      created++;
    } else {
      skipped++;
    }
  }

  String day(int monthsAgo, int dayOfMonth) {
    final base = DateTime(currentMonth.year, currentMonth.month - monthsAgo, 1);
    final lastDay = DateTime(base.year, base.month + 1, 0).day;
    final safe = dayOfMonth > lastDay ? lastDay : dayOfMonth;
    return '${base.year}-${base.month.toString().padLeft(2, '0')}-${safe.toString().padLeft(2, '0')}';
  }

  // 2. 历史 5 个完整月 + 当月：每月生活费 / 兼职收入 + 日常支出 + 月度订阅
  for (var monthsAgo = 5; monthsAgo >= 0; monthsAgo--) {
    final isCurrent = monthsAgo == 0;
    // 收入的日期不超过今天
    final incomeDay = isCurrent ? 1 : 1;
    await addBill(2, '2400.00', _shenghuofei, day(monthsAgo, incomeDay), '家里转账');
    if (monthsAgo % 2 == 0) {
      await addBill(2, '600.00', _jianzhi, day(monthsAgo, isCurrent ? 2 : 15), '校园兼职');
    }

    // 日常支出：餐饮作为主导分类
    // 历史月餐饮 400，当月 1200 → 触发 4-C 的分类上涨异常
    final canyinAmount = isCurrent ? '1200.00' : '400.00';
    await addBill(1, canyinAmount, _canyin, day(monthsAgo, isCurrent ? 1 : 5), _shangtang);
    await addBill(1, '35.00', _canyin, day(monthsAgo, isCurrent ? 2 : 8), _naicha);
    await addBill(1, '60.00', _canyin, day(monthsAgo, isCurrent ? 3 : 12), _shangtang);
    await addBill(1, '80.00', _gouwu, day(monthsAgo, isCurrent ? 4 : 16), _chaoshi);
    await addBill(1, '22.00', _jiaotong, day(monthsAgo, isCurrent ? 5 : 18), _gongjiao);
    await addBill(1, '45.00', _yule, day(monthsAgo, isCurrent ? 6 : 22), '校园影院');
    await addBill(1, '30.00', _gouwu, day(monthsAgo, isCurrent ? 7 : 25), _wenju);

    // 月度订阅：每月固定日期一笔，用于 4-B 的周期识别
    await addBill(1, '25.00', _yule, day(monthsAgo, isCurrent ? 8 : 20), _tencent,
        remark: '视频会员');
  }

  // 3. 当月额外制造一笔大额消费（4-C 的单笔异常）
  await addBill(1, '880.00', _gouwu, day(0, 9), '数码店', remark: '演示数据-大额消费');

  // 4. 预算：当月总预算 + 两个分类预算（4-A 需要预算才会给出预测）
  for (final budget in [
    {'category': '', 'amount': '1800.00'},
    {'category': _canyin, 'amount': '1000.00'},
    {'category': _gouwu, 'amount': '600.00'},
  ]) {
    final monthKey = '${currentMonth.year}-${currentMonth.month.toString().padLeft(2, '0')}';
    final body = {
      'month': monthKey,
      'category': budget['category'],
      'amount': budget['amount'],
    };
    final result = await api.post('/budgets', body, ignoreError: true);
    if (result['code'] == 0) {
      created++;
    } else {
      // 已存在同月同分类预算时更新金额
      final list = await api.get('/budgets', query: {'month': monthKey});
      final data = list['data'] as Map<String, dynamic>? ?? {};
      final items = <Map<String, dynamic>>[];
      if (data['total'] != null) items.add(data['total'] as Map<String, dynamic>);
      items.addAll(((data['categories'] as List?) ?? const []).cast<Map<String, dynamic>>());
      for (final item in items) {
        if (item['category'] == body['category'] && item['id'] != null) {
          await api.put('/budgets/${item['id']}', body, ignoreError: true);
          break;
        }
      }
      skipped++;
    }
  }

  // 5. 汇总
  final month = '${currentMonth.year}-${currentMonth.month.toString().padLeft(2, '0')}';
  stdout.writeln('写入完成：新增 $created 条，跳过 $skipped 条');
  for (final path in [
    '/insights/monthly?month=$month',
    '/insights/recurring',
    '/insights/anomalies?month=$month',
    '/insights/forecast?month=$month',
    '/insights/rhythm?month=$month',
    '/insights/merchants?month=$month',
    '/insights/balance?month=$month',
    '/budgets/predictions?month=$month',
  ]) {
    final result = await api.get(path);
    final data = result['data'];
    final status = data is Map ? data['status'] : '—';
    stdout.writeln('  ${path.padRight(46)} status=$status');
  }
  client.close();
}

String? _arg(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index >= 0 && index + 1 < args.length) {
    return args[index + 1];
  }
  return null;
}

/// 极简 HTTP 封装：只在本脚本内使用，不依赖应用代码
class _Api {
  _Api(this._client, this.base);

  final HttpClient _client;
  final String base;
  String? token;

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {bool ignoreError = false}) async {
    return _send('POST', path, body: body, ignoreError: ignoreError);
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body,
      {bool ignoreError = false}) async {
    return _send('PUT', path, body: body, ignoreError: ignoreError);
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    return _send('GET', uri.toString(), absolute: true);
  }

  Future<Map<String, dynamic>> _send(String method, String path,
      {Map<String, dynamic>? body, bool absolute = false, bool ignoreError = false}) async {
    final uri = absolute ? Uri.parse(path) : Uri.parse('$base$path');
    final request = await _client.openUrl(method, uri);
    request.headers.set('Content-Type', 'application/json; charset=utf-8');
    if (token != null) {
      request.headers.set('Authorization', 'Bearer $token');
    }
    if (body != null) {
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
    if (!ignoreError && response.statusCode >= 400) {
      throw StateError('$method $path 失败：${response.statusCode} $text');
    }
    return decoded;
  }
}
