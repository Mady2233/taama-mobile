import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../theme/couleurs_taama.dart';
import 'chat_screen.dart';

class EcranCourierLivreur extends StatefulWidget {
  final Map<String, dynamic> livraison;
  const EcranCourierLivreur({super.key, required this.livraison});

  @override
  State<EcranCourierLivreur> createState() =>
      _EcranCourierLivreurState();
}

class _EcranCourierLivreurState extends State<EcranCourierLivreur> {
  late Map<String, dynamic> _livraison;
  final LocationService _locationService = LocationService();
  bool _enChargement = false;

  @override
  void initState() {
    super.initState();
    _livraison = widget.livraison;
    // Démarre l'envoi GPS
    _locationService.demarrerEnvoiPosition(
      _livraison['room_gps']?.toString() ??
          'courier_gps_${_livraison['id']}',
    );
  }

  @override
  void dispose() {
    _locationService.arreter();
    super.dispose();
  }

  Future<void> _changerStatut({String? photoBase64}) async {
    setState(() => _enChargement = true);
    try {
      final res = await ApiService.changerStatutCourier(
        _livraison['id'] as int,
        photoLivraison: photoBase64,
      );
      if (!mounted) return;
      setState(() =>
          _livraison = {..._livraison, 'statut': res['statut']});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'OK')),
      );
      if (res['statut'] == 'livre') {
        _locationService.arreter();
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            e.toString().replaceAll('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _enChargement = false);
    }
  }

  Future<void> _prendrePhotoEtLivrer() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 800,
    );
    if (image == null || !mounted) return;

    final bytes = await image.readAsBytes();
    final base64 = base64Encode(bytes);
    await _changerStatut(photoBase64: base64);
  }

  static const _labelsCategorie = {
    'colis': '📦 Colis standard',
    'repas': '🍽️ Repas (restaurant)',
    'document': '📄 Document officiel',
  };

  String get _labelBouton {
    return switch (_livraison['statut']) {
      'livreur_assigne' => '🚗 Partir collecter le colis',
      'en_collecte' => '📦 Colis collecté — Partir livrer',
      'en_livraison' => '📸 Prendre photo et marquer livré',
      _ => '',
    };
  }

  Color get _couleurBouton {
    return switch (_livraison['statut']) {
      'livreur_assigne' => Colors.blue,
      'en_collecte' => Colors.orange,
      'en_livraison' => Colors.green,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    final statut = _livraison['statut']?.toString() ?? '';

    return Scaffold(
      backgroundColor: CouleursTaama.sable,
      appBar: AppBar(
        title: const Text('Livraison en cours',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EcranChat(
                  roomName: _livraison['room_chat']?.toString() ??
                      'courier_${_livraison['id']}',
                  titreConversation: 'Client',
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Carte du trajet
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📦 Détails de la livraison',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  _LigneInfo('Catégorie',
                      _labelsCategorie[_livraison['categorie']] ??
                          '📦 Colis standard'),
                  const Divider(height: 20),
                  _LigneInfo('📍 Collecte',
                      _livraison['adresse_collecte']?.toString() ?? ''),
                  const Divider(height: 20),
                  _LigneInfo('🏁 Livraison',
                      _livraison['adresse_livraison']?.toString() ?? ''),
                  const Divider(height: 20),
                  _LigneInfo('📦 Colis',
                      _livraison['description_colis']?.toString() ?? ''),
                  const Divider(height: 20),
                  _LigneInfo('💰 Prix',
                      '${_livraison['prix'] ?? 0} FCFA'
                      '${_livraison['paye'] == true ? ' ✅ Payé' : ' • Non payé'}'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Barre de progression
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _BarreProgression(statut: statut),
            ),
            const SizedBox(height: 20),

            // Bouton action
            if (statut != 'livre' && statut != 'annule')
              ElevatedButton(
                onPressed: _enChargement
                    ? null
                    : statut == 'en_livraison'
                        ? _prendrePhotoEtLivrer
                        : () => _changerStatut(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _couleurBouton,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _enChargement
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_labelBouton,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
              ),
          ],
        ),
      ),
    );
  }
}

class _LigneInfo extends StatelessWidget {
  final String label;
  final String valeur;
  const _LigneInfo(this.label, this.valeur);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(valeur,
              style: TextStyle(
                  color: Colors.grey.shade700, fontSize: 13)),
        ),
      ],
    );
  }
}

class _BarreProgression extends StatelessWidget {
  final String statut;
  const _BarreProgression({required this.statut});

  @override
  Widget build(BuildContext context) {
    final etapes = [
      ('livreur_assigne', '✅', 'Assigné'),
      ('en_collecte', '🚗', 'Collecte'),
      ('en_livraison', '📦', 'Livraison'),
      ('livre', '🎉', 'Livré'),
    ];

    final indexActuel = etapes.indexWhere((e) => e.$1 == statut);

    return Column(
      children: [
        // Barre de progression
        Row(
          children: etapes.asMap().entries.map((entry) {
            final index = entry.key;
            final estPasse = index <= indexActuel;
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(
                    right: index < etapes.length - 1 ? 4 : 0),
                decoration: BoxDecoration(
                  color: estPasse ? Colors.orange : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        // Labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: etapes.asMap().entries.map((entry) {
            final index = entry.key;
            final (_, emoji, label) = entry.value;
            final estActuel = index == indexActuel;
            final estPasse = index < indexActuel;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        estActuel ? FontWeight.bold : FontWeight.normal,
                    color: estActuel
                        ? Colors.orange
                        : estPasse
                            ? Colors.green
                            : Colors.grey,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}
