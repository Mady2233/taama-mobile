import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';

class EcranAvisApp extends StatefulWidget {
  const EcranAvisApp({super.key});

  @override
  State<EcranAvisApp> createState() => _EcranAvisAppState();
}

class _EcranAvisAppState extends State<EcranAvisApp> {
  int _noteSelectionnee = 0;
  String _categorieSelectionnee = 'autre';
  final TextEditingController _messageController = TextEditingController();
  bool _enEnvoi = false;

  final Map<String, String> _categories = {
    'interface': '🎨 Interface / Design',
    'performance': '⚡ Performance',
    'conducteurs': '🚗 Qualité des conducteurs',
    'paiement': '💳 Paiement',
    'support': '🎧 Support client',
    'autre': '💬 Autre',
  };

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    if (_noteSelectionnee == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisis une note entre 1 et 5 étoiles')),
      );
      return;
    }

    if (_messageController.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message trop court (10 caractères minimum)')),
      );
      return;
    }

    setState(() => _enEnvoi = true);
    try {
      await ApiService.soumettreAvis(
        note: _noteSelectionnee,
        categorie: _categorieSelectionnee,
        message: _messageController.text.trim(),
      );

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Merci ! 🙏'),
          content: const Text(
            'Ton avis a été envoyé avec succès. '
            'Il nous aide à améliorer Taama pour tous les utilisateurs.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: CouleursTaama.terreCuite,
                foregroundColor: Colors.white,
              ),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _enEnvoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleursTaama.sable,
      appBar: AppBar(
        title: const Text('Donner mon avis'),
        backgroundColor: CouleursTaama.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8),
                ],
              ),
              child: const Column(
                children: [
                  Text('🌟', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 8),
                  Text(
                    'Comment tu trouves Taama ?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: CouleursTaama.indigo,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Ton avis nous aide à améliorer l\'app',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Étoiles
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Note globale',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(5, (index) {
                      final etoile = index + 1;
                      return GestureDetector(
                        onTap: () => setState(() => _noteSelectionnee = etoile),
                        child: Icon(
                          etoile <= _noteSelectionnee
                              ? Icons.star
                              : Icons.star_border,
                          color: CouleursTaama.or,
                          size: 36,  // Réduit de 40 à 36
                        ),
                      );
                    }),
                  ),
                  if (_noteSelectionnee > 0) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        [
                          '',
                          'Très mauvais 😞',
                          'Mauvais 😕',
                          'Correct 😐',
                          'Bien 😊',
                          'Excellent ! 🤩',
                        ][_noteSelectionnee],
                        style: const TextStyle(
                          fontSize: 14,
                          color: CouleursTaama.terreCuite,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Catégorie
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Catégorie',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _categories.entries.map((entry) {
                      final selectionne =
                          _categorieSelectionnee == entry.key;
                      return GestureDetector(
                        onTap: () => setState(
                            () => _categorieSelectionnee = entry.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selectionne
                                ? CouleursTaama.indigo
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              color: selectionne
                                  ? Colors.white
                                  : Colors.grey.shade700,
                              fontSize: 13,
                              fontWeight: selectionne
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Message
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ton message',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _messageController,
                    maxLines: 4,
                    maxLength: 1000,
                    decoration: InputDecoration(
                      hintText: 'Partage ton expérience avec Taama...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Bouton envoyer
            ElevatedButton(
              onPressed: _enEnvoi ? null : _envoyer,
              style: ElevatedButton.styleFrom(
                backgroundColor: CouleursTaama.terreCuite,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _enEnvoi
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Envoyer mon avis',
                      style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
