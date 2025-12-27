import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Simple application-wide timezone helper.
///
/// Initialize early (before UI starts) with `await TimeService.instance.initialize();`.
/// Use `TimeService.instance.now()` and `TimeService.instance.format(dt)` to get
/// Zimbabwe (Africa/Harare) based times and formatted strings.
class TimeService {
  TimeService._privateConstructor();
  static final TimeService instance = TimeService._privateConstructor();

  late tz.Location _location;
  bool _initialized = false;

  /// Initialize timezone database and set default location.
  Future<void> initialize({String tzLocation = 'Africa/Harare'}) async {
    if (_initialized) return;
    // load TZ database
    tzdata.initializeTimeZones();
    _location = tz.getLocation(tzLocation);
    tz.setLocalLocation(_location);
    _initialized = true;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      // Synchronous initialization fallback (helps tests that don't call main())
      try {
        tzdata.initializeTimeZones();
        _location = tz.getLocation('Africa/Harare');
        tz.setLocalLocation(_location);
        _initialized = true;
      } catch (e) {
        throw Exception(
            'TimeService not initialized. Call initialize() early in startup.');
      }
    }
  }

  /// Returns the current instant in the configured timezone.
  tz.TZDateTime now() {
    _ensureInitialized();
    return tz.TZDateTime.now(_location);
  }

  /// Format a DateTime (or TZDateTime) using pattern (default: 'yyyy-MM-dd HH:mm:ss').
  String formatDateTime(DateTime dt, {String pattern = 'yyyy-MM-dd HH:mm:ss'}) {
    _ensureInitialized();
    final tzdt = tz.TZDateTime.from(dt.toUtc(), _location);
    return DateFormat(pattern).format(tzdt);
  }

  /// Format the current time.
  String formatNow({String pattern = 'yyyy-MM-dd HH:mm:ss'}) =>
      formatDateTime(now(), pattern: pattern);

  /// Return ISO 8601 string for the current timezone-aware time.
  String nowIsoString() => now().toIso8601String();
}
