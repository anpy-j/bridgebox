import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum StatusKind {
  active,
  inactive,
  warning,
  error,
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.kind,
    this.showDot = true,
  });

  factory StatusBadge.running([String label = '运行中']) =>
      StatusBadge(label: label, kind: StatusKind.active);

  factory StatusBadge.stopped([String label = '已停止']) =>
      StatusBadge(label: label, kind: StatusKind.inactive);

  factory StatusBadge.restarting([String label = '重启中']) =>
      StatusBadge(label: label, kind: StatusKind.warning);

  factory StatusBadge.failed([String label = '异常']) =>
      StatusBadge(label: label, kind: StatusKind.error);

  final String label;
  final StatusKind kind;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final (color, glowColor, bg) = switch (kind) {
      StatusKind.active => (
          AppColors.success,
          AppColors.successGlow,
          const Color(0x1A10B981)
        ),
      StatusKind.inactive => (
          AppColors.muted,
          Colors.transparent,
          const Color(0x1E64748B)
        ),
      StatusKind.warning => (
          AppColors.warning,
          AppColors.warningGlow,
          const Color(0x1AF59E0B)
        ),
      StatusKind.error => (
          AppColors.error,
          AppColors.errorGlow,
          const Color(0x1AEF4444)
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: glowColor != Colors.transparent
                    ? [BoxShadow(color: glowColor, blurRadius: 4, spreadRadius: 1)]
                    : null,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
