import 'package:flutter/foundation.dart';

import 'ui_layout.dart';

/// Declares a customizable component: its stable id, how it may be changed and
/// the defaults a missing or invalid layout entry falls back to.
///
/// Definitions are pure data. They never build widgets, so the registry can be
/// consumed by the normalizer, the editor and persistence without dragging UI
/// code along.
@immutable
class UiComponentDefinition {
  const UiComponentDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.defaultSize,
    this.allowedSizes = const [
      ComponentSize.small,
      ComponentSize.medium,
      ComponentSize.large,
    ],
    this.allowedStyleIds = const [],
    this.defaultStyleId,
    this.canHide = true,
    this.canReorder = true,
    this.canResize = true,
  });

  final String id;
  final String label;
  final String description;
  final ComponentSize defaultSize;
  final List<ComponentSize> allowedSizes;

  /// Registry-declared style variants. An empty list means the component has
  /// one fixed presentation.
  final List<String> allowedStyleIds;
  final String? defaultStyleId;

  final bool canHide;
  final bool canReorder;
  final bool canResize;

  bool supportsSize(ComponentSize size) => allowedSizes.contains(size);

  bool supportsStyle(String? id) => id == null || allowedStyleIds.contains(id);

  /// The style a component uses when no (valid) style is stored.
  String? get effectiveDefaultStyleId =>
      defaultStyleId ??
      (allowedStyleIds.isEmpty ? null : allowedStyleIds.first);

  /// First-run layout for this component.
  ComponentLayout defaultLayout({bool visible = true}) => ComponentLayout(
    id: id,
    visible: visible,
    size: defaultSize,
    styleId: effectiveDefaultStyleId,
  );
}

/// The set of customizable components for one or more screens, in default
/// order. Order in [definitions] is the canonical fallback order.
@immutable
class UiComponentRegistry {
  const UiComponentRegistry(this.definitions);

  final List<UiComponentDefinition> definitions;

  UiComponentDefinition? definitionFor(String id) {
    for (final d in definitions) {
      if (d.id == id) return d;
    }
    return null;
  }

  bool contains(String id) => definitionFor(id) != null;

  List<String> get ids => [for (final d in definitions) d.id];
}

/// Screen id for the Home dashboard.
const String kHomeScreenId = 'home';

/// Screen id for the full-screen Now Playing player.
const String kPlayerScreenId = 'player';

/// Screen id for the compact Now Playing bar.
const String kMiniScreenId = 'mini';

/// Screen id for the flagship Equalizer screen.
const String kEqualizerScreenId = 'equalizer';

/// The ids of every customizable screen.
const List<String> kLayoutScreenIds = [
  kHomeScreenId,
  kPlayerScreenId,
  kMiniScreenId,
  kEqualizerScreenId,
];

/// Home dashboard components, in the original pre-customization order so the
/// default profile reproduces the existing UI exactly.
const UiComponentRegistry homeComponentRegistry = UiComponentRegistry([
  UiComponentDefinition(
    id: 'home.continueListening',
    label: 'Continue Listening',
    description: 'Resume the track you were last playing',
    defaultSize: ComponentSize.medium,
    allowedStyleIds: ['hero', 'compact'],
    defaultStyleId: 'hero',
  ),
  UiComponentDefinition(
    id: 'home.listeningInsights',
    label: 'Your Listening',
    description: 'Play counts, listening time and your most played track',
    defaultSize: ComponentSize.medium,
    allowedStyleIds: ['full', 'chips'],
    defaultStyleId: 'full',
  ),
  UiComponentDefinition(
    id: 'home.playlists',
    label: 'Playlists',
    description: 'Your playlists with a quick create action',
    defaultSize: ComponentSize.medium,
    allowedStyleIds: ['carousel', 'grid'],
    defaultStyleId: 'carousel',
  ),
  UiComponentDefinition(
    id: 'home.allSongs',
    label: 'All Songs',
    description: 'A preview of the songs in your library',
    defaultSize: ComponentSize.medium,
    // The library preview is the dashboard's anchor: it stays visible, but it
    // can still be moved or resized.
    canHide: false,
  ),
]);

