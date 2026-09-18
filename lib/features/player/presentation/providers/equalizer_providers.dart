import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/audio_effects.dart';
import '../../../library/data/library_repository.dart';
import '../../../library/presentation/providers/library_providers.dart';
import '../../../settings/data/settings_models.dart';
import '../../data/equalizer_settings.dart';

/// Loads, edits and persists the equalizer UI preferences (mode and the user's
/// saved curves). The curve that is actually applied to the player still lives
/// in `AudioSettings`; saving or selecting a preset here is paired with an
/// `audioSettingsProvider` update by the equalizer screen so the engine never
/// reads a second, competing source of truth.
class EqualizerSettingsController extends StateNotifier<EqualizerUiSettings> {
  EqualizerSettingsController(this._repository)
    : super(const EqualizerUiSettings()) {
    _load();
  }

  final LibraryRepository _repository;

  Future<void> _load() async {
    try {
      final json = await _repository.kvGet(SettingsKeys.equalizer);
      if (json != null && mounted) {
        state = EqualizerUiSettings.tryDecode(json);
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    await _repository.kvSet(SettingsKeys.equalizer, state.encode());
  }

  String _newId() =>
      'eq-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  Future<void> setMode(EqMode mode) async {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode);
    await _persist();
  }

  /// Saves [levels] as a new named preset and returns it (null on empty name).
  EqCustomPreset? savePreset(String name, List<double> levels) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final preset = EqCustomPreset(
      id: _newId(),
      name: trimmed,
      levels: normalizeEqLevels(levels),
    );
    state = state.copyWith(
      presets: [...state.presets, preset],
      selectedPresetId: preset.id,
    );
    _persist();
    return preset;
  }

  Future<void> renamePreset(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(
      presets: [
        for (final preset in state.presets)
          if (preset.id == id) preset.copyWith(name: trimmed) else preset,
      ],
    );
    await _persist();
  }

  Future<void> updatePresetLevels(String id, List<double> levels) async {
    state = state.copyWith(
      presets: [
        for (final preset in state.presets)
          if (preset.id == id) preset.copyWith(levels: levels) else preset,
      ],
    );
    await _persist();
  }

  Future<void> duplicatePreset(String id) async {
    final source = state.presetById(id);
    if (source == null) return;
    final copy = EqCustomPreset(
      id: _newId(),
      name: '${source.name} copy',
      levels: List<double>.of(source.levels),
    );
    state = state.copyWith(
      presets: [...state.presets, copy],
      selectedPresetId: copy.id,
    );
    await _persist();
  }

  Future<void> deletePreset(String id) async {
    state = state.copyWith(
      presets: [
        for (final preset in state.presets)
          if (preset.id != id) preset,
      ],
      clearSelectedPreset: state.selectedPresetId == id,
    );
    await _persist();
  }

  Future<void> reorderPresets(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= state.presets.length) return;
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final presets = List<EqCustomPreset>.of(state.presets);
    final moved = presets.removeAt(oldIndex);
    presets.insert(target.clamp(0, presets.length), moved);
    state = state.copyWith(presets: presets);
    await _persist();
  }

  Future<void> togglePin(String id) async {
    state = state.copyWith(
      presets: [
        for (final preset in state.presets)
          if (preset.id == id)
            preset.copyWith(pinned: !preset.pinned)
          else
            preset,
      ],
    );
    await _persist();
  }

  Future<void> selectPreset(String id) async {
    state = state.copyWith(selectedPresetId: id);
    await _persist();
  }

  Future<void> clearSelectedPreset() async {
    if (state.selectedPresetId == null) return;
    state = state.copyWith(clearSelectedPreset: true);
    await _persist();
  }
}

final equalizerSettingsProvider =
    StateNotifierProvider<EqualizerSettingsController, EqualizerUiSettings>((
      ref,
    ) {
      final repository = ref.watch(libraryRepositoryProvider);
      return EqualizerSettingsController(repository);
    });
