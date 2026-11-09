"""
Génère les rues nommées du Grand Bamako pour la recherche de l'app client :
  taama_app/lib/donnees/rues_bamako.dart

Une entrée par nom de voie et par quartier (ou localité) le plus proche : « Rue 40 »
existe dans plusieurs quartiers, « Avenue de l'O.U.A. » en traverse plusieurs. Le
point retenu est un vrai point de la voie (le plus proche de son centre) ; la
longueur cumulée dit à l'app s'il faut faire préciser le point sur la carte.

Fichier séparé : la carte et l'app chauffeur n'en dépendent pas.

Usage (depuis la racine du dépôt Taama_mobile) :
  python taama_app/tool/generer_rues_bamako.py

Mêmes règles que generer_localites_bamako.py : source unique OpenStreetMap, jamais
de donnée ajoutée à la main, et rien n'est écrit en cas d'échec ou de réponse trop
petite.
"""
import datetime
import json
import math
import os
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request

# Même zone que les localités (Kati, Kalaban Coro, Mountougoula compris).
ZONE = (12.48, -8.12, 12.77, -7.80)
SERVEURS = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
]
USER_AGENT = 'Taama/1.0 (generation des donnees de carte, Bamako)'
# Ni chemins, ni escaliers, ni voies en projet : jamais une destination de course.
TYPES_EXCLUS = {'footway', 'path', 'steps', 'cycleway', 'bridleway', 'construction', 'proposed',
                'raceway', 'corridor', 'platform', 'elevator', 'abandoned', 'disused'}
MIN_RUES = 300  # en dessous : réponse jugée incomplète, rien n'est écrit
# Le nom de la ville seul n'est pas une destination (même règle que les localités).
EXCLUS = {'bamako'}
# « Bamako - Dakar Transafrican Highway », « Bamako - Fana - Ségou - … » : noms
# d'itinéraires entre villes, jamais une destination dans Bamako.
ITINERAIRE = re.compile(r'\s[-–]\s')


def interroger():
    s, o, n, e = ZONE
    requete = f'[out:json][timeout:180];way["highway"]["name"]({s},{o},{n},{e});out geom tags;'
    donnees = urllib.parse.urlencode({'data': requete}).encode()
    derniere_erreur = None
    for serveur in SERVEURS:
        for essai in range(2):
            try:
                req = urllib.request.Request(serveur, data=donnees, headers={'User-Agent': USER_AGENT})
                with urllib.request.urlopen(req, timeout=240) as reponse:
                    return json.load(reponse)['elements']
            except Exception as exc:  # noqa: BLE001 — tout échec => on n'écrit rien
                derniere_erreur = exc
                time.sleep(10 * (essai + 1))
    raise SystemExit(f'Overpass indisponible ({type(derniere_erreur).__name__}) : rien écrit.')


def normaliser(nom):
    t = unicodedata.normalize('NFD', nom.lower())
    t = ''.join(c for c in t if unicodedata.category(c) != 'Mn')
    return re.sub(r'[^a-z0-9]+', ' ', t).strip()


def metres(a, b):
    """Distance (m) entre deux (lat, lng)."""
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371000 * math.asin(math.sqrt(h))


def zones_connues(dossier):
    """Quartiers de la carte et localités : (nom, lat, lng), pour rattacher chaque voie."""
    zones = []
    motifs = {
        'carte_bamako.dart': r"QuartierCarte\('((?:[^'\\]|\\.)*)', (-?[\d.]+), (-?[\d.]+),",
        'localites_bamako.dart': r"LocaliteCarte\('((?:[^'\\]|\\.)*)', (-?[\d.]+), (-?[\d.]+)\)",
    }
    for fichier, motif in motifs.items():
        with open(os.path.join(dossier, fichier), encoding='utf-8') as f:
            contenu = f.read()
        zones += [(n.replace("\\'", "'"), float(la), float(lo)) for n, la, lo in re.findall(motif, contenu)]
    if not zones:
        raise SystemExit('Aucun quartier lu dans carte_bamako.dart : rien écrit.')
    return zones


