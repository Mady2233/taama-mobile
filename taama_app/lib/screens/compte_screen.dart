import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';
import 'profil_screen.dart';
import 'portefeuille_screen.dart';
import 'mes_reservations_screen.dart';
import 'mes_conversations_client_screen.dart';
import 'avis_app_screen.dart';
import 'connexion_screen.dart';
import '../theme/taama_theme.dart';
import '../widgets/dialogue_suppression_compte.dart';

class EcranCompte extends StatefulWidget {
  const EcranCompte({super.key});

  @override
  State<EcranCompte> createState() => _EcranCompteState();
}

class _EcranCompteState extends State<EcranCompte> {
  Map<String, dynamic>? _profil;
  bool _suppressionEnCours = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final profil = await ApiService.monProfil();
      if (mounted) setState(() => _profil = profil);
    } catch (_) {}
  }

  String _premierChiffre(String telephone) {
    final chiffres = telephone.replaceAll(RegExp(r'[^0-9]'), '');
    return chiffres.isNotEmpty ? chiffres[0] : '?';
  }

  Future<void> _deconnecter() async {
    await ApiService.definirToken('');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const EcranConnexion()),
      (route) => false,
    );
  }

  Future<void> _supprimerCompte() async {
    if (!await demanderConfirmationSuppression(context)) return;
    if (!mounted) return;
    setState(() => _suppressionEnCours = true);
    String messageFinal;
    try {
      await ApiService.supprimerMonCompte();
      messageFinal = 'Ton compte a été supprimé.';
    } on SuppressionCompteRefuseeException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        duration: const Duration(seconds: 8),
      ));
      return;
    } on SessionInvalideException {
      messageFinal = "Ta session n'est plus valide. Si tu venais de demander "
          'la suppression, elle a bien été prise en compte.';
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Impossible de joindre Taama. Vérifie ta connexion et réessaie.'),
      ));
      return;
    } finally {
      if (mounted) setState(() => _suppressionEnCours = false);
    }
    if (!mounted) return;
    final messager = ScaffoldMessenger.of(context);
    await _deconnecter();
    messager.showSnackBar(SnackBar(content: Text(messageFinal)));
  }

  @override
  Widget build(BuildContext context) {
    final nom = '${_profil?['first_name'] ?? ''} ${_profil?['last_name'] ?? ''}'.trim();
    final tel = _profil?['telephone']?.toString() ?? '';
    final initiales = nom.isNotEmpty
        ? nom.split(' ').take(2).map((e) => e[0].toUpperCase()).join()
        : _premierChiffre(tel);

    return Scaffold(
      backgroundColor: CouleursTaama.sable,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Header profil
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: CouleursTaama.indigo,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: CouleursTaama.terreCuite,
                      child: Text(initiales,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nom.isEmpty ? 'Mon compte' : nom,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18),
                          ),
                          Text(tel,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white70),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const EcranProfil()),
                        );
                        _charger();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Menu items
              _buildSection('Mon compte', [
                _buildItem(Icons.account_balance_wallet, 'Mon portefeuille',
                    CouleursTaama.or, () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) =>
                            const EcranPortefeuille(estChauffeur: false)))),
                _buildItem(Icons.event_seat, 'Mes réservations',
                    CouleursTaama.indigo, () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) =>
                            const EcranMesReservations()))),
                _buildItem(Icons.chat_bubble, 'Mes messages',
                    Colors.green, () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) =>
                            const MesConversationsClientScreen()))),
              ]),
              const SizedBox(height: 16),
              _buildSection('Taama', [
                _buildItem(Icons.star_rate, 'Donner mon avis',
                    CouleursTaama.or, () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) =>
                            const EcranAvisApp()))),
                _buildItem(Icons.help_outline, 'Aide & Support',
                    Colors.blue, () {}),
                _buildItem(Icons.privacy_tip_outlined,
                    'Politique de confidentialité',
                    Colors.grey, () {}),
              ]),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFEEEE),
                    child: Icon(Icons.logout, color: Colors.red),
                  ),
                  title: const Text('Se déconnecter',
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold)),
                  onTap: _deconnecter,
                ),
              ),
              const SizedBox(height: 24),
              // Volontairement discret et séparé de « Se déconnecter » :
              // action irréversible, protégée par une saisie de confirmation.
              TextButton.icon(
                onPressed: _suppressionEnCours ? null : _supprimerCompte,
                style: TextButton.styleFrom(
                    foregroundColor: TaamaColors.danger),
                icon: _suppressionEnCours
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.delete_forever_outlined),
                label: const Text('Supprimer mon compte'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String titre, List<Widget> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(titre,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    fontSize: 12)),
          ),
          ...items,
        ],
      ),
    );
  }

  Widget _buildItem(IconData icone, String label, Color couleur,
      VoidCallback onTap) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: couleur.withValues(alpha: 0.12),
        child: Icon(icone, color: couleur, size: 20),
      ),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}
