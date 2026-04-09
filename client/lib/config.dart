/// Runtime configuration injected via --dart-define at build time.
///
/// Development:
///   flutter run --dart-define=API_URL=http://localhost:8080
///
/// Production:
///   flutter build web --dart-define=API_URL=https://api.paintcoop.thkali.dev
abstract final class Config {
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8080',
  );

  // Derives WebSocket URL from apiUrl (http → ws, https → wss)
  static String get wsUrl => apiUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');
}
