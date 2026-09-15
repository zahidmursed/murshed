import 'package:shared_preferences/shared_preferences.dart';

/// `--dart-define=TRIAL_DAYS=30` দিয়ে বানানো APK-তে ট্রায়াল সীমা চালু হয়।
/// 0 (স্বাভাবিক release build)-এ কোনো সীমা থাকে না।
class TrialService {
  static const int trialDays = int.fromEnvironment('TRIAL_DAYS', defaultValue: 0);
  static const _startedAtKey = 'trial_started_at_v1';
  static const _lastSeenAtKey = 'trial_last_seen_at_v1';

  static Future<TrialStatus> load(SharedPreferences prefs) async {
    if (trialDays <= 0) return const TrialStatus.unlimited();

    final now = DateTime.now();
    final storedMillis = prefs.getInt(_startedAtKey);
    final lastSeenMillis = prefs.getInt(_lastSeenAtKey);
    final startedAt = storedMillis == null
        ? now
        : DateTime.fromMillisecondsSinceEpoch(storedMillis);
    if (storedMillis == null) {
      await prefs.setInt(_startedAtKey, now.millisecondsSinceEpoch);
    }

    final expiresAt = startedAt.add(const Duration(days: trialDays));
    // ফোনের সময় অনেকটা পেছনে নিলে trial বাড়িয়ে নেওয়া যাবে না। কয়েক মিনিটের
    // স্বাভাবিক clock correction অনুমোদিত থাকে। app-data clear প্রতিরোধে
    // server-based activation প্রয়োজন।
    final rolledBack = lastSeenMillis != null &&
        now.millisecondsSinceEpoch <
            lastSeenMillis - const Duration(minutes: 5).inMilliseconds;
    await prefs.setInt(_lastSeenAtKey, now.millisecondsSinceEpoch);
    return TrialStatus(
      expiresAt: expiresAt,
      isExpired: rolledBack || !now.isBefore(expiresAt),
    );
  }
}

class TrialStatus {
  final DateTime? expiresAt;
  final bool isExpired;

  const TrialStatus({required this.expiresAt, required this.isExpired});

  const TrialStatus.unlimited() : expiresAt = null, isExpired = false;
}
