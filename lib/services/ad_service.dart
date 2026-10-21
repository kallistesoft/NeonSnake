/// Ad placements. Screens only use this interface, so the AdMob (mobile) and
/// portal SDK (web) implementations can be swapped in without touching gameplay.
abstract class AdService {
  /// Between levels. Implementations enforce the frequency cap.
  Future<void> showInterstitial();

  /// Rewarded video; returns true if the player earned the reward.
  Future<bool> showRewarded();
}

/// Development stand-in: no ads, rewards always granted.
class NoAdService implements AdService {
  const NoAdService();

  @override
  Future<void> showInterstitial() async {}

  @override
  Future<bool> showRewarded() async => true;
}
