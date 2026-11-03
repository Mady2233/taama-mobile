// lib/services/politique_confidentialite.dart
//
// Ouvre la politique de confidentialité dans le navigateur du téléphone.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

/// Si rien ne peut ouvrir la page, l'adresse est affichée : jamais un bouton sans
/// effet. [ouvrir] remplace le navigateur dans les tests.
Future<void> ouvrirPolitiqueConfidentialite(
  BuildContext context, {
  Future<bool> Function(Uri)? ouvrir,
}) async {
  final uri = Uri.parse(AppConfig.urlPolitiqueConfidentialite);
  var ouverte = false;
  try {
    ouverte = await (ouvrir ?? _ouvrirDansLeNavigateur)(uri);
  } catch (_) {
    // Aucun navigateur, ou refus du système : le message ci-dessous donne l'adresse.
  }
  if (ouverte || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('Impossible d’ouvrir la page. Adresse : ${AppConfig.urlPolitiqueConfidentialite}'),
    duration: const Duration(seconds: 8),
  ));
}

Future<bool> _ouvrirDansLeNavigateur(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
