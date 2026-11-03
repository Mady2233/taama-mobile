import 'package:flutter/material.dart';
import '../theme/taama_theme.dart';
import 'home/home_page.dart';
import 'services_screen.dart';
import 'activite_screen.dart';
import 'compte_screen.dart';

/// Coquille à onglets de l'app client : porte la barre de navigation du bas.
/// Le contenu de chaque onglet (dont HomePage) ne contient PAS de barre —
/// elle est unique et vit ici.
class EcranAccueil extends StatefulWidget {
  const EcranAccueil({super.key});

  @override
  State<EcranAccueil> createState() => _EcranAccueilState();
}

class _EcranAccueilState extends State<EcranAccueil> {
  int _indexOnglet = 0;

  final List<Widget> _onglets = const [
    HomePage(),
    EcranServices(),
    EcranActivite(),
    EcranCompte(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _indexOnglet,
        children: _onglets,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indexOnglet,
        onDestinationSelected: (index) => setState(() => _indexOnglet = index),
        backgroundColor: TaamaColors.surface,
        indicatorColor: TaamaColors.primary.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: TaamaColors.primary),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view, color: TaamaColors.primary),
            label: 'Services',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: TaamaColors.primary),
            label: 'Activité',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: TaamaColors.primary),
            label: 'Compte',
          ),
        ],
      ),
    );
  }
}