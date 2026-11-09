// lib/utils/dates.dart
//
// Dates en français, sans dépendance intl : « Aujourd'hui », « Hier »,
// « mardi 4 novembre », « 14:32 ».

const List<String> _jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const List<String> _mois = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);

/// « Aujourd'hui », « Hier », « mardi 4 novembre » (année ajoutée si ce n'est
/// pas l'année en cours).
String libelleJour(DateTime jour, {DateTime? maintenant}) {
  final aujourdhui = _jour(maintenant ?? DateTime.now());
  final j = _jour(jour);
  if (j == aujourdhui) return 'Aujourd’hui';
  if (j == aujourdhui.subtract(const Duration(days: 1))) return 'Hier';
  final base = '${_jours[j.weekday - 1]} ${j.day} ${_mois[j.month - 1]}';
  return j.year == aujourdhui.year ? base : '$base ${j.year}';
}

/// « 14:32 ».
String heureMinute(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// « mardi 4 novembre 2026 à 14:32 ».
String dateHeureComplete(DateTime d) =>
    '${_jours[d.weekday - 1]} ${d.day} ${_mois[d.month - 1]} ${d.year} à ${heureMinute(d)}';
