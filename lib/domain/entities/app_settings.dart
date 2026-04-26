class AppSettings {
  const AppSettings({
    required this.baseCurrencyCode,
    required this.notificationsEnabled,
    required this.reminderLeadDays,
  });

  const AppSettings.defaults()
    : baseCurrencyCode = 'USD',
      notificationsEnabled = true,
      reminderLeadDays = 1;

  final String baseCurrencyCode;
  final bool notificationsEnabled;
  final int reminderLeadDays;

  AppSettings copyWith({
    String? baseCurrencyCode,
    bool? notificationsEnabled,
    int? reminderLeadDays,
  }) {
    return AppSettings(
      baseCurrencyCode: baseCurrencyCode ?? this.baseCurrencyCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      reminderLeadDays: reminderLeadDays ?? this.reminderLeadDays,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'baseCurrencyCode': baseCurrencyCode,
      'notificationsEnabled': notificationsEnabled,
      'reminderLeadDays': reminderLeadDays,
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
    );
  }
}
