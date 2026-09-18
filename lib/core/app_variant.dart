/// Build-variant helpers for the side-by-side V2 development install.
///
/// The V2 Dev build is the Android `debug` build type with an
/// `applicationIdSuffix` (see `android/app/build.gradle.kts`). It shares the
/// production namespace and release signing, but gets its own applicationId so
/// it can be installed alongside the Play build with fully isolated data.
library;

/// The applicationId suffix that identifies the side-by-side V2 development
/// build (`com.piyushbaniya.vora_tube.v2dev`). Keep in sync with the
/// `applicationIdSuffix` in `android/app/build.gradle.kts`.
const String sideBySideDevApplicationIdSuffix = '.v2dev';

/// The production applicationId, used to reason about the two installs.
const String productionApplicationId = 'com.piyushbaniya.vora_tube';

/// The side-by-side development applicationId.
const String sideBySideDevApplicationId =
    '$productionApplicationId$sideBySideDevApplicationIdSuffix';

/// True when [packageName] identifies the side-by-side V2 development build.
///
/// Matches only a trailing [sideBySideDevApplicationIdSuffix], so production
/// (`com.piyushbaniya.vora_tube`) and lookalike names such as
/// `com.example.v2dev2` are not misclassified.
bool isSideBySideDevPackage(String packageName) =>
    packageName.endsWith(sideBySideDevApplicationIdSuffix);
