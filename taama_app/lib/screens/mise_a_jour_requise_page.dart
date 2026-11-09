// lib/screens/mise_a_jour_requise_page.dart
//
// Logique de l'écran « Mise à jour requise » : lancer la mise à jour de Google
// Play (sinon sa fiche), ou relancer le démarrage.

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
  bool _enCours = false;
  AvisMiseAJour? _avis;

  Future<void> _mettreAJour() async {
    if (_enCours) return;
    setState(() {
      _enCours = true;
      _avis = null;
    });
    try {
      final issue = await MiseAJour.mettreAJour();
      if (!mounted) return;
      setState(() => _avis = switch (issue) {
            IssueMiseAJour.lancee => null,
            IssueMiseAJour.annulee => AvisMiseAJour.annulee,
            IssueMiseAJour.impossible => AvisMiseAJour.playStoreIndisponible,
          });
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  void _reessayer() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const EcranSplash()));
  }

  @override
  Widget build(BuildContext context) => EcranMiseAJourRequise(
        onMettreAJour: _mettreAJour,
        onReessayer: _reessayer,
        enCours: _enCours,
        avis: _avis,
      );
}
