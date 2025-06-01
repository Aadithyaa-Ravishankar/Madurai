import 'package:flutter_gen/gen_l10n/app_localizations.dart';

extension AppLocalizationsExtension on AppLocalizations {
  String? dynamicLookup(String key) {
    // ignore: unnecessary_cast
    final map = this as dynamic;
    try {
      return map.getValue(key) as String?;
    } catch (_) {
      // fallback: try to access as a property
      try {
        return map.getField(key) as String?;
      } catch (_) {
        return null;
      }
    }
  }
} 