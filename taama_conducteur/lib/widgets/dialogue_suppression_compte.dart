import 'package:flutter/material.dart';

/// Confirmation de suppression de compte : le conducteur doit taper le mot
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Cette action est IRRÉVERSIBLE. Ton nom, ton numéro, ta photo '
              'et tes documents de vérification seront effacés. Ton '
              'historique de courses est gardé sans ton identité.',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
          const SizedBox(height: 16),
          Text('Pour confirmer, tape ${widget.motAttendu} :'),
          const SizedBox(height: 8),
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
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          child: const Text('Supprimer définitivement'),
        ),
      ],
    );
  }
}
