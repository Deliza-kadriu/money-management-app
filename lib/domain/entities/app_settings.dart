import 'package:flutter/material.dart';

enum AppThemePreference {
  system,
  light,
  dark;

  ThemeMode toThemeMode() {
    switch (this) {
      case AppThemePreference.system:
        return ThemeMode.system;
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
        return ThemeMode.dark;
    }
  }

  static AppThemePreference fromStorage(Object? value) {
    final String? rawValue = value as String?;
    for (final mode in AppThemePreference.values) {
      if (mode.name == rawValue) {
        return mode;
      }
    }
    return AppThemePreference.system;
  }
}

class AppSettings {
  const AppSettings({
    required this.baseCurrencyCode,
    required this.notificationsEnabled,
    required this.reminderLeadDays,
    required this.themePreference,
  });

  const AppSettings.defaults()
    : baseCurrencyCode = 'USD',
      notificationsEnabled = true,
      reminderLeadDays = 1,
      themePreference = AppThemePreference.system;

  final String baseCurrencyCode;
  final bool notificationsEnabled;
  final int reminderLeadDays;
  final AppThemePreference themePreference;

  AppSettings copyWith({
    String? baseCurrencyCode,
    bool? notificationsEnabled,
    int? reminderLeadDays,
    AppThemePreference? themePreference,
  }) {
    return AppSettings(
      baseCurrencyCode: baseCurrencyCode ?? this.baseCurrencyCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      reminderLeadDays: reminderLeadDays ?? this.reminderLeadDays,
      themePreference: themePreference ?? this.themePreference,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'baseCurrencyCode': baseCurrencyCode,
      'notificationsEnabled': notificationsEnabled,
      'reminderLeadDays': reminderLeadDays,
      'themePreference': themePreference.name,
    };
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    return AppSettings(
      baseCurrencyCode:
          json['baseCurrencyCode'] as String? ??
          const AppSettings.defaults().baseCurrencyCode,
      notificationsEnabled:
          json['notificationsEnabled'] as bool? ??
          const AppSettings.defaults().notificationsEnabled,
      reminderLeadDays:
          json['reminderLeadDays'] as int? ??
          const AppSettings.defaults().reminderLeadDays,
      themePreference: AppThemePreference.fromStorage(json['themePreference']),
    );
  }
}
