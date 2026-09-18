import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/ui_customization/ui_component_registry.dart';
import 'package:vora_tube/core/ui_customization/ui_layout.dart';
import 'package:vora_tube/core/ui_customization/ui_layout_normalizer.dart';
import 'package:vora_tube/features/customization/data/layout_repository.dart';

class _MemoryStore implements LayoutKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

ScreenLayout _screen(List<ComponentLayout> components) =>
    ScreenLayout(screenId: kHomeScreenId, components: components);

List<String> _ids(ScreenLayout layout) => [
  for (final c in layout.components) c.id,
];

void main() {
  group('layoutVariantForSize', () {
    const cases = <(Size, LayoutVariant)>[
      (Size(400, 800), LayoutVariant.portrait),
      (Size(800, 400), LayoutVariant.landscape),
      (Size(899, 1600), LayoutVariant.portrait),
      (Size(1600, 899), LayoutVariant.landscape),
      (Size(900, 900), LayoutVariant.largeScreen),
      (Size(1200, 1600), LayoutVariant.largeScreen),
      (Size(2560, 1440), LayoutVariant.largeScreen),
    ];
    for (final (size, expected) in cases) {
      test('$size resolves to ${expected.name}', () {
        expect(layoutVariantForSize(size), expected);
      });
    }
  });

  group('ComponentLayout serialization', () {
    test('round-trips every field including a null style', () {
      const a = ComponentLayout(
        id: 'home.playlists',
        visible: false,
        size: ComponentSize.large,
        styleId: 'grid',
      );
      const b = ComponentLayout(id: 'home.allSongs');
      expect(ComponentLayout.tryFromJson(a.toJson()), a);
      expect(ComponentLayout.tryFromJson(b.toJson()), b);
    });

    test('repairs malformed fields to safe defaults', () {
      final decoded = ComponentLayout.tryFromJson({
        'id': 'home.playlists',
        'visible': 'nope',
        'size': 'gigantic',
        'style': 42,
      });
      expect(decoded, const ComponentLayout(id: 'home.playlists'));
    });

    test('rejects entries without a usable id', () {
      expect(ComponentLayout.tryFromJson(null), isNull);
      expect(ComponentLayout.tryFromJson('x'), isNull);
      expect(ComponentLayout.tryFromJson({'id': ''}), isNull);
    });
  });

  group('LayoutProfile serialization', () {
    test('round-trips a default profile', () {
      final profile = defaultLayoutProfile(homeComponentRegistry);
      final decoded = LayoutProfile.tryDecode(profile.encode());
      expect(decoded, profile);
      expect(decoded!.schemaVersion, kUiLayoutSchemaVersion);
    });

    test('returns null for corrupt or unusable payloads', () {
      expect(LayoutProfile.tryDecode('not json'), isNull);
      expect(LayoutProfile.tryDecode('[]'), isNull);
      expect(LayoutProfile.tryDecode(jsonEncode({'v': '1'})), isNull);
      expect(LayoutProfile.tryDecode(jsonEncode({'v': 1})), isNull);
      expect(
        LayoutProfile.tryDecode(jsonEncode({'v': 1, 'layouts': []})),
        isNull,
      );
    });

    test('falls back to portrait for an unknown variant name', () {
      final raw = jsonEncode({
        'v': 1,
        'preset': 'standard',
        'layouts': [
          {
            'variant': 'watch',
            'screen': kHomeScreenId,
            'components': [
              {'id': 'home.allSongs', 'visible': true, 'size': 'medium'},
            ],
          },
        ],
      });
      final decoded = LayoutProfile.tryDecode(raw);
      expect(
        decoded!.layouts.keys.single,
        const LayoutKey(kHomeScreenId, LayoutVariant.portrait),
      );
    });
  });

  group('normalizeScreenLayout', () {
    test(
      'drops unknown ids and duplicates, appends registry gaps in order',
      () {
        final normalized = normalizeScreenLayout(
          _screen([
            const ComponentLayout(id: 'home.playlists'),
            const ComponentLayout(id: 'home.ghost'),
            const ComponentLayout(id: 'home.playlists', visible: false),
          ]),
          homeComponentRegistry,
        );
        expect(_ids(normalized), [
          'home.playlists',
          'home.continueListening',
          'home.listeningInsights',
          'home.allSongs',
        ]);
        expect(normalized.component('home.playlists')!.visible, isTrue);
      },
    );

    test('clamps invalid style and forces non-hideable visible', () {
      final normalized = normalizeScreenLayout(
        _screen([
          const ComponentLayout(id: 'home.allSongs', visible: false),
          const ComponentLayout(
            id: 'home.continueListening',
            size: ComponentSize.medium,
            styleId: 'nonsense',
          ),
        ]),
        homeComponentRegistry,
      );
      expect(
        normalized.component('home.allSongs')!.visible,
        isTrue,
        reason: 'allSongs cannot be hidden',
      );
      expect(normalized.component('home.continueListening')!.styleId, 'hero');
    });

    test('clamps a size outside the definition allow-list', () {
      const restricted = UiComponentRegistry([
        UiComponentDefinition(
          id: 'widget',
          label: 'Widget',
          description: 'Test-only component',
          defaultSize: ComponentSize.medium,
          allowedSizes: [ComponentSize.medium, ComponentSize.large],
        ),
      ]);
      final normalized = normalizeScreenLayout(
        _screen([
          const ComponentLayout(id: 'widget', size: ComponentSize.small),
        ]),
        restricted,
      );
      expect(normalized.component('widget')!.size, ComponentSize.medium);
    });

    test('is idempotent', () {
      final first = normalizeScreenLayout(
        _screen([
          const ComponentLayout(id: 'home.allSongs', size: ComponentSize.large),
        ]),
        homeComponentRegistry,
      );
      final second = normalizeScreenLayout(first, homeComponentRegistry);
      expect(second, first);
    });
  });

  group('normalizeLayoutProfile', () {
    test('discards a profile from a different schema version', () {
      final stored = LayoutProfile(
        schemaVersion: kUiLayoutSchemaVersion + 1,
        layouts: {
          const LayoutKey(kHomeScreenId, LayoutVariant.portrait): _screen([
            const ComponentLayout(id: 'home.playlists', visible: false),
          ]),
        },
      );
      final normalized = normalizeLayoutProfile(stored, homeComponentRegistry);
      expect(normalized, defaultLayoutProfile(homeComponentRegistry));
    });

    test('fills missing variants and drops non-registry screens', () {
      final stored = LayoutProfile(
        layouts: {
          const LayoutKey(kHomeScreenId, LayoutVariant.portrait): _screen([
            const ComponentLayout(id: 'home.playlists', visible: false),
          ]),
          const LayoutKey('library', LayoutVariant.portrait): _screen([
            const ComponentLayout(id: 'home.allSongs'),
          ]),
        },
      );
      final normalized = normalizeLayoutProfile(stored, homeComponentRegistry);
      expect(normalized.layouts.length, LayoutVariant.values.length);
      expect(
        normalized
            .screenLayout(kHomeScreenId, LayoutVariant.portrait)!
            .component('home.playlists')!
            .visible,
        isFalse,
      );
      expect(
        normalized.screenLayout(kHomeScreenId, LayoutVariant.landscape),
        isNotNull,
      );
      expect(
        normalized.layouts.keys.any((k) => k.screenId == 'library'),
        isFalse,
      );
    });
  });

  group('applyLayoutPreset', () {
    test('standard reproduces the registry default exactly', () {
      expect(
        applyLayoutPreset(
          LayoutPreset.standard,
          kHomeScreenId,
          homeComponentRegistry,
        ),
        defaultScreenLayout(kHomeScreenId, homeComponentRegistry),
      );
    });

    test('minimal hides the optional sections and shrinks the hero', () {
      final layout = applyLayoutPreset(
        LayoutPreset.minimal,
        kHomeScreenId,
        homeComponentRegistry,
      );
      expect(layout.component('home.listeningInsights')!.visible, isFalse);
      expect(layout.component('home.playlists')!.visible, isFalse);
      expect(
        layout.component('home.continueListening')!.size,
        ComponentSize.small,
      );
      expect(layout.component('home.allSongs')!.visible, isTrue);
    });

    test('compact uses the small size everywhere', () {
      final layout = applyLayoutPreset(
        LayoutPreset.compact,
        kHomeScreenId,
        homeComponentRegistry,
      );
      for (final component in layout.components) {
        expect(component.size, ComponentSize.small, reason: component.id);
      }
    });

    test('immersive uses the large size for the visual sections', () {
      final layout = applyLayoutPreset(
        LayoutPreset.immersive,
        kHomeScreenId,
        homeComponentRegistry,
      );
      expect(
        layout.component('home.continueListening')!.size,
        ComponentSize.large,
      );
      expect(layout.component('home.playlists')!.size, ComponentSize.large);
      expect(layout.component('home.allSongs')!.size, ComponentSize.medium);
    });

    test('discovery reorders and restyles the dashboard', () {
      final layout = applyLayoutPreset(
        LayoutPreset.discovery,
        kHomeScreenId,
        homeComponentRegistry,
      );
      expect(_ids(layout), [
        'home.playlists',
        'home.listeningInsights',
        'home.continueListening',
        'home.allSongs',
      ]);
      expect(layout.component('home.playlists')!.styleId, 'grid');
      expect(layout.component('home.continueListening')!.styleId, 'compact');
      expect(
        layout.component('home.continueListening')!.size,
        ComponentSize.small,
      );
    });
  });

  group('KvLayoutRepository', () {
    test('returns null when nothing is stored', () async {
      final repository = KvLayoutRepository(_MemoryStore());
      expect(await repository.load(), isNull);
    });

    test('round-trips a saved profile', () async {
      final store = _MemoryStore();
      final repository = KvLayoutRepository(store);
      final profile = applyLayoutPreset(
        LayoutPreset.discovery,
        kHomeScreenId,
        homeComponentRegistry,
      );
      final saved = LayoutProfile(
        preset: LayoutPreset.discovery,
        layouts: {
          for (final variant in LayoutVariant.values)
            LayoutKey(kHomeScreenId, variant): profile,
        },
      );
      await repository.save(saved);
      expect(store.values[KvLayoutRepository.storageKey], isNotNull);
      expect(await repository.load(), saved);
    });

    test('treats a corrupt blob as empty instead of throwing', () async {
      final store = _MemoryStore()
        ..values[KvLayoutRepository.storageKey] = '{broken';
      expect(await KvLayoutRepository(store).load(), isNull);
    });
  });
}
