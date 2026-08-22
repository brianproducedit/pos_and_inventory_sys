class DemoConfig {
  /// Defines whether the app is running in a fully offline demo state without a backend.
  /// Default is true so release APKs don't rely on missing backend servers.
  static const bool isDemoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: true);
}
