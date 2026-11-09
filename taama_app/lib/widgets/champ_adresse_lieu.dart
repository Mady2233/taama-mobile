// lib/widgets/champ_adresse_lieu.dart
//
// Champ d'adresse avec les suggestions locales de lieux, sans réseau. Un lieu
// choisi garde ses coordonnées ; toute modification du texte les oublie.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/preciser_point_rue.dart';
import '../services/recherche_lieux.dart';
import '../theme/taama_theme.dart';

// Le clavier est ouvert et le champ est dans un dialogue : peu de place.
const int _maxSuggestions = 4;

class ChampAdresseLieu extends StatefulWidget {
  const ChampAdresseLieu({
    super.key,
    required this.controleur,
    required this.onLieu,
    required this.longueurMax,
    this.decoration = const InputDecoration(),
    this.validator,
    this.autofocus = false,
    this.onValider,
  });

  final TextEditingController controleur;

  /// Lieu choisi, ou null dès que le texte est modifié à la main.
  final ValueChanged<LieuTrouve?> onLieu;
  final int longueurMax;
  final InputDecoration decoration;
  final FormFieldValidator<String>? validator;
  final bool autofocus;
  final VoidCallback? onValider;

  @override
  State<ChampAdresseLieu> createState() => _ChampAdresseLieuState();
}

class _ChampAdresseLieuState extends State<ChampAdresseLieu> {
  List<LieuTrouve> _suggestions = const [];

  void _surSaisie(String texte) {
    widget.onLieu(null);
    setState(() => _suggestions = rechercherLieux(texte, max: _maxSuggestions));
  }

  /// Une longue voie se précise d'abord sur la carte : une adresse enregistrée
  /// (domicile, travail) garde ainsi le bon point.
  Future<void> _choisir(LieuTrouve lieu) async {
    final choisi = await preciserSiNecessaire(context, lieu);
    if (choisi == null || !mounted) return;
    widget.controleur.value = TextEditingValue(
      text: choisi.adresse,
      selection: TextSelection.collapsed(offset: choisi.adresse.length),
    );
    widget.onLieu(choisi);
    setState(() => _suggestions = const []);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controleur,
          autofocus: widget.autofocus,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          inputFormatters: [LengthLimitingTextInputFormatter(widget.longueurMax)],
          decoration: widget.decoration,
          validator: widget.validator,
          onChanged: _surSaisie,
          onFieldSubmitted: (_) => widget.onValider?.call(),
        ),
        for (final lieu in _suggestions)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_rounded, color: TaamaColors.primary),
            title: Text(lieu.nom, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(lieu.detail, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _choisir(lieu),
          ),
      ],
    );
  }
}
