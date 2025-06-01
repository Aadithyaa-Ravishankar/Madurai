import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';

extension AppLocalizationsExtension on AppLocalizations {
  String? dynamicLookup(String key) {
    debugPrint('[_LocalizationHelper] Attempting to lookup key: $key');
    
    try {
      // ignore: unnecessary_cast
      final map = this as dynamic;
      
      // Try to access the property directly using the key
      final value = map[key] as String?;
      debugPrint('[_LocalizationHelper] Property lookup result: $value');
      return value;
    } catch (e) {
      debugPrint('[_LocalizationHelper] Error during lookup: $e');
      return null;
    }
  }

  // Helper method to get councillor details for a specific ward
  Map<String, String> getCouncillorDetails(String wardNo) {
    debugPrint('[_LocalizationHelper] Getting councillor details for ward $wardNo');
    
    final nameKey = 'councillor_${wardNo}_name';
    final partyKey = 'councillor_${wardNo}_party';
    final responsibilityKey = 'councillor_${wardNo}_responsibility';

    final name = dynamicLookup(nameKey);
    final party = dynamicLookup(partyKey);
    final responsibility = dynamicLookup(responsibilityKey);

    debugPrint('[_LocalizationHelper] Found translations:');
    debugPrint('  - Name: $name');
    debugPrint('  - Party: $party');
    debugPrint('  - Responsibility: $responsibility');

    return {
      'name': name ?? '',
      'party': party ?? '',
      'responsibility': responsibility ?? '',
    };
  }

  // Helper method to get ward name
  String? getWardName(String wardNo) {
    debugPrint('[_LocalizationHelper] Getting ward name for ward $wardNo');
    final key = 'wardName$wardNo';
    debugPrint('[_LocalizationHelper] Looking up key: $key');
    final name = dynamicLookup(key);
    debugPrint('[_LocalizationHelper] Found ward name: $name');
    return name;
  }
}

extension DynamicLocalizations on dynamic {
  dynamic $getProperty(String name) {
    try {
      // Try to access it as a property
      return this.$name;
    } catch (_) {
      try {
        // Try to access it as a method
        final method = this[name] as Function?;
        if (method != null) {
          return method();
        }
      } catch (_) {
        // If all else fails, try to access it as a property
        return this.$name;
      }
    }
    return null;
  }
}

class _LocalizationProxy {
  final AppLocalizations _localizations;
  
  _LocalizationProxy(this._localizations);
  
  dynamic $getProperty(String name) {
    // ignore: unnecessary_cast
    final map = _localizations as dynamic;
    return map[name];
  }
  
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      final name = invocation.memberName.toString().split('"')[1];
      return $getProperty(name);
    }
    return super.noSuchMethod(invocation);
  }
} 