/// Full player components, in the default rendering order.
///
/// The player is composed of two anchored zones: the top zone holds artwork
/// and song info (dismissable, scrollable) while the bottom zone holds the
/// progress bar and the control rows (fixed, never dismissed with the swipe).
const UiComponentRegistry playerComponentRegistry = UiComponentRegistry([
  UiComponentDefinition(
    id: 'player.artwork',
    label: 'Artwork',
    description: 'The rotating cover art of the current track',
    defaultSize: ComponentSize.medium,
    allowedStyleIds: ['standard', 'immersive'],
    defaultStyleId: 'standard',
    // The artwork is the player's centerpiece and is always shown.
    canHide: false,
  ),
  UiComponentDefinition(
    id: 'player.trackInfo',
    label: 'Song Info',
    description: 'The title and artist of the current track',
    defaultSize: ComponentSize.medium,
  ),
  UiComponentDefinition(
    id: 'player.progress',
    label: 'Progress Bar',
    description: 'Track position and the seek bar',
    defaultSize: ComponentSize.medium,
    // The progress bar always stays on screen so seeking is always possible.
    canHide: false,
    canReorder: false,
  ),
  UiComponentDefinition(
    id: 'player.secondaryControls',
    label: 'Playback Modes',
    description: 'Shuffle, repeat and playback effects',
    defaultSize: ComponentSize.medium,
    canResize: false,
  ),
  UiComponentDefinition(
    id: 'player.primaryControls',
    label: 'Playback Controls',
    description: 'Previous, play and next with ten second seek',
    defaultSize: ComponentSize.medium,
    // The transport controls always stay on screen.
    canHide: false,
  ),
]);

/// Mini player components, in the default rendering order. The mini bar is a
/// single-row surface: its blocks are never reordered.
const UiComponentRegistry miniComponentRegistry = UiComponentRegistry([
  UiComponentDefinition(
    id: 'mini.artwork',
    label: 'Artwork',
    description: 'The cover art of the current track',
    defaultSize: ComponentSize.medium,
    canHide: false,
    canReorder: false,
    canResize: true,
  ),
  UiComponentDefinition(
    id: 'mini.trackInfo',
    label: 'Song Info',
    description: 'The title and artist of the current track',
    defaultSize: ComponentSize.medium,
    canReorder: false,
  ),
  UiComponentDefinition(
    id: 'mini.progress',
    label: 'Progress Bar',
    description: 'Track position as a thin line',
    defaultSize: ComponentSize.medium,
    allowedStyleIds: ['thin', 'bold'],
    defaultStyleId: 'thin',
    canHide: false,
    canReorder: false,
    canResize: false,
  ),
  UiComponentDefinition(
    id: 'mini.controls',
    label: 'Playback Controls',
    description: 'Previous, play and next buttons',
    defaultSize: ComponentSize.medium,
    canHide: false,
    canReorder: false,
  ),
  UiComponentDefinition(
    id: 'mini.secondaryControls',
    label: 'Shuffle',
    description: 'Toggle shuffle from the bar',
    defaultSize: ComponentSize.medium,
    canReorder: false,
    canResize: false,
  ),
]);

/// Equalizer components, in the default rendering order.
///
/// The interactive curve is the screen's anchor: it can never be hidden,
/// reordered or resized, so however the rest of the screen is customised the
/// graph always stays reachable and usable.
const UiComponentRegistry equalizerComponentRegistry = UiComponentRegistry([
  UiComponentDefinition(
    id: 'equalizer.nowPlaying',
    label: 'Now Playing',
    description: 'The artwork and track the curve is shaping',
    defaultSize: ComponentSize.medium,
  ),
  UiComponentDefinition(
    id: 'equalizer.curve',
    label: 'EQ Curve',
    description: 'The interactive 10-band curve',
    defaultSize: ComponentSize.medium,
    allowedSizes: [ComponentSize.medium, ComponentSize.large],
    canHide: false,
    canReorder: false,
    canResize: false,
  ),
  UiComponentDefinition(
    id: 'equalizer.presets',
    label: 'Presets',
    description: 'Built-in and saved one-tap curves',
    defaultSize: ComponentSize.medium,
  ),
  UiComponentDefinition(
    id: 'equalizer.quickControls',
    label: 'Quick Controls',
    description: 'Sub Bass, Bass, Vocal Clarity and Treble macros',
    defaultSize: ComponentSize.medium,
  ),
  UiComponentDefinition(
    id: 'equalizer.bandControls',
    label: 'Band Controls',
    description: 'Fine-tune each of the ten bands',
    defaultSize: ComponentSize.medium,
  ),
  UiComponentDefinition(
    id: 'equalizer.preamp',
    label: 'Preamp',
    description: 'Output gain and clipping headroom',
    defaultSize: ComponentSize.medium,
  ),
  UiComponentDefinition(
    id: 'equalizer.processing',
    label: 'Processing',
    description: 'ReplayGain, speed and sound controls',
    defaultSize: ComponentSize.medium,
  ),
]);

/// Component ids that belong to the player's dismissable top zone. Anything
/// not listed belongs to the fixed bottom zone.
const List<String> kPlayerTopZoneIds = ['player.artwork', 'player.trackInfo'];

/// Reorders the given player components back into their anchored zones while
/// keeping the relative order inside each zone: artwork and song info first,
/// then the progress bar and the control rows.
List<ComponentLayout> groupPlayerZones(List<ComponentLayout> components) {
  final top = <ComponentLayout>[];
  final bottom = <ComponentLayout>[];
  for (final c in components) {
    (kPlayerTopZoneIds.contains(c.id) ? top : bottom).add(c);
  }
  return [...top, ...bottom];
}
