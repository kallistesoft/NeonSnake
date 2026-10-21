import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

enum Sfx { eat, golden, boost, poison, charge, die, enemyDown, bossHit, warning, bossDown, levelClear, gameOver }

abstract class SoundService {
  bool get muted;
  Future<void> setMuted(bool value);
  void play(Sfx sfx);
}

class NoSound implements SoundService {
  @override
  bool muted = false;

  final played = <Sfx>[];

  @override
  Future<void> setMuted(bool value) async => muted = value;

  @override
  void play(Sfx sfx) {
    if (!muted) played.add(sfx);
  }
}

/// Short effects from assets/sfx (synthesized by tools/make_sfx.py), one small player pool each.
class AudioSoundService implements SoundService {
  AudioSoundService({required bool muted, required Future<void> Function(bool) persist})
      : _muted = muted, // ignore: prefer_initializing_formals
        _persist = persist; // ignore: prefer_initializing_formals

  bool _muted;
  final Future<void> Function(bool) _persist;
  final _pools = <Sfx, Future<AudioPool>>{};

  static const _volume = {Sfx.eat: 0.5, Sfx.enemyDown: 0.6};

  @override
  bool get muted => _muted;

  @override
  Future<void> setMuted(bool value) async {
    _muted = value;
    await _persist(value);
  }

  @override
  void play(Sfx sfx) {
    if (_muted) return;
    final pool = _pools.putIfAbsent(sfx, () => AudioPool.createFromAsset(path: 'sfx/${sfx.name}.wav', maxPlayers: 4));
    unawaited(() async {
      try {
        await (await pool).start(volume: _volume[sfx] ?? 0.8);
      } catch (_) {
        // Browsers can refuse audio before the first user gesture; a missed effect is fine.
      }
    }());
  }
}
