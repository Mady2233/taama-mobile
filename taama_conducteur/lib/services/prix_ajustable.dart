// lib/services/prix_ajustable.dart
//
// Prix d'une course que le chauffeur peut ajuster avant d'accepter. Les
// limites viennent du serveur (`prix_ajustable` de la demande) ; l'app ne fait
// que se déplacer entre elles, et le serveur revérifie le prix envoyé.

/// Limites d'un autre prix : prix standard, minimum, maximum et pas (100 F).
/// Montants de la course AVANT promo, en francs entiers.
class PrixAjustable {
  const PrixAjustable({
    required this.standard,
    required this.min,
    required this.max,
    required this.pas,
  });

  final int standard;
  final int min;
  final int max;
  final int pas;

  /// Null quand le serveur n'en envoie pas (fonction coupée, app du client
  /// trop ancienne, course trop courte…) ou si les limites sont incohérentes :
  /// l'écran n'affiche alors ni − ni +, seulement « Accepter ».
  static PrixAjustable? depuisJson(Object? brut) {
    if (brut is! Map) return null;
    int? lire(String cle) => (brut[cle] as num?)?.toInt();
    final standard = lire('standard');
    final min = lire('min');
    final max = lire('max');
    final pas = lire('pas');
    if (standard == null || min == null || max == null || pas == null || pas <= 0) return null;
    if (min > standard || max < standard || (min == standard && max == standard)) return null;
    return PrixAjustable(standard: standard, min: min, max: max, pas: pas);
  }

  bool peutBaisser(int prix) => prix - pas >= min;
  bool peutMonter(int prix) => prix + pas <= max;
  int baisser(int prix) => peutBaisser(prix) ? prix - pas : prix;
  int monter(int prix) => peutMonter(prix) ? prix + pas : prix;
}
