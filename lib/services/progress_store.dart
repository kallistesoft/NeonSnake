import 'package:shared_preferences/shared_preferences.dart';

class ProgressStore {
  ProgressStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<ProgressStore> open() async => ProgressStore(await SharedPreferences.getInstance());

  int get bestScore => _prefs.getInt('best') ?? 0;
  int get bestLevel => _prefs.getInt('bestLevel') ?? 0;
  int get bossesBeaten => _prefs.getInt('bosses') ?? 0;

  /// First level of the stretch the player last reached (1, 6, 11...).
  int get checkpoint => _prefs.getInt('checkpoint') ?? 1;

  /// Records a level reached; moves the checkpoint forward past beaten bosses.
  Future<void> reachLevel(int level, int checkpoint) async {
    if (level > bestLevel) await _prefs.setInt('bestLevel', level);
    if (checkpoint > this.checkpoint) await _prefs.setInt('checkpoint', checkpoint);
  }

  Future<void> bossBeaten() => _prefs.setInt('bosses', bossesBeaten + 1);

  /// Returns true for a new best score.
  Future<bool> recordScore(int score) async {
    if (score <= bestScore) return false;
    await _prefs.setInt('best', score);
    return true;
  }

  bool get muted => _prefs.getBool('muted') ?? false;
  Future<void> setMuted(bool value) => _prefs.setBool('muted', value);
}
