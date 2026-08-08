import 'package:flutter/material.dart';
import '../theme/couleurs_taama.dart';
import 'carte_screen.dart';
import 'services_screen.dart';
import 'activite_screen.dart';
import 'compte_screen.dart';

class EcranAccueil extends StatefulWidget {
  const EcranAccueil({super.key});

  @override
  State<EcranAccueil> createState() => _EcranAccueilState();
}

class _EcranAccueilState extends State<EcranAccueil> {
  int _indexOnglet = 0;

  final List<Widget> _onglets = const [
    EcranCarte(),
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
        onDestinationSelected: (index) =>
            setState(() => _indexOnglet = index),
        backgroundColor: Colors.white,
        indicatorColor: CouleursTaama.indigo.withValues(alpha: 0.1),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: CouleursTaama.indigo),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view, color: CouleursTaama.indigo),
            label: 'Services',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: CouleursTaama.indigo),
            label: 'Activité',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: CouleursTaama.indigo),
            label: 'Compte',
          ),
        ],
      ),
    );
  }
}
