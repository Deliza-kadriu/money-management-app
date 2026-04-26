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
    return Container(
      height: 52,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.lightMint,
        borderRadius: BorderRadius.circular(22),
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
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: isSelected
                      ? <BoxShadow>[
                    BoxShadow(
                      color: AppColors.primaryDark.withValues(alpha: 0.10),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
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
                      color: isSelected
                          ? AppColors.primaryDark
                          : AppColors.textDark.withValues(alpha: 0.55),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        item.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: isSelected
                              ? AppColors.primaryDark
                              : AppColors.textDark.withValues(alpha: 0.55),
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