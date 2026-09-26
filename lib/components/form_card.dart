import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// iOS 分组表单卡片：白底圆角 + 行间分隔线，可选组标题与组说明
class FormCard extends StatelessWidget {
  final List<Widget> children;
  final String? header;
  final String? footer;

  const FormCard({
    super.key,
    required this.children,
    this.header,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
            child: Text(
              header!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8E8E93),
                letterSpacing: 0.2,
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: <Widget>[
              for (var i = 0; i < children.length; i++) ...<Widget>[
                if (i > 0)
                  const Divider(
                    height: 1,
                    thickness: 0.6,
                    indent: 16,
                    color: Color(0xFFE5E5EA),
                  ),
                children[i],
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 7, 4, 0),
            child: Text(
              footer!,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: Color(0xFF8E8E93),
              ),
            ),
          ),
      ],
    );
  }
}

/// 表单行：左标签 + 右值 / 控件，整行可点击
class FormRow extends StatelessWidget {
  final String label;
  final String? valueText;
  final Color? valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final double minHeight;

  const FormRow({
    super.key,
    required this.label,
    this.valueText,
    this.valueColor,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.minHeight = 52,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: trailing ??
                    Text(
                      valueText ?? '',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 15,
                        color: valueColor ?? const Color(0xFF8E8E93),
                      ),
                    ),
              ),
            ),
            if (showChevron) ...<Widget>[
              const SizedBox(width: 6),
              const Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: Color(0xFFC7C7CC),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 竖排表单块：上方小标签 + 下方控件（用于优先级 / 色板等较宽的内容）
class FormBlock extends StatelessWidget {
  final String label;
  final Widget child;
  final String? hint;

  const FormBlock({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 10),
          child,
          if (hint != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              hint!,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: Color(0xFF8E8E93),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 信息提示条（如「来自周期·xxx，修改只影响这一次」）
class InfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;

  const InfoBanner({
    super.key,
    required this.text,
    this.icon = CupertinoIcons.info_circle,
    this.color = const Color(0xFFFF9500),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: color.withValues(alpha: 0.95),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
