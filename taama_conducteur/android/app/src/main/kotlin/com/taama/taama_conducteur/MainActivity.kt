package com.taama.taama_conducteur

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Ce qui peut empêcher une demande de sonner (lib/services/
        // verification_sonnerie.dart). Lu sur le téléphone, rien n'est envoyé.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_SONNERIE)
            .setMethodCallHandler { appel, resultat ->
                when (appel.method) {
                    "etat" -> resultat.success(etatSonnerie())
                    "ouvrirReglages" -> resultat.success(ouvrirReglages(appel.argument<String>("reglage")))
                    else -> resultat.notImplemented()
                }
            }
    }

    private fun etatSonnerie(): Map<String, Boolean> {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val muette = audio.ringerMode != AudioManager.RINGER_MODE_NORMAL ||
            audio.getStreamVolume(AudioManager.STREAM_RING) == 0
        val economie = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val energie = getSystemService(Context.POWER_SERVICE) as PowerManager
            !energie.isIgnoringBatteryOptimizations(packageName)
        } else {
            false
        }
        return mapOf("sonnerieMuette" to muette, "economieBatterie" to economie)
    }

    /** Ouvre le bon écran de réglages, sinon la fiche de l'app. Aucune
     *  permission demandée : c'est le chauffeur qui choisit. */
    private fun ouvrirReglages(reglage: String?): Boolean {
        val intention = when (reglage) {
            "batterie" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            } else {
                null
            }
            "son" -> Intent(Settings.ACTION_SOUND_SETTINGS)
            "notifications" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            } else {
                null
            }
            else -> return false
        }
        if (intention != null && demarrer(intention)) return true
        return demarrer(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
        )
    }

    private fun demarrer(intention: Intent): Boolean = try {
        startActivity(intention)
        true
    } catch (e: Exception) {
        false
    }

    companion object {
        private const val CANAL_SONNERIE = "taama/sonnerie_systeme"
    }
}
