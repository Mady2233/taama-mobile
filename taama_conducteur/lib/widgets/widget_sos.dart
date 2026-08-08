import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';

/// Bouton SOS rouge + dialogue de confirmation, utilisable depuis
/// n'importe quel écran de course en cours.
Future<void> afficherDialogueSOS(
  BuildContext context, {
  int? demandeId,
  int? reservationId,
}) async {
  final confirme = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.sos, color: Colors.red, size: 28),
          SizedBox(width: 8),
          Text('Alerte SOS', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        ],
      ),
      content: const Text(
        'Tu es en danger ?\n\nTon alerte et ta position GPS vont être envoyées immédiatement aux équipes Taama.',
        style: TextStyle(fontSize: 15),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('ENVOYER L\'ALERTE', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );

  if (confirme != true || !context.mounted) return;

  // Récupère la position GPS en temps réel
  double? lat, lng;
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 5),
      ),
    );
    lat = position.latitude;
    lng = position.longitude;
  } catch (_) {}

  try {
    await ApiService.declencherSOS(
      demandeId: demandeId,
      reservationId: reservationId,
      latitude: lat,
      longitude: lng,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🚨 Alerte SOS envoyée ! Les équipes Taama ont été notifiées.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Erreur lors de l\'envoi de l\'alerte. Appelle le 112.'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

/// Widget bouton SOS compact, à placer dans l'AppBar ou en bas d'écran.
class BoutonSOS extends StatelessWidget {
  final int? demandeId;
  final int? reservationId;

  const BoutonSOS({super.key, this.demandeId, this.reservationId});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => afficherDialogueSOS(
        context,
        demandeId: demandeId,
        reservationId: reservationId,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sos, color: Colors.white, size: 18),
            SizedBox(width: 4),
            Text(
              'SOS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
