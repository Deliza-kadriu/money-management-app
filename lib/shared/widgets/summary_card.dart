import 'package:flutter/material.dart';

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Text(
              amountLabel,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: accentColor),
            ),
          ],
        ),
      ),
    );
  }
}
