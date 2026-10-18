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
    namespace = "com.taama.taama_conducteur"
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
        applicationId = "com.taama.taama_conducteur"
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

// Une release non signée par la clé d'upload serait refusée par Google
// Play : on refuse de la construire.
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
    if (erreurs.isNotEmpty()) {
        throw GradleException("Release refusée :\n - " + erreurs.joinToString("\n - "))
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
