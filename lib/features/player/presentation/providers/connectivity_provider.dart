import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reactive connectivity stream provided by the platform.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// Whether the device currently has network connectivity that could reach the
/// internet (Wi-Fi or mobile data).  Defaults to `true` while the initial
/// platform check is in flight so the app attempts an online lyrics fetch on
/// first launch rather than incorrectly assuming offline.
final isOnlineProvider = Provider<bool>((ref) {
  final asyncResult = ref.watch(connectivityProvider);
  return asyncResult.when(
    data: (results) => results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn,
    ),
    loading: () => true,
    error: (e, st) => true,
  );
});
