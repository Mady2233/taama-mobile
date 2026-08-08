import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/couleurs_taama.dart';

/// Avatar d'un conducteur : sa photo de profil si disponible (mise en cache
/// localement par cached_network_image pour ne pas la re-télécharger à
/// chaque scroll en 4G), sinon un cercle avec son initiale.
class AvatarConducteur extends StatelessWidget {
  final String? photoUrl;
  final String nom;
  final double radius;

  const AvatarConducteur({
    super.key,
    required this.photoUrl,
    required this.nom,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    if (photoUrl == null || photoUrl!.isEmpty) {
      return _avatarInitiale();
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: photoUrl!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (context, url) => _avatarInitiale(),
        errorWidget: (context, url, error) => _avatarInitiale(),
      ),
    );
  }

  Widget _avatarInitiale() {
    return CircleAvatar(
      radius: radius,
      backgroundColor: CouleursTaama.indigo,
      child: Text(
        nom.isNotEmpty ? nom.substring(0, 1).toUpperCase() : '?',
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.75,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
