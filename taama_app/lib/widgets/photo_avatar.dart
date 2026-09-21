// lib/widgets/photo_avatar.dart
//
// Avatar photo réutilisable (client, chauffeur).
//
// Règles de sécurité appliquées ici, pas dans les écrans appelants :
//  - seules les URL https sont chargées (une URL http est ignorée) ;
//  - toute erreur réseau ou 403 (URL R2 expirée) retombe silencieusement
//    sur les initiales : jamais d'icône cassée à l'écran ;
//  - la photo est décodée à la taille d'affichage (cacheWidth) pour ne pas
//    garder une image de 1600 px en mémoire dans une pastille de 40 px.

import 'package:flutter/material.dart';

import '../theme/taama_theme.dart';

class PhotoAvatar extends StatelessWidget {
  const PhotoAvatar({
    super.key,
    required this.nom,
    this.urlPhoto,
    this.diametre = 44,
    this.couleurFond = TaamaColors.primarySoft,
    this.couleurTexte = TaamaColors.primary,
    this.bordure,
    this.forme = BoxShape.circle,
  });

  /// Sert à calculer les initiales de repli.
  final String nom;
  final String? urlPhoto;
  final double diametre;
  final Color couleurFond;
  final Color couleurTexte;
  final Color? bordure;
  final BoxShape forme;

  String get _initiales {
    final mots = nom
        .trim()
        .split(RegExp(r'\s+'))
        .where((m) => m.isNotEmpty)
        .toList();
    if (mots.isEmpty) return '';
    if (mots.length == 1) return mots.first.characters.first.toUpperCase();
    return (mots.first.characters.first + mots[1].characters.first)
        .toUpperCase();
  }

  bool get _urlValide {
    final u = urlPhoto;
    if (u == null || u.isEmpty) return false;
    final uri = Uri.tryParse(u);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final rayon = forme == BoxShape.circle
        ? BorderRadius.circular(diametre)
        : BorderRadius.circular(TaamaRadius.md);
    final ratio = MediaQuery.devicePixelRatioOf(context);

    final repli = Center(
      child: _initiales.isEmpty
          ? Icon(Icons.person_rounded,
              color: couleurTexte, size: diametre * 0.5)
          : Text(
              _initiales,
              style: TextStyle(
                color: couleurTexte,
                fontSize: diametre * 0.34,
                fontWeight: FontWeight.w700,
              ),
            ),
    );

    return Container(
      width: diametre,
      height: diametre,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: couleurFond,
        borderRadius: rayon,
        border: bordure == null ? null : Border.all(color: bordure!, width: 2),
      ),
      child: _urlValide
          ? Image.network(
              urlPhoto!,
              fit: BoxFit.cover,
              cacheWidth: (diametre * ratio).round(),
              // URL R2 expirée, hors ligne, fichier absent : on retombe
              // sur les initiales sans casser la mise en page.
              errorBuilder: (_, __, ___) => repli,
              loadingBuilder: (context, enfant, progres) =>
                  progres == null ? enfant : repli,
            )
          : repli,
    );
  }
}
