/// Supabase project connection details.
///
/// The publishable key is safe to ship in client code (it's the public
/// counterpart to the anon role) — access control is enforced by the
/// Postgres row level security policies on the `sources`/`articles` tables,
/// not by keeping this key secret.
class SupabaseConfig {
  static const url = 'https://imswemntldphsibfusal.supabase.co';
  static const publishableKey = 'sb_publishable_7oR53mhr4PNAuvR30Ow6ew_FTJaNyq7';
}
