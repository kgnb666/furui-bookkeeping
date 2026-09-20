import 'package:flutter_test/flutter_test.dart';

import 'package:campus_ledger/utils/money.dart';

void main() {
  group('金额校验', () {
    test('合法金额', () {
      expect(Money.validate('31.00'), isNull);
      expect(Money.validate('0.01'), isNull);
      expect(Money.validate('1500'), isNull);
      expect(Money.validate(' 12.5 '), isNull);
    });

    test('非法金额会被拦下', () {
      expect(Money.validate(''), '请输入金额');
      expect(Money.validate(null), '请输入金额');
      expect(Money.validate('abc'), isNotNull);
      expect(Money.validate('12.345'), isNotNull);
      expect(Money.validate('0'), '金额必须大于 0');
      expect(Money.validate('-5'), isNotNull);
    });
  });

  group('整数分计算', () {
    test('字符串与分之间互转', () {
      expect(Money.toCents('31.00'), 3100);
      expect(Money.toCents('0.05'), 5);
      expect(Money.toCents('1500'), 150000);
      expect(Money.fromCents(3100), '31.00');
      expect(Money.fromCents(5), '0.05');
    });

    test('相加不会出现浮点误差', () {
      expect(Money.sum(['0.10', '0.20']), '0.30');
      expect(Money.sum(['31.00', '15.00', '89.00']), '135.00');
      expect(Money.sum([]), '0.00');
    });
  });
}
