/// Supabase connection settings.
///
/// Both values are safe to ship in the app: the URL is public and the
/// publishable key (`sb_publishable_…`, the successor to the anon key) is
/// designed for client use — Row-Level Security, not key secrecy, is what
/// protects the data. They default to the project's values but can be
/// overridden at build time with:
///   --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_KEY=…
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bsvhldkuscurztywhhaa.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_aNKwEQrdnfD-9F1OjP49Gw_dFWH8x_R',
  );
}
