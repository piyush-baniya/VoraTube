import java.io.FileInputStream
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// A release build must be signed with the real upload/release credentials. When
// they are missing we fail the release build loudly instead of silently falling
// back to debug signing. Debug builds never touch this config.
val releaseStoreFile = keystoreProperties["storeFile"]?.let { file(it) }
val hasReleaseKeystore =
    keystorePropertiesFile.exists() &&
        keystoreProperties["keyAlias"] != null &&
        keystoreProperties["keyPassword"] != null &&
        keystoreProperties["storePassword"] != null &&
        releaseStoreFile != null &&
        releaseStoreFile.isFile


plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")

}

android {
    namespace = "com.piyushbaniya.vora_tube"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion


    signingConfigs {
        // Only define the release signing config when real credentials exist.
        // This is read during configuration; skipping it keeps debug builds
        // working without key.properties/upload-keystore.jks.
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = releaseStoreFile
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }


    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.piyushbaniya.vora_tube"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AdMob app ID defaults to Google's test app ID for debug builds and
        // is overridden to VoraTube's production app ID in the release
        // buildType — mirroring VoraTubeAds.useTestAds (kDebugMode) so a
        // released app always serves live ads and never a demo app ID.
        manifestPlaceholders["admobAppId"] =
            "ca-app-pub-3940256099942544~3347511713"
        // Default app label; the debug buildType overrides this with the
        // side-by-side dev name so both apps are distinguishable on-device.
        manifestPlaceholders["appLabel"] = "VoraTube"
    }

    buildTypes {
        debug {
            // Side-by-side development install. The production package,
            // namespace and release signing are left untouched; only the debug
            // variant is re-branded so it can coexist with the Play install.
            // A distinct applicationId gives V2 Dev its own sandbox (storage,
            // databases, preferences and rewarded/premium state) and lets it be
            // uninstalled without touching production data.
            applicationIdSuffix = ".v2dev"
            // "-v2dev" makes the build origin obvious in Settings and crash
            // reports while the production versionName stays untouched.
            versionNameSuffix = "-v2dev"
            manifestPlaceholders["appLabel"] = "VoraTube V2 Dev"
        }
        release {
            // Production AdMob app ID: a released build must serve live IDs.
            // (VoraTubeAds.useTestAds is false in release and every unit +
            // this app-level ID resolves to the production AdMob app.)
            manifestPlaceholders["admobAppId"] =
                "ca-app-pub-5203454754912425~2417374767"
            // Release builds are signed with the real upload/release key from
            // key.properties. When that configuration is absent the build must
            // fail loudly (see the taskGraph guard below) — never silently fall
            // back to debug credentials.
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
            // Shrink Java/Kotlin plugin code and strip unused Android resources.
            // audio_service/just_audio/ExoPlayer entry points plus the
            // string-referenced notification drawables need explicit keeps:
            // see proguard-rules.pro and res/values/keep.xml. Shrinking itself
            // stays enabled.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

// ── Side-by-side Firebase handling ──────────────────────────────────────────
// google-services.json currently registers only the production package
// (com.piyushbaniya.vora_tube). The v2dev debug variant has no matching client,
// and Google's plugin fails the build when one is missing. Rather than
// fabricating a registration, skip Firebase processing for just that variant:
// the V2 Dev build runs without analytics (see lib/main.dart) and never reports
// development activity into the production Firebase project. Release and
// profile variants keep the production client and are unaffected.
tasks.matching { it.name == "processDebugGoogleServices" }.configureEach {
    enabled = false
}

// A production release requires real signing credentials. If they are missing,
// stop the build at planning time with a clear message instead of allowing the
// artifact to be produced unsigned / debug-signed. Debug builds never reach a
// Release task and are unaffected.
gradle.taskGraph.whenReady {
    val releaseSigningRequired = allTasks.any { task ->
        when {
            task.name == "bundleRelease" -> true
            task.name == "assembleRelease" -> true
            task.name.startsWith("packageRelease") -> true
            task.name.startsWith("bundleRelease") -> true
            else -> false
        }
    }
    if (releaseSigningRequired && !hasReleaseKeystore) {
        throw GradleException(
            "Release signing configuration is missing.\n" +
                "Configure key.properties and the upload keystore " +
                "before building a production release."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.google.android.play:app-update:2.1.0")
    implementation("com.google.android.play:app-update-ktx:2.1.0")
}

flutter {
    source = "../.."
}
