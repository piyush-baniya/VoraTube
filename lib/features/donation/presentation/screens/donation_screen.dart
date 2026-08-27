import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/donation/donation_config.dart';

/// In-app donation page.
///
/// First checks connectivity (never attempts an offline load). When online it
/// opens the Buy Me a Momo page inside an embedded WebView with a premium
/// glass header, a loading progress overlay, and graceful failure handling.
/// All donation behaviour is isolated from the rest of the application.
class DonationScreen extends StatefulWidget {
  const DonationScreen({super.key, this.connectivityCheck});

  /// Injectable connectivity probe (defaults to [checkInternetConnection]).
  final Future<bool> Function()? connectivityCheck;

  @override
  State<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends State<DonationScreen> {
  late Future<bool> _connectivity;
  WebViewController? _controller;
  bool _webViewLoading = true;
  String? _webViewError;

  @override
  void initState() {
    super.initState();
    final check = widget.connectivityCheck ?? checkInternetConnection;
    _connectivity = check();
  }

  /// Lazily builds (or returns) the WebView controller.
  ///
  /// Only created once connectivity is confirmed so the offline and loading
  /// branches never touch the platform WebView channel.
  WebViewController _ensureController() {
    return _controller ??= _buildController();
  }

  Future<void> _retry(BuildContext context) async {
    setState(() {
      _connectivity = (widget.connectivityCheck ?? checkInternetConnection)();
      _webViewLoading = true;
      _webViewError = null;
      _controller = null;
    });
  }

  WebViewController _buildController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.voidBlack)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _webViewLoading = progress < 100;
              _webViewError = null;
            });
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _webViewLoading = false;
              _webViewError = 'Could not load the donation page.';
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _webViewLoading = false;
              _webViewError = null;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(kBuyMeAMomoUri));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.voidBlack,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              onClose: () => Navigator.of(context).maybePop(),
              onRetry: _webViewError == null ? null : () => _retry(context),
            ),
            Expanded(
              child: FutureBuilder<bool>(
                future: _connectivity,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const _LoadingState();
                  }
                  if (snapshot.data == false) {
                    return _OfflineState(onRetry: () => _retry(context));
                  }
                  if (_webViewError != null) {
                    return _ErrorState(
                      message: _webViewError!,
                      onRetry: () => _retry(context),
                    );
                  }
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: WebViewWidget(controller: _ensureController()),
                      ),
                      if (_webViewLoading)
                        const Positioned.fill(child: _LoadingState()),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose, this.onRetry});

  final VoidCallback onClose;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s3,
        AppTokens.s2,
        AppTokens.s3,
        AppTokens.s2,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            tooltip: 'Close',
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            color: colorScheme.onSurface,
          ),
          const SizedBox(width: AppTokens.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Support the Developer',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  'Buy Me a Momo',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (onRetry != null)
            IconButton(
              onPressed: onRetry,
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh_rounded),
              color: colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: AppColors.voidBlack,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppTokens.s4),
            Text(
              'Checking connection…',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineState extends StatelessWidget {
  const _OfflineState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _MessageState(
      icon: Icons.wifi_off_rounded,
      title: 'No internet connection',
      message:
          'No internet connection. Please connect to the internet to donate.',
      child: FilledButton.tonal(
        onPressed: onRetry,
        child: const Text('Try again'),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _MessageState(
      icon: Icons.error_outline_rounded,
      title: 'Something went wrong',
      message: message,
      child: FilledButton.tonal(
        onPressed: onRetry,
        child: const Text('Reload'),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: AppColors.voidBlack,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: colorScheme.primary),
              ),
              const SizedBox(height: AppTokens.s4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppTokens.s2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppTokens.s5),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
