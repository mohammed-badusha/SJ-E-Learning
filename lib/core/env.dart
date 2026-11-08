abstract final class Env {
  static const appName = 'SJ E-Learning';
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );
  static const redirectUrl = String.fromEnvironment(
    'AUTH_REDIRECT_URL',
    defaultValue: 'in.sjacademy.quiz://login-callback',
  );
  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );
  static bool get configured =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
