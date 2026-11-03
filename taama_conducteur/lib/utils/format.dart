// lib/utils/format.dart
//
// Affichage des montants, identique à l'app client (taama_app/lib/utils/format.dart).

/// « 12 500 F » — espaces fines insécables, sans dépendance intl.
String formaterFcfa(int montant) {
  final negatif = montant < 0;
  final chiffres = montant.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < chiffres.length; i++) {
    final restant = chiffres.length - i;
    buffer.write(chiffres[i]);
    if (restant > 1 && restant % 3 == 1) buffer.write(' ');
  }
  return '${negatif ? '-' : ''}$buffer F';
}

/// Montant lu dans une réponse de l'API (entier, décimal ou texte). Null si
/// absent ou illisible : l'écran masque le segment, jamais « null ».
String? formaterFcfaApi(Object? valeur) {
  final montant = valeur is num ? valeur : num.tryParse('$valeur');
  if (montant == null || !montant.isFinite) return null;
  return formaterFcfa(montant.round());
}
