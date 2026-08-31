import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vora_tube/core/db/app_database.dart';
import 'package:vora_tube/features/ads/premium_models.dart';
import 'package:vora_tube/features/ads/premium_providers.dart';
import 'package:vora_tube/features/library/data/library_repository.dart';

/// Verifies the Premium entitlement genuinely survives an app "restart": a fresh
/// [AppDatabase] + [LibraryRepository] instance pointed at the same SQLite file,
/// plus a freshly constructed [PremiumController] that must load the stored flag.
void main() {
  late File dbFile;

  setUp(() {
    dbFile = File(
      '${Directory.systemTemp.path}/vt_premium_'
      '${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
  });

  tearDown(() {
    if (dbFile.existsSync()) {
      dbFile.deleteSync();
    }
  });

  test('premium entitlement persists across a reopened database', () async {
    final db1 = AppDatabase(NativeDatabase(dbFile));
    final repo1 = LibraryRepository(db1);

    final first = PremiumController(repo1);
    await Future<void>.delayed(Duration.zero);
    expect(first.state, PremiumEntitlement.inactive);

    await first.activate();
    expect(await repo1.kvGet(PremiumKeys.activated), 'true');

    await db1.close();

    // Simulate a restart: reopen the same file with a brand-new repository.
    final db2 = AppDatabase(NativeDatabase(dbFile));
    final repo2 = LibraryRepository(db2);

    final stored = await repo2.kvGet(PremiumKeys.activated);
    expect(stored, 'true');

    final second = PremiumController(repo2);
    await Future<void>.delayed(Duration.zero);
    expect(second.state, PremiumEntitlement.active);
    expect(second.isPremium, isTrue);

    await db2.close();
  });
}
