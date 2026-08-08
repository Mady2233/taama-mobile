import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';

/// Permet de recharger le solde Taama via Orange Money ou Moov Money
/// (via PayDunya). Le flux est :
/// 1. L'utilisateur choisit opérateur + montant → appuie sur Recharger
/// 2. PayDunya envoie une demande de confirmation USSD sur le téléphone
/// 3. L'app interroge PayDunya toutes les 3s pour savoir si l'utilisateur
///    a confirmé → une fois confirmé, le solde est crédité automatiquement
class EcranRecharge extends StatefulWidget {
  const EcranRecharge({super.key});

  @override
  State<EcranRecharge> createState() => _EcranRechargeState();
}

class _EcranRechargeState extends State<EcranRecharge> {
  int? _operateurSelectionne;
  final TextEditingController _montantController = TextEditingController();
  bool _enChargement = false;

  // État du flux PayDunya (après envoi de la demande)
  bool _enAttenteConfirmation = false;
  int? _rechargeId;
  Timer? _timerPolling;
  String _messageStatut = '';

  final List<(String, String, Color)> _operateurs = [
    ('orange', 'Orange Money', Colors.orange),
    ('moov', 'Moov Money', Colors.blue),
  ];

  final List<int> _montantsRapides = [500, 1000, 2000, 5000, 10000];

  @override
  void dispose() {
    _montantController.dispose();
    _timerPolling?.cancel();
    super.dispose();
  }

  Future<void> _rechargerViaPaydunya() async {
    final montant = int.tryParse(_montantController.text);
    if (_operateurSelectionne == null || montant == null || montant < 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisis un opérateur et un montant valide (min 100 FCFA)')),
      );
      return;
    }

    setState(() => _enChargement = true);
    try {
      final resultat = await ApiService.demanderRechargePaydunya(
        operateur: _operateurs[_operateurSelectionne!].$1,
        montant: montant,
      );

      if (!mounted) return;
      setState(() {
        _rechargeId = resultat['recharge_id'];
        _enAttenteConfirmation = true;
        _messageStatut = 'En attente de ta confirmation sur ton téléphone...';
      });

      // Je lance le polling pour vérifier la confirmation toutes les 3s
      _timerPolling = Timer.periodic(const Duration(seconds: 3), (_) => _verifierStatut());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _enChargement = false);
    }
  }

  Future<void> _verifierStatut() async {
    if (_rechargeId == null) return;
    try {
      final resultat = await ApiService.verifierRechargePaydunya(
        rechargeId: _rechargeId!,
      );

      final statut = resultat['statut']?.toString() ?? '';
      final nouveauSolde = resultat['solde'] is int
          ? resultat['solde'] as int
          : int.tryParse(resultat['solde'].toString()) ?? 0;

      if (statut == 'completed') {
        _timerPolling?.cancel();
        if (!mounted) return;
        Navigator.pop(context, nouveauSolde);
      } else if (statut == 'cancelled') {
        _timerPolling?.cancel();
        if (!mounted) return;
        setState(() {
          _enAttenteConfirmation = false;
          _messageStatut = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paiement annulé ou expiré. Réessaie.')),
        );
      } else {
        if (mounted) {
          setState(() => _messageStatut = 'En attente de ta confirmation sur ton téléphone...');
        }
      }
    } catch (e) {
      debugPrint('Erreur polling PayDunya : $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recharger mon compte'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: _enAttenteConfirmation
            ? _buildAttenteConfirmation()
            : _buildFormulaire(),
      ),
    );
  }

  Widget _buildAttenteConfirmation() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            width: 64, height: 64,
            child: CircularProgressIndicator(color: CouleursTaama.terreCuite, strokeWidth: 5),
          ),
          const SizedBox(height: 32),
          const Text(
            'Confirme le paiement',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: CouleursTaama.indigo),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            _messageStatut,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Une demande de confirmation a été envoyée sur ton téléphone (${_operateurs[_operateurSelectionne ?? 0].$2}). '
            'Accepte-la pour finaliser la recharge.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: () {
              _timerPolling?.cancel();
              setState(() {
                _enAttenteConfirmation = false;
                _rechargeId = null;
              });
            },
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }

  Widget _buildFormulaire() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Choisis ton opérateur', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          ..._operateurs.asMap().entries.map((entry) {
            final index = entry.key;
            final (_, nom, couleur) = entry.value;
            final selectionne = _operateurSelectionne == index;

            return GestureDetector(
              onTap: () => setState(() => _operateurSelectionne = index),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selectionne ? couleur.withValues(alpha: 0.12) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selectionne ? couleur : Colors.grey.shade300,
                    width: selectionne ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.phone_android, color: couleur),
                    const SizedBox(width: 12),
                    Text(nom, style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (selectionne) ...[
                      const Spacer(),
                      Icon(Icons.check_circle, color: couleur, size: 20),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 20),
          const Text('Montant (FCFA)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          TextField(
            controller: _montantController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              suffixText: 'FCFA',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: CouleursTaama.terreCuite, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: _montantsRapides.map((montant) {
              return ActionChip(
                label: Text('$montant'),
                backgroundColor: Colors.white,
                onPressed: () => _montantController.text = montant.toString(),
              );
            }).toList(),
          ),
          const Spacer(),

          // Bouton principal : vrai paiement PayDunya
          ElevatedButton.icon(
            onPressed: _enChargement ? null : _rechargerViaPaydunya,
            icon: const Icon(Icons.phone_android),
            label: _enChargement
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Recharger via Mobile Money', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: CouleursTaama.terreCuite,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}