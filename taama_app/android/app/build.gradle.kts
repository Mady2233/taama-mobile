import java.util.Base64
import java.io.FileInputStream
import java.util.Properties

// Signature de la release : android/key.properties, HORS git (voir
// CONTEXTE.md §6.1). Lu seulement s'il existe ; une release sans lui est
// refusée plus bas. Jamais de repli sur la clé de debug.
val fichierCle = rootProject.file("key.properties")
val proprietesCle = Properties().apply {
    if (fichierCle.exists()) FileInputStream(fichierCle).use { load(it) }
}
val champsCle = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val cleComplete = champsCle.all { !proprietesCle.getProperty(it).isNullOrBlank() }

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.taama.taama_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.taama.taama_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (cleComplete) {
                // Chemin absolu, ou relatif au dossier android/.
                storeFile = rootProject.file(proprietesCle.getProperty("storeFile"))
                storePassword = proprietesCle.getProperty("storePassword")
                keyAlias = proprietesCle.getProperty("keyAlias")
                keyPassword = proprietesCle.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Clé d'upload Play, jamais la clé de debug.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

// Une release sans fond de carte configuré afficherait « Carte
// indisponible » partout, et sans attribution violerait la licence du
// fournisseur : on refuse de la construire. Flutter transmet les
// --dart-define à Gradle en base64, séparés par des virgules.
val definesDart: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.mapNotNull { runCatching { String(Base64.getDecoder().decode(it)) }.getOrNull() }
        ?.mapNotNull { d -> d.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] } }
        ?.toMap() ?: emptyMap()

// Contrôle à la configuration, avant toute compilation : assembleRelease
// est la dernière tâche du build, un doFirst ne s'y déclencherait qu'une
// fois l'APK déjà produit.
val construitUneRelease = gradle.startParameter.taskNames.any {
    val nom = it.substringAfterLast(":")
    (nom.startsWith("assemble") || nom.startsWith("bundle")) && nom.endsWith("Release")
}
if (construitUneRelease) {
    val erreurs = mutableListOf<String>()
    if (!fichierCle.exists()) {
        erreurs += "android/key.properties absent (voir CONTEXTE.md §6.1)"
    } else {
        val manquants = champsCle.filter { proprietesCle.getProperty(it).isNullOrBlank() }
        if (manquants.isNotEmpty()) {
            erreurs += "key.properties incomplet : ${manquants.joinToString()}"
        } else if (!rootProject.file(proprietesCle.getProperty("storeFile")).exists()) {
            erreurs += "keystore introuvable (storeFile de key.properties)"
        }
    }
    // Fond de carte : rien n'est écrit dans le code (lib/config/carte_config.dart).
    for (cle in listOf("MAP_TILES_LIGHT", "MAP_TILES_DARK", "CARTE_ATTRIBUTION")) {
        if (definesDart[cle].isNullOrBlank()) {
            erreurs += "--dart-define=$cle manquant (voir CONTEXTE.md §4.1)"
        }
    }
    if (erreurs.isNotEmpty()) {
        throw GradleException("Release refusée :\n - " + erreurs.joinToString("\n - "))
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}