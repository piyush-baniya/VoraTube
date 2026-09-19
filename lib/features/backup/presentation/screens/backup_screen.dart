import '../../../library/data/library_repository.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../library/presentation/providers/library_providers.dart';
import '../../../library/presentation/providers/library_view_providers.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../../player/presentation/providers/equalizer_providers.dart';
import '../../../lyrics/presentation/providers/lyrics_providers.dart';
import '../../data/backup_format.dart';
import '../../data/backup_service.dart';
import '../../data/backup_storage.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final _storage = const BackupStorage();
  bool _busy = false;
  String? _directory;
  String? _location;
  String? _last;
  String? _message;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(libraryRepositoryProvider);
    final dir = await repo.kvGet('backup.directory');
    final last = await repo.kvGet('backup.lastSuccess');
    String? name;
    try {
      if (dir != null) name = await _storage.displayName(dir);
    } catch (_) {
      /* grant may have expired */
    }
    if (mounted) {
      setState(() {
        _directory = dir;
        _location = name;
        _last = last;
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not complete: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _chooseLocation() async {
    final dir = await _storage.pickDirectory();
    if (dir == null) return false;
    await ref.read(libraryRepositoryProvider).kvSet('backup.directory', dir);
    _directory = dir;
    await _load();
    return true;
  }

  Future<void> _backup() async {
    if (_directory == null || !await _storage.hasPermission(_directory!)) {
      if (!await _chooseLocation()) return;
    }
    final service = BackupService(ref.read(appDatabaseProvider));
    final version = await PackageInfo.fromPlatform();
    final payload = await service.capture(
      '${version.version}+${version.buildNumber}',
    );
    final bytes = composeBackupBytes(payload.toJson());
    service.read(bytes);
    final name = backupFileNameFor(payload.createdAt);
    final uri = await _storage.writeFile(
      dirUri: _directory!,
      fileName: name,
      bytes: bytes,
    );
    final reopened = await _storage.readFile(uri);
    service.read(reopened);
    if (bytes.length != reopened.length || !_equalBytes(bytes, reopened)) {
      throw StateError('Written backup differs');
    }
    final at = DateTime.now().toLocal().toString();
    await ref.read(libraryRepositoryProvider).kvSet('backup.lastSuccess', at);
    if (mounted) {
      setState(() {
        _last = at;
        _message = 'Backup complete and verified.\n$name';
      });
    }
  }

  bool _equalBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _read({required bool restore}) async {
    final uri = await _storage.pickBackupFile();
    if (uri == null) return;
    final bytes = await _storage.readFile(uri);
    final service = BackupService(ref.read(appDatabaseProvider));
    final payload = service.read(bytes);
    final mapping = await service.plan(payload);
    final summary =
        '${payload.playlists.length} playlists · ${payload.favoritesCount} favorites\n'
        '${payload.history.length} history entries · ${payload.kv.length} settings\n'
        '${mapping.matchedCount} songs matched · ${mapping.unresolvedCount} unresolved';
    if (!mounted) return;
    if (!restore) {
      setState(() => _message = 'Backup verified.\n$summary');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Text(
          '$summary\n\nCurrent playlists, favorites, history and settings will be replaced. '
          'Missing song references are retained. Music files are untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await service.restore(bytes, await getTemporaryDirectory());
    if (!mounted) return;
    ref.invalidate(appSettingsProvider);
    ref.invalidate(audioSettingsProvider);
    ref.invalidate(librarySettingsProvider);
    ref.invalidate(appearanceSettingsProvider);
    ref.invalidate(equalizerSettingsProvider);
    ref.invalidate(currentLyricsProvider);
    ref.read(libraryRefreshTickProvider.notifier).state++;
    ref.read(statsRefreshTickProvider.notifier).state++;
    ref.read(favoritesRefreshTickProvider.notifier).state++;
    setState(
      () => _message =
          'Restore complete. ${result.matchedCount} songs matched; '
          '${result.unresolvedCount} unresolved.',
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Save a .vtb file in a folder you own. Backups contain your app data, not music files.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : () => _run(_backup),
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Back Up Now'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _run(() => _read(restore: true)),
            child: const Text('Restore Backup'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _run(() => _read(restore: false)),
            child: const Text('Verify Backup'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Backup location'),
            subtitle: Text(_location ?? 'Choose a folder'),
            trailing: TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      await _chooseLocation();
                    }),
              child: const Text('Change location'),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Last successful backup'),
            subtitle: Text(_last ?? 'No backup yet'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_message!),
            ),
        ],
      ),
    ),
  );
}