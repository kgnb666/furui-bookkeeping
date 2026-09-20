/// 分类常量，必须与后端保持一致（后端会校验分类是否合法）。
class Categories {
  Categories._();

  static const int expense = 1;
  static const int income = 2;
  static const int neutral = 3;

  static const List<String> expenseCategories = [
    '餐饮', '交通', '购物', '娱乐', '学习', '住宿', '生活', '医疗', '通讯', '其他',
  ];

  static const List<String> incomeCategories = [
    '生活费', '奖助学金', '兼职收入', '红包', '其他收入',
  ];

  static const List<String> neutralCategories = [
    '转账', '红包', '提现', '还款', '其他',
  ];

  static const Map<int, List<String>> byType = {
    expense: expenseCategories,
    income: incomeCategories,
    neutral: neutralCategories,
  };

  static const Map<int, String> typeNames = {
    expense: '支出',
    income: '收入',
    neutral: '不计收支',
  };

  static List<String> of(int type) => byType[type] ?? expenseCategories;

  static String typeName(int type) => typeNames[type] ?? '支出';

  static String defaultOf(int type) => type == income ? '其他收入' : '其他';
}
