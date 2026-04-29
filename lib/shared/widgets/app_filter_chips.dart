import 'package:flutter/material.dart';
import 'package:money_manager/app/theme/app_colors.dart';

class AppFilterChipItem<T> {
  const AppFilterChipItem({required this.value, required this.label});

  final T value;
  final String label;
}

class AppFilterChips<T> extends StatelessWidget {
  const AppFilterChips({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<AppFilterChipItem<T>> items;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color selectedBackground = isDark
        ? AppColors.darkElevated
        : AppColors.primary;
    final Color unselectedBackground = isDark
        ? AppColors.darkCard
        : Colors.white;
    final Color unselectedBorder = isDark
        ? AppColors.darkBorder
        : AppColors.lightMint;
    final Color selectedText = isDark ? AppColors.textLight : Colors.white;
    final Color unselectedText = isDark
        ? AppColors.mutedLight
        : AppColors.textDark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items
            .map((item) {
              final bool isSelected = item.value == selected;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => onChanged(item.value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? selectedBackground
                          : unselectedBackground,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : unselectedBorder,
                        width: 1.3,
                      ),
                      boxShadow: isSelected
                          ? <BoxShadow>[
                              BoxShadow(
                                color: AppColors.primary.withValues(
                                  alpha: isDark ? 0.10 : 0.18,
                                ),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.10 : 0.03,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                    ),
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? selectedText : unselectedText,
                      ),
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}
