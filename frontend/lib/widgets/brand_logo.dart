import 'package:flutter/material.dart';

/// 福瑞记账品牌标识：招财猫图标 + 名称 + 标语。
/// 登录、注册、关于等页面共用，保证品牌呈现一致。
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = 88,
    this.showName = true,
    this.showSlogan = true,
  });

  /// 图标边长
  final double size;
  final bool showName;
  final bool showSlogan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/brand/app_icon_rounded.png',
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
        ),
        if (showName) ...[
          SizedBox(height: size * 0.16),
          Text(
            '福瑞记账',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: const Color(0xFFC9761A),
            ),
          ),
        ],
        if (showSlogan) ...[
          const SizedBox(height: 6),
          Text(
            '记下每一笔 · 收获更好的自己',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.brown.shade300,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ],
    );
  }
}
