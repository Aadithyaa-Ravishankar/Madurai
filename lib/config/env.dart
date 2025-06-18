import 'config.dart';

class Env {
  static String get supabaseUrl => Config.supabaseUrl;
  static String get supabaseAnonKey => Config.supabaseAnonKey;
  static String get supabaseServiceRole => Config.supabaseServiceRole;
  static String get googleMapsApiKey => Config.googleMapsApiKey;
} 