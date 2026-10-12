import 'package:flutter/material.dart';
import '../theme/taama_theme.dart';

/// Confirmation de suppression de compte : l'utilisateur doit taper le mot
/// [motAttendu]. Un simple « OK » ne suffit pas pour une action
/// irréversible. Renvoie true seulement si le mot est correct.
Future<bool> demanderConfirmationSuppression(BuildContext context,
    {String motAttendu = 'SUPPRIMER'}) async {
  final confirme = await showDialog<bool>(
    context: context,
    builder: (_) => _DialogueSuppression(motAttendu: motAttendu),
  );
  return confirme ?? false;
}

class _DialogueSuppression extends StatefulWidget {
  final String motAttendu;
  const _DialogueSuppression({required this.motAttendu});

  @override
  State<_DialogueSuppression> createState() => _DialogueSuppressionState();
}

class _DialogueSuppressionState extends State<_DialogueSuppression> {
  final _controleur = TextEditingController();

  bool get _motCorrect =>
      _controleur.text.trim().toUpperCase() == widget.motAttendu;

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true, // le clavier ne masque pas le champ
      title: const Text('Supprimer mon compte'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(TaamaSpacing.md),
            decoration: BoxDecoration(
              color: TaamaColors.dangerSoft,
              borderRadius: BorderRadius.circular(TaamaRadius.md),
            ),
            child: const Text(
              'Cette action est IRRÉVERSIBLE. Ton nom, ton numéro et tes '
              'adresses seront effacés. Ton historique de courses est gardé '
              'sans ton identité.',
              style: TextStyle(color: TaamaColors.danger),
            ),
          ),
          const SizedBox(height: TaamaSpacing.lg),
          Text('Pour confirmer, tape ${widget.motAttendu} :'),
          const SizedBox(height: TaamaSpacing.sm),
          TextField(
            controller: _controleur,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: _motCorrect ? () => Navigator.pop(context, true) : null,
          style: TextButton.styleFrom(foregroundColor: TaamaColors.danger),
          child: const Text('Supprimer définitivement'),
        ),
      ],
    );
  }
}
