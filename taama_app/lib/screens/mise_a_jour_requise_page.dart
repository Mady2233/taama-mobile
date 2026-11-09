// lib/screens/mise_a_jour_requise_page.dart
//
// Logique de l'écran « Mise à jour requise » : ouvrir le Play Store, ou relancer
// le démarrage (la version minimale a pu baisser entre-temps).

import 'package:flutter/material.dart';

import '../services/mise_a_jour.dart';
import 'mise_a_jour_requise_screen.dart';
import 'splash_screen.dart';

class PageMiseAJourRequise extends StatefulWidget {
  const PageMiseAJourRequise({super.key});

  @override
  State<PageMiseAJourRequise> createState() => _PageMiseAJourRequiseState();
}

class _PageMiseAJourRequiseState extends State<PageMiseAJourRequise> {
  bool _playStoreIndisponible = false;

  Future<void> _mettreAJour() async {
    final ouvert = await MiseAJour.ouvrirPlayStore();
    if (!mounted) return;
    setState(() => _playStoreIndisponible = !ouvert);
  }

  void _reessayer() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const EcranSplash()));
  }

  @override
  Widget build(BuildContext context) => EcranMiseAJourRequise(
        onMettreAJour: _mettreAJour,
        onReessayer: _reessayer,
        playStoreIndisponible: _playStoreIndisponible,
      );
}
