import 'package:flutter/material.dart';

/// 福瑞记账品牌信息与配色，页面统一从这里取值，避免颜色散落在各处。
class Brand {
  Brand._();

  static const String name = '福瑞记账';
  static const String englishName = 'Furui Bookkeeping';
  static const String slogan = '记下每一笔 · 收获更好的自己';
  static const String version = '1.0.0';

  /// 主色：暖橙（按钮、强调数字、选中状态）
  static const Color orange = Color(0xFFF5A524);

  /// 辅助色：账本绿（收入、增长）
  static const Color green = Color(0xFF2E7D6F);

  /// 背景：奶油白
  static const Color cream = Color(0xFFFFF6E8);

  /// 卡片底色
  static const Color surface = Color(0xFFFFFFFF);

  /// 支出与超支提示用的暖红
  static const Color expense = Color(0xFFD64545);

  /// 收入与正向数字
  static const Color income = Color(0xFF2E9E6B);
}
