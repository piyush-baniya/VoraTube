import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/presentation/providers/library_providers.dart';
import 'premium_models.dart';

/// The single, authoritative Premium / ads entitlement state for the whole app.
///
/// Every VoraTube ad placement must depend on [premiumProvider] so there is
/// exactly one source of truth:
///
/// ```text
/// if premiumActivated:
///     do not render/load ads
/// else:
///     ads may render
/// ```
///
/// When Premium is active every ad widget simply does not build, and any loaded
/// ad instance owned by a placement is disposed because the placement widget
/// leaves the tree.
class PremiumController extends StateNotifier<PremiumEntitlement> {
  PremiumController(this._repository) : super(PremiumEntitlement.inactive) {
    _load();
  }

  final dynamic _repository;

  Future<void> _load() async {
    try {
      final stored = await _repository.kvGet(PremiumKeys.activated) as String?;
      if (stored == 'true' && mounted) {
        state = PremiumEntitlement.active;
      }
    } catch (_) {
      // A read failure falls back to the safe default (Premium inactive).
    }
  }

  /// Whether Premium (and therefore ad-free browsing) is currently active.
  bool get isPremium => state == PremiumEntitlement.active;

  /// Promotes the user to Premium given the already-validated code, persists
  /// the entitlement and disables all ads immediately.
  ///
  /// Callers validate the code with [PremiumCodeValidator] before invoking
  /// this; it does not re-persist the code itself.
  Future<void> activate() async {
    if (isPremium) return;
    state = PremiumEntitlement.active;
    try {
      await _repository.kvSet(PremiumKeys.activated, 'true');
    } catch (_) {
      // Persistence failure still keeps the in-memory entitlement active for
      // this session; the next launch simply falls back to the default.
    }
  }

  /// Revokes Premium, re-enables ads and persists the new state.
  Future<void> deactivate() async {
    if (!isPremium) return;
    state = PremiumEntitlement.inactive;
    try {
      await _repository.kvSet(PremiumKeys.activated, 'false');
    } catch (_) {
      // Same session-end persistence semantics as activation.
    }
  }
}

final premiumProvider =
    StateNotifierProvider<PremiumController, PremiumEntitlement>((ref) {
      final repo = ref.watch(libraryRepositoryProvider);
      return PremiumController(repo);
    });

/// Convenience boolean mirroring whether Premium is active.
final isPremiumProvider = Provider<bool>((ref) {
  return ref.watch(
    premiumProvider.select((p) => p == PremiumEntitlement.active),
  );
});
