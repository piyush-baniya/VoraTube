import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../app/theme/app_tokens.dart';
import 'ads_config.dart';
import 'premium_providers.dart';

/// A small, unobtrusive AdMob banner that obeys VoraTube's centralized Premium
/// state.
///
/// * When Premium is active this widget builds to [SizedBox.shrink] and the
///   underlying [BannerAd] (if any) is disposed because the stateful element
///   leaves the tree — so no ad shows and no ad request is made.
/// * When Premium is off it loads a banner and shows a compact, thematically
///   muted placeholder while loading so the layout does not jump.
/// * On load/display failure the banner collapses gracefully to nothing rather
///   than reserving a blank area or crashing.
///
/// Height is fixed while an ad is present ([bannerHeight]) so activation or
/// de-activation never causes jarring layout jumps.
class VoraTubeBannerAd extends ConsumerStatefulWidget {
  const VoraTubeBannerAd({super.key});

  /// Fixed display height used while a banner is loaded or loading.
  static const double bannerHeight = 56;

  @override
  ConsumerState<VoraTubeBannerAd> createState() => _VoraTubeBannerAdState();
}

class _VoraTubeBannerAdState extends ConsumerState<VoraTubeBannerAd> {
  BannerAd? _bannerAd;
  bool _loaded = false;
  bool _loadFailed = false;
  bool _disposed = false;

  bool get _premiumActive => ref.read(isPremiumProvider);

  @override
  void initState() {
    super.initState();
    ref.listen(isPremiumProvider, (previous, next) {
      _handlePremiumChange(next);
    });
    if (!_premiumActive) {
      _loadAd();
    }
  }

  @override
  void didUpdateWidget(covariant VoraTubeBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the widget rebuilds we simply re-read the premium state; listeners
    // above already keep the banner in sync.
  }

  void _handlePremiumChange(bool premium) {
    if (premium) {
      _disposeAd();
      if (mounted) {
        setState(() {
          _loaded = false;
          _loadFailed = false;
        });
      }
    } else if (!premium && _bannerAd == null && !_loadFailed) {
      _loadAd();
    }
  }

  void _loadAd() {
    if (_premiumActive || _disposed) return;
    final adUnitId = VoraTubeAds.bannerAndroidId;
    late BannerAd ad;
    ad = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (_disposed || _premiumActive) {
            ad.dispose();
            return;
          }
          if (mounted) {
            setState(() {
              _bannerAd = ad;
              _loaded = true;
              _loadFailed = false;
            });
          }
        },
        onAdFailedToLoad: (Ad failedAd, LoadAdError error) {
          failedAd.dispose();
          if (!_disposed && mounted) {
            setState(() => _loadFailed = true);
          }
        },
      ),
    );
    ad.load();
  }

  void _disposeAd() {
    final ad = _bannerAd;
    _bannerAd = null;
    ad?.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _disposeAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final premium = ref.watch(isPremiumProvider);
    if (premium || _loadFailed) {
      // Premium active, or the ad failed to load: collapse to nothing so we
      // neither show ads nor reserve a blank area.
      return const SizedBox.shrink();
    }

    if (!_loaded || _bannerAd == null) {
      // Loading placeholder: a short, muted strip so the area is not empty but
      // stays low-profile and never dominates.
      return Container(
        height: VoraTubeBannerAd.bannerHeight,
        alignment: Alignment.center,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.onSurfaceVariant
                .withValues(alpha: 0.35),
          ),
        ),
      );
    }

    return Container(
      height: VoraTubeBannerAd.bannerHeight,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // Blend the native ad surface into VoraTube's card styling so it
        // reads as a small part of the UI, not a foreign insert.
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(AppTokens.rMd),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant
              .withValues(alpha: 0.25),
          width: AppTokens.borderHairline,
        ),
      ),
      child: SizedBox(width: 320, height: 48, child: AdWidget(ad: _bannerAd!)),
    );
  }
}
