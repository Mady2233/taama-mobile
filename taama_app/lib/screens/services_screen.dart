import 'package:flutter/material.dart';
import '../theme/couleurs_taama.dart';
import 'carte_screen.dart';
import 'courier_screen.dart';
import 'recherche_screen.dart';
import 'resultats_recherche_screen.dart';
import 'mes_demandes_planifiees_screen.dart';

class EcranServices extends StatefulWidget {
  const EcranServices({super.key});

  @override
  State<EcranServices> createState() => _EcranServicesState();
}

class _EcranServicesState extends State<EcranServices>
    with TickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _bientot() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: CouleursTaama.indigo.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.rocket_launch,
                  color: CouleursTaama.indigo, size: 28),
            ),
            const SizedBox(height: 16),
            const Text('Bientôt disponible 🚀',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: CouleursTaama.indigo)),
            const SizedBox(height: 8),
            Text(
              'Cette fonctionnalité arrive très bientôt.\nSois le premier à l\'utiliser !',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: CouleursTaama.indigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('OK, j\'attends !',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1C2B4A), Color(0xFF2D3B6A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header ───
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Services',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            )),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: CouleursTaama.terreCuite,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.local_fire_department,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('6 services actifs',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Partout, pour tout à Bamako',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13)),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ─── Contenu scrollable ───
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F6FA),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section Transport
                        _SectionTitre(
                          icone: Icons.directions_car,
                          titre: 'Transport',
                          couleur: CouleursTaama.indigo,
                        ),
                        const SizedBox(height: 12),
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.82,
                          children: [
                            _buildCarteAnimee(
                              index: 0,
                              service: _ServicePremium(
                                emoji: '🚗',
                                label: 'Course',
                                sousTitre: 'Voiture',
                                gradient: [
                                  const Color(0xFF1C2B4A),
                                  const Color(0xFF2D4A8A)
                                ],
                                badge: '-10%',
                                couleurBadge: CouleursTaama.terreCuite,
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(
                                        builder: (_) => const EcranCarte())),
                              ),
                            ),
                            _buildCarteAnimee(
                              index: 1,
                              service: _ServicePremium(
                                emoji: '🏍️',
                                label: 'Moto',
                                sousTitre: 'Rapide',
                                gradient: [
                                  const Color(0xFFC8623D),
                                  const Color(0xFFE07A50)
                                ],
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(
                                        builder: (_) => EcranCarte(
                                            typeVehiculeInitial: 'Moto'))),
                              ),
                            ),
                            _buildCarteAnimee(
                              index: 2,
                              service: _ServicePremium(
                                emoji: '📦',
                                label: 'Courier',
                                sousTitre: 'Colis',
                                gradient: [
                                  const Color(0xFFE65100),
                                  const Color(0xFFF57C00)
                                ],
                                badge: 'Nouveau',
                                couleurBadge: Colors.orange.shade700,
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const EcranCourier())),
                              ),
                            ),
                            _buildCarteAnimee(
                              index: 3,
                              service: _ServicePremium(
                                emoji: '📅',
                                label: 'Réserver',
                                sousTitre: 'Planifié',
                                gradient: [
                                  const Color(0xFF4A148C),
                                  const Color(0xFF6A1B9A)
                                ],
                                onTap: () async {
                                  final resultat = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const EcranRecherche()),
                                  );
                                  if (resultat != null && mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EcranDemandeInstantanee(
                                            destination: resultat.toString()),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                            _buildCarteAnimee(
                              index: 4,
                              service: _ServicePremium(
                                emoji: '⏰',
                                label: 'Planifier',
                                sousTitre: 'À l\'avance',
                                gradient: [
                                  const Color(0xFF006064),
                                  const Color(0xFF00838F)
                                ],
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const MesDemandesPlanifieesScreen())),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Bannière promo
                        _buildBannierePromo(),

                        const SizedBox(height: 24),

                        // Section Spécial
                        _SectionTitre(
                          icone: Icons.star,
                          titre: 'Bientôt disponible',
                          couleur: CouleursTaama.terreCuite,
                          sousTitre: 'En développement',
                        ),
                        const SizedBox(height: 12),
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.82,
                          children: [
                            _buildCarteBientot(
                                '👩', 'Femmes', 'Conductrices'),
                            _buildCarteBientot(
                                '👴', 'Seniors', 'Assistance'),
                            _buildCarteBientot(
                                '🚛', 'Cargo', 'Marchandises'),
                            _buildCarteBientot(
                                '🏫', 'Scolaire', 'Élèves'),
                            _buildCarteBientot(
                                '🏥', 'Médical', 'Urgences'),
                            _buildCarteBientot(
                                '✈️', 'Aéroport', 'Sénou'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCarteAnimee({
    required int index,
    required _ServicePremium service,
  }) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final delay = index * 0.08;
        final progress = ((_animController.value - delay) / 0.4)
            .clamp(0.0, 1.0);
        final curve = Curves.easeOutBack.transform(progress);
        return Transform.scale(
          scale: 0.7 + (0.3 * curve),
          child: Opacity(opacity: progress, child: child),
        );
      },
      child: _CartePremium(service: service),
    );
  }

  Widget _buildCarteBientot(
      String emoji, String label, String sousTitre) {
    return GestureDetector(
      onTap: _bientot,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(height: 6),
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.grey.shade600)),
                Text(sousTitre,
                    style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade400)),
              ],
            ).paddingAll(8),
            Positioned(
              top: 6, right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Bientôt',
                    style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannierePromo() {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const EcranCarte())),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFC8623D), Color(0xFFD4844A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: CouleursTaama.terreCuite.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('🔥 OFFRE SPÉCIALE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5)),
                  ),
                  const SizedBox(height: 6),
                  const Text('10% de réduction\nsur votre 1ère course',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          height: 1.2)),
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🚗', style: TextStyle(fontSize: 40)),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Réserver →',
                      style: TextStyle(
                          color: CouleursTaama.terreCuite,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Widget carte premium avec gradient ───
class _CartePremium extends StatefulWidget {
  final _ServicePremium service;
  const _CartePremium({required this.service});

  @override
  State<_CartePremium> createState() => _CartePremiumState();
}

class _CartePremiumState extends State<_CartePremium> {
  bool _appuye = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    return GestureDetector(
      onTapDown: (_) => setState(() => _appuye = true),
      onTapUp: (_) {
        setState(() => _appuye = false);
        s.onTap();
      },
      onTapCancel: () => setState(() => _appuye = false),
      child: AnimatedScale(
        scale: _appuye ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: s.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: s.gradient[0].withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Cercle décoratif en fond
              Positioned(
                bottom: -15, right: -15,
                child: Container(
                  width: 70, height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),

              // Contenu
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Emoji dans cercle blanc
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(s.emoji,
                            style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                    const Spacer(),
                    Text(s.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        )),
                    Text(s.sousTitre,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 10,
                        )),
                  ],
                ),
              ),

              // Badge
              if (s.badge != null)
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: s.couleurBadge ?? Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(s.badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        )),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Titre de section ───
class _SectionTitre extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String? sousTitre;
  final Color couleur;

  const _SectionTitre({
    required this.icone,
    required this.titre,
    required this.couleur,
    this.sousTitre,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icone, color: couleur, size: 16),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: couleur)),
            if (sousTitre != null)
              Text(sousTitre!,
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500)),
          ],
        ),
      ],
    );
  }
}

// ─── Modèle service ───
class _ServicePremium {
  final String emoji, label, sousTitre;
  final List<Color> gradient;
  final String? badge;
  final Color? couleurBadge;
  final VoidCallback onTap;

  const _ServicePremium({
    required this.emoji,
    required this.label,
    required this.sousTitre,
    required this.gradient,
    required this.onTap,
    this.badge,
    this.couleurBadge,
  });
}

// Extension utilitaire
extension WidgetPadding on Widget {
  Widget paddingAll(double value) =>
      Padding(padding: EdgeInsets.all(value), child: this);
}
