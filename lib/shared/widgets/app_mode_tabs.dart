import 'package:flutter/material.dart';
import 'package:money_manager/app/theme/app_colors.dart';

class AppModeTabItem<T> {
  const AppModeTabItem({
    required this.value,
    required this.label,
    required this.icon,
  });

  final T value;
  final String label;
  final IconData icon;
}

class AppModeTabs<T> extends StatelessWidget {
  const AppModeTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<AppModeTabItem<T>> items;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color containerColor = isDark
        ? AppColors.darkSurface
        : AppColors.lightMint;
    final Color selectedColor = isDark ? AppColors.darkElevated : Colors.white;
    final Color activeColor = isDark
        ? AppColors.textLight
        : AppColors.primaryDark;
    final Color inactiveColor = isDark
        ? AppColors.mutedLight
        : AppColors.textDark.withValues(alpha: 0.55);

    return Container(
      height: 52,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightMint,
          width: 1.2,
        ),
      ),
      child: Row(
        children: items.map((item) {
          final bool isSelected = item.value == selected;

          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(item.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: isSelected ? selectedColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: isSelected
                      ? <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.14 : 0.08,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      item.icon,
                      size: 18,
                      color: isSelected ? activeColor : inactiveColor,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        item.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: isSelected ? activeColor : inactiveColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
