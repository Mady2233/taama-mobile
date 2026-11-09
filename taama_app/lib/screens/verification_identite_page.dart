// Logique de « Vérifier mon identité » (écran : verification_identite_screen.dart).
// Facultatif : aucune autre partie de l'app n'attend ce statut.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' show ClientException;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/verification_identite.dart';
import '../services/api_service.dart';
import 'verification_identite_screen.dart';

/// Posé pendant que l'appareil photo ou la galerie est ouvert : Android peut
/// fermer l'app à court de mémoire, la photo est alors reprise à la réouverture.
const String _cleChoixEnCours = 'choix_piece_identite_en_cours';

class PageVerificationIdentite extends StatefulWidget {
  const PageVerificationIdentite({super.key});

  @override
  State<PageVerificationIdentite> createState() => _PageVerificationIdentiteState();
}

class _PageVerificationIdentiteState extends State<PageVerificationIdentite> {
  final ImagePicker _picker = ImagePicker();
  VerificationIdentite? _verification;
  bool _chargement = true;
  String? _erreur;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _charger();
    _reprendrePhotoPerdue();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final verification = VerificationIdentite.depuisJson(await ApiService.verificationIdentite());
      if (!mounted) return;
      setState(() {
        _verification = verification;
        _erreur = verification == null ? 'Réponse du serveur illisible. Réessaie.' : null;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Identite] Chargement : ${e.runtimeType}');
      if (!mounted) return;
      setState(() => _erreur = 'Impossible de joindre Taama. Vérifie ta connexion et réessaie.');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _reprendrePhotoPerdue() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_cleChoixEnCours) != true) return;
      await prefs.remove(_cleChoixEnCours);
      final fichier = (await _picker.retrieveLostData()).file;
      if (fichier == null || !mounted) return;
      final confirme = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Envoyer cette photo ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(fichier.path), height: 160, fit: BoxFit.cover),
              ),
              const SizedBox(height: 12),
              const Text('Seule l’équipe Taama qui vérifie pourra la voir.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Envoyer')),
          ],
        ),
      );
      if (confirme == true && mounted) await _envoyer(fichier.path);
    } catch (e) {
      if (kDebugMode) debugPrint('[Identite] Reprise de la photo : ${e.runtimeType}');
    }
  }

  Future<void> _choisir(ImageSource source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cleChoixEnCours, true);
    XFile? image;
    try {
      image = await _picker.pickImage(
        source: source,
        // Le serveur garde 1600 px au plus : inutile d'envoyer plus, et
        // chaque octet coûte au client sur son forfait.
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Identite] Choix de la photo : ${e.runtimeType}');
      _signaler(source == ImageSource.camera
          ? 'Impossible d’ouvrir l’appareil photo. Vérifie l’autorisation dans les réglages du téléphone.'
          : 'Impossible d’ouvrir la galerie. Vérifie l’autorisation dans les réglages du téléphone.');
      return;
    } finally {
      await prefs.remove(_cleChoixEnCours);
    }
    if (image == null || !mounted) return;
    await _envoyer(image.path);
  }

  Future<void> _envoyer(String chemin) async {
    setState(() => _envoi = true);
    try {
      final verification = VerificationIdentite.depuisJson(await ApiService.envoyerPieceIdentite(chemin));
      if (!mounted) return;
      if (verification == null) {
        await _charger();
      } else {
        setState(() => _verification = verification);
      }
      _signaler('Pièce envoyée. Nous la vérifions et te prévenons.');
    } on TimeoutException {
      _signaler('Envoi trop long : connexion lente ou coupée. Réessaie.');
    } on ClientException {
      _signaler('Impossible de joindre Taama. Vérifie ta connexion et réessaie.');
    } on SocketException {
      _signaler('Impossible de joindre Taama. Vérifie ta connexion et réessaie.');
    } catch (e) {
      // Message du serveur (format refusé, pièce déjà vérifiée…), jamais une page d'erreur brute.
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      _signaler(message.isEmpty || message.length > 160 || message.contains('<')
          ? 'L’envoi n’a pas abouti. Réessaie.'
          : message);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  void _signaler(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return EcranVerificationIdentite(
      chargement: _chargement,
      erreur: _erreur,
      verification: _verification,
      envoiEnCours: _envoi,
      onReessayer: _charger,
      onPrendrePhoto: () => _choisir(ImageSource.camera),
      onChoisirPhoto: () => _choisir(ImageSource.gallery),
    );
  }
}