def zone_la_plus_proche(point, zones):
    return min(zones, key=lambda z: (z[1] - point[0]) ** 2 + ((z[2] - point[1]) * 0.976) ** 2)[0]


def milieu(points):
    """Point situé à mi-longueur de la voie."""
    longueurs = [metres(a, b) for a, b in zip(points, points[1:])]
    moitie, cumul = sum(longueurs) / 2, 0.0
    for point, longueur in zip(points, longueurs):
        if cumul + longueur >= moitie:
            return point
        cumul += longueur
    return points[-1]


def extraire(elements, zones):
    groupes = {}
    for el in elements:
        tags = el.get('tags', {})
        if tags.get('highway') in TYPES_EXCLUS:
            continue
        # OSM admet « nom1;nom2 » : le premier est le nom usuel.
        nom = (tags.get('name') or '').split(';')[0].strip()
        points = [(p['lat'], p['lon']) for p in el.get('geometry') or [] if p]
        if not nom or len(points) < 2 or not normaliser(nom):
            continue
        if normaliser(nom) in EXCLUS or ITINERAIRE.search(nom):
            continue
        zone = zone_la_plus_proche(milieu(points), zones)
        groupe = groupes.setdefault((normaliser(nom), zone), {'noms': {}, 'points': [], 'longueur': 0.0})
        groupe['noms'][nom] = groupe['noms'].get(nom, 0) + 1
        groupe['points'] += points
        groupe['longueur'] += sum(metres(a, b) for a, b in zip(points, points[1:]))

    rues = []
    for (cle, zone), g in groupes.items():
        nom = max(g['noms'], key=lambda n: (g['noms'][n], n))  # graphie la plus fréquente
        centre = (sum(p[0] for p in g['points']) / len(g['points']), sum(p[1] for p in g['points']) / len(g['points']))
        point = min(g['points'], key=lambda p: metres(p, centre))  # sur la voie, jamais à côté
        rues.append((cle, nom, zone, point[0], point[1], round(g['longueur'])))
    rues.sort(key=lambda r: (r[0], normaliser(r[2])))
    return [r[1:] for r in rues]


def echapper(texte):
    return texte.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')


def fichier_dart(rues, date):
    lignes = [
        '// GÉNÉRÉ par taama_app/tool/generer_rues_bamako.py — ne pas modifier',
        '// à la main (relancer le script).',
        '// Source : OpenStreetMap (© OpenStreetMap contributors, licence ODbL).',
        f'// Extraction du {date}. Zone : {ZONE}.',
        '',
        '/// Voie nommée, rattachée au quartier (ou à la localité) le plus proche.',
        '/// Utilisée par la recherche seulement.',
        'class RueCarte {',
        '  const RueCarte(this.nom, this.quartier, this.lat, this.lng, this.longueur);',
        '  final String nom;',
        '  final String quartier;',
        '',
        '  /// Un vrai point de la voie, le plus proche de son centre.',
        '  final double lat;',
        '  final double lng;',
        '',
        '  /// Longueur cumulée de la voie dans ce quartier, en mètres.',
        '  final int longueur;',
        '}',
        '',
        'const List<RueCarte> ruesBamako = [',
        *[f"  RueCarte('{echapper(n)}', '{echapper(z)}', {la:.6f}, {lo:.6f}, {lg})," for n, z, la, lo, lg in rues],
        '];',
        '',
    ]
    return '\n'.join(lignes)


def main():
    racine = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
    dossier = os.path.join(racine, 'taama_app', 'lib', 'donnees')
    rues = extraire(interroger(), zones_connues(dossier))
    if len(rues) < MIN_RUES:
        raise SystemExit(f'Seulement {len(rues)} rues (< {MIN_RUES}) : réponse jugée incomplète, rien écrit.')
    date = datetime.date.today().isoformat()
    contenu = fichier_dart(rues, date)
    with open(os.path.join(dossier, 'rues_bamako.dart'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(contenu)
    longues = sum(1 for r in rues if r[4] > 400)
    print(f'Extraction du {date} : {len(rues)} rues ({longues} de plus de 400 m), {len(contenu.encode("utf-8"))} octets.')


if __name__ == '__main__':
    sys.exit(main())
