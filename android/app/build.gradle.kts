import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}
val hasReleaseSigning = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !signingProperties.getProperty(it).isNullOrBlank() } &&
    rootProject.file(signingProperties.getProperty("storeFile", "missing-release-key")).isFile

// Public Firebase app identifiers are supplied by candidate configuration.
// Empty configuration leaves background push unavailable without breaking startup.
val pushDefines = (project.findProperty("dart-defines") as? String).orEmpty().split(",")
    .mapNotNull { encoded -> runCatching { String(Base64.getDecoder().decode(encoded)) }.getOrNull() }
    .filter { it.contains("=") }.associate { it.substringBefore("=") to it.substringAfter("=") }
val firebaseResources = mapOf("FIREBASE_APP_ID" to "google_app_id", "FIREBASE_API_KEY" to "google_api_key",
    "FIREBASE_PROJECT_ID" to "project_id", "FIREBASE_SENDER_ID" to "gcm_defaultSenderId")
val hasPushConfiguration = firebaseResources.keys.all { !pushDefines[it].isNullOrBlank() }
// Integration APKs must never replace the user's installed Tabby or its data.
val usbTestBuild = pushDefines["TABBY_USB_TEST"] == "true"
val entryTestBuild = usbTestBuild && pushDefines["TABBY_ENTRY_TEST"] == "true"

gradle.taskGraph.whenReady {
    if (usbTestBuild && allTasks.any { it.project.path == ":app" &&
            !it.name.contains("Debug", ignoreCase = true) &&
            (it.name.contains("Release", ignoreCase = true) || it.name.contains("Profile", ignoreCase = true)) }) {
        throw GradleException("USB test isolation is only allowed for debug builds.")
    }
    if (allTasks.any { it.project.path == ":app" && it.name.contains("Release", ignoreCase = true) }
        && !hasReleaseSigning) {
        throw GradleException("Release signing is required; debug signing is never a release fallback.")
    }
}

android {
    namespace = "com.zalweb.tabby"
    buildFeatures {
        // AGP 9 defaults this off; configured Firebase emits public resValue IDs.
        resValues = true
    }
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.zalweb.tabby"
        manifestPlaceholders["tabbyLabel"] = if (entryTestBuild) "Tabby Entry Test" else if (usbTestBuild) "Tabby USB Test" else "Tabby"
        manifestPlaceholders["tabbyAuthScheme"] = if (entryTestBuild) "io.supabase.tabby.entrytest" else if (usbTestBuild) "io.supabase.tabby.usbtest" else "io.supabase.tabby"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        if (hasPushConfiguration) firebaseResources.forEach { (key, resource) ->
            resValue("string", resource, pushDefines.getValue(key))
        }
    }

    buildTypes {
        debug {
            if (usbTestBuild) applicationIdSuffix = if (entryTestBuild) ".entrytest" else ".usbtest"
        }
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.create("release").apply {
                    storeFile = rootProject.file(signingProperties.getProperty("storeFile"))
                    storePassword = signingProperties.getProperty("storePassword")
                    keyAlias = signingProperties.getProperty("keyAlias")
                    keyPassword = signingProperties.getProperty("keyPassword")
                }
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.firebase:firebase-messaging:25.1.3")
    testImplementation("junit:junit:4.13.2")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
