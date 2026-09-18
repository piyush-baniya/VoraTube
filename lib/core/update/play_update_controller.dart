import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/library/data/library_repository.dart';
import '../../features/library/presentation/providers/library_providers.dart';
import 'play_update.dart';

class RepositoryPlayUpdateStore implements PlayUpdateStore {
  RepositoryPlayUpdateStore(this._repository);

  final LibraryRepository _repository;

  @override
  Future<String?> read(String key) => _repository.kvGet(key);

  @override
  Future<void> write(String key, String value) => _repository.kvSet(key, value);
}

final playUpdateApiProvider = Provider<PlayUpdateApi>(
  (ref) => MethodChannelPlayUpdateApi(),
);

final playUpdateStoreProvider = Provider<PlayUpdateStore>(
  (ref) => RepositoryPlayUpdateStore(ref.watch(libraryRepositoryProvider)),
);

final playUpdateControllerProvider =
    NotifierProvider<PlayUpdateController, PlayUpdateInfo>(
      PlayUpdateController.new,
    );

class PlayUpdateController extends Notifier<PlayUpdateInfo> {
  static const _dismissedDayKey = 'play_update_dismissed_day';

  bool _checkedThisLaunch = false;
  bool _dismissedToday = false;

  @override
  PlayUpdateInfo build() {
    final api = ref.watch(playUpdateApiProvider);
    ref.onDispose(() => api.onStateChange = null);
    api.onStateChange = (update) {
      switch (update.status) {
        case PlayUpdateStatus.downloading:
        case PlayUpdateStatus.downloaded:
        case PlayUpdateStatus.installing:
        case PlayUpdateStatus.failed:
          state = update.copyWith(promptToken: state.promptToken);
        default:
          break;
      }
    };
    return const PlayUpdateInfo();
  }

  /// Returns the resulting update state. [manual] checks bypass the
  /// once-per-launch and persisted-dismissal gates.
  Future<PlayUpdateInfo> checkForUpdate({bool manual = false}) async {
    if (manual) {
      return _publish(await _query(), allowNoUpdate: true);
    }
    if (_checkedThisLaunch || _dismissedToday) return state;
    _checkedThisLaunch = true;
    if (await _dismissedDay() == _today()) {
      _dismissedToday = true;
      return state;
    }
    return _publish(await _query());
  }

  /// Publishes a query result, bumping the prompt token only when the host
  /// should present a sheet (an available flexible update, or an update that
  /// is already running). A plain "no update" result clears the prompt.
  PlayUpdateInfo _publish(PlayUpdateInfo info, {bool allowNoUpdate = false}) {
    if (info.canPrompt || _inProgress(info.status)) {
      return state = info.copyWith(promptToken: state.promptToken + 1);
    }
    return state = allowNoUpdate
        ? info
        : const PlayUpdateInfo(status: PlayUpdateStatus.notAvailable);
  }

  /// Re-queries Google Play after a resume. A running or downloaded update is
  /// restored verbatim (the user must still be able to finish installing);
  /// a fresh availability prompt only surfaces when it was not dismissed.
  Future<PlayUpdateInfo> syncOnResume() async {
    if (!_checkedThisLaunch) return checkForUpdate();
    final info = await _query();
    if (_inProgress(info.status) || (!_dismissedToday && info.canPrompt)) {
      // Passive restore: keep the current token so no extra sheet is opened.
      state = info.copyWith(promptToken: state.promptToken);
    }
    return state;
  }

  Future<void> startUpdate() async {
    final started = await ref.read(playUpdateApiProvider).startFlexibleUpdate();
    switch (started) {
      case PlayUpdateStatus.downloading:
        state = state.copyWith(status: PlayUpdateStatus.downloading);
      case PlayUpdateStatus.downloaded:
        state = state.copyWith(status: PlayUpdateStatus.downloaded);
      case PlayUpdateStatus.canceled:
        // The user declined Play's confirmation dialog: keep the prompt open.
        break;
      case _:
        state = state.copyWith(status: PlayUpdateStatus.failed);
    }
  }

  Future<void> completeUpdate() async {
    try {
      await ref.read(playUpdateApiProvider).completeUpdate();
      state = state.copyWith(status: PlayUpdateStatus.installing);
    } catch (_) {}
  }

  Future<void> dismiss() async {
    _dismissedToday = true;
    try {
      await ref.read(playUpdateStoreProvider).write(_dismissedDayKey, _today());
    } catch (_) {}
    state = state.copyWith(status: PlayUpdateStatus.notAvailable);
  }

  Future<PlayUpdateInfo> _query() async {
    try {
      return await ref.read(playUpdateApiProvider).checkForUpdate();
    } catch (_) {
      return const PlayUpdateInfo(status: PlayUpdateStatus.failed);
    }
  }

  bool _inProgress(PlayUpdateStatus status) =>
      status == PlayUpdateStatus.downloading ||
      status == PlayUpdateStatus.downloaded ||
      status == PlayUpdateStatus.installing;

  Future<String?> _dismissedDay() async {
    try {
      return await ref.read(playUpdateStoreProvider).read(_dismissedDayKey);
    } catch (_) {
      return null;
    }
  }

  String _today() => DateTime.now().toIso8601String().substring(0, 10);
}
