import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.stockmanager.stock_management"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications uses java.time on minSdk levels that
        // predate it, so the desugared JDK library is required, not optional.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.stockmanager.stock_management"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // One codebase, two Firebase projects. The flavor is what selects the
    // native half of that: the applicationId, and therefore which
    // google-services.json the Google Services plugin resolves. The Dart half
    // is `AppBrand` in lib/config/flavor.dart, which reads the same name back
    // out of `--flavor`; keep the spellings identical.
    //
    // Note that declaring any dimension removes the flavorless variant, so
    // `flutter build apk` / `appbundle` / `run` now REQUIRE `--flavor`. The
    // existing app is `smartshelf`.
    flavorDimensions += "brand"

    productFlavors {
        create("smartshelf") {
            dimension = "brand"
            // applicationId, label and google-services.json all inherit from
            // defaultConfig / src/main / the module-root JSON, so this flavor
            // is byte-for-byte what the app built before flavors existed.
        }
        create("gpb") {
            dimension = "brand"
            // Yes, "gbp" here and "gpb" everywhere else. The brand is GPB
            // (project gpbstockinventory, gpbgroup.co.in); the package name was
            // registered with the letters transposed and an applicationId can
            // never be changed after publication. Do not "fix" this one — it
            // must match the package_name in src/gpb/google-services.json.
            applicationId = "com.gbp.android"
        }
    }

    if (keystorePropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    // Held at 1.9.3 deliberately. 1.13.0 was tried to shed the deprecated
    // Window.setStatusBarColor / setNavigationBarColor calls that Play flags,
    // and measurably made it worse: it ships more per-API-level EdgeToEdge
    // shims, taking those call sites from 6 to 8 in the release dex.
    implementation("androidx.activity:activity-ktx:1.9.3")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
