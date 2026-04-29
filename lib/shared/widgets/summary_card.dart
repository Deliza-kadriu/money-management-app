import 'package:flutter/material.dart';
import 'package:money_manager/app/theme/app_colors.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.label,
    required this.amountLabel,
    required this.accentColor,
  });

  final String label;
  final String amountLabel;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color chipColor = accentColor.withValues(alpha: isDark ? 0.18 : 0.12);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 34,
              height: 4,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDark ? 0.75 : 1),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark ? AppColors.mutedLight : const Color(0xFF627267),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              amountLabel,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: accentColor),
            ),
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: chipColor,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const SizedBox(height: 6, width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}
