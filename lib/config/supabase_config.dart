import 'package:supabase_flutter/supabase_flutter.dart';
import 'env.dart';

class SupabaseConfig {
  static const String supabaseUrl = '';
  static const String supabaseAnonKey = '';
  static const String supabaseServiceRole = '';
  static const String redirectUrl = 'madurai://reset-password';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
} 
