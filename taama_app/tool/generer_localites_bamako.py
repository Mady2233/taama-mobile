"""
Génère les localités du Grand Bamako absentes de carte_bamako.dart (villes, villages,
hameaux, quartiers hors de l'emprise de la carte), pour la recherche de l'app client :
  taama_app/lib/donnees/localites_bamako.dart

Fichier séparé : la carte et l'app chauffeur n'en dépendent pas.

Usage (depuis la racine du dépôt Taama_mobile) :
  python taama_app/tool/generer_localites_bamako.py

Mêmes règles que generer_donnees_carte.py : source unique OpenStreetMap, jamais de
donnée ajoutée à la main, et rien n'est écrit en cas d'échec ou de réponse trop petite.
"""
import datetime
import json
import os
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request

# sud, ouest, nord, est : assez large pour Kati et Mountougoula, assez étroit pour
# écarter les villages homonymes éloignés (un Ntomikorobougou à plus de 20 km au nord).
ZONE = (12.48, -8.12, 12.77, -7.80)
SERVEURS = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
]
USER_AGENT = 'Taama/1.0 (generation des donnees de carte, Bamako)'
TYPES = 'suburb|quarter|neighbourhood|city|town|village|hamlet|locality'
# Le centre de « Bamako » n'est pas une destination : prix calculé sur un point arbitraire.
EXCLUS = {'bamako'}
MIN_LOCALITES = 30  # en dessous : réponse jugée incomplète, rien n'est écrit
MEME_LIEU_DEGRES = 0.0135  # ~1,5 km : au-delà, deux lieux de même nom sont distincts


def interroger():
    s, o, n, e = ZONE
    requete = f'[out:json][timeout:120];nwr["place"~"^({TYPES})$"]["name"]({s},{o},{n},{e});out center tags;'
    donnees = urllib.parse.urlencode({'data': requete}).encode()
    derniere_erreur = None
    for serveur in SERVEURS:
        for essai in range(2):
            try:
                req = urllib.request.Request(serveur, data=donnees, headers={'User-Agent': USER_AGENT})
                with urllib.request.urlopen(req, timeout=180) as reponse:
                    return json.load(reponse)['elements']
            except Exception as exc:  # noqa: BLE001 — tout échec => on n'écrit rien
                derniere_erreur = exc
                time.sleep(10 * (essai + 1))
    raise SystemExit(f'Overpass indisponible ({type(derniere_erreur).__name__}) : rien écrit.')


def normaliser(nom):
    t = unicodedata.normalize('NFD', nom.lower())
    t = ''.join(c for c in t if unicodedata.category(c) != 'Mn')
    return re.sub(r'[^a-z0-9]+', ' ', t).strip()


def proche(a, b):
    return abs(a[0] - b[0]) <= MEME_LIEU_DEGRES and abs(a[1] - b[1]) <= MEME_LIEU_DEGRES


def lieux_de_la_carte(chemin):
    """Quartiers déjà connus de la carte : (nom normalisé, lat, lng)."""
    with open(chemin, encoding='utf-8') as f:
        contenu = f.read()
    motif = r"QuartierCarte\('((?:[^'\\]|\\.)*)', (-?[\d.]+), (-?[\d.]+),"
    return [(normaliser(n.replace("\\'", "'")), float(la), float(lo)) for n, la, lo in re.findall(motif, contenu)]


def extraire(elements, connus):
    gardes = []
    for el in elements:
        tags = el.get('tags', {})
        # OSM admet « nom1;nom2 » : le premier est le nom usuel.
        nom = (tags.get('name') or '').split(';')[0].strip()
        centre = el if 'lat' in el else el.get('center')
        if not nom or not centre:
            continue
        cle = normaliser(nom)
        point = (centre['lat'], centre['lon'])
        if not cle or cle in EXCLUS:
            continue
        if any(c == cle and proche(point, (la, lo)) for c, la, lo in connus):
            continue
        if any(c == cle and proche(point, (la, lo)) for c, _, la, lo in gardes):
            continue
        gardes.append((cle, nom, point[0], point[1]))
    gardes.sort(key=lambda g: g[0])
    return [(nom, la, lo) for _, nom, la, lo in gardes]


def echapper(texte):
    return texte.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')


def fichier_dart(localites, date):
    lignes = [
        '// GÉNÉRÉ par taama_app/tool/generer_localites_bamako.py — ne pas modifier',
        '// à la main (relancer le script).',
        '// Source : OpenStreetMap (© OpenStreetMap contributors, licence ODbL).',
        f'// Extraction du {date}. Zone : {ZONE}.',
        '',
        '/// Lieu habité absent de carte_bamako.dart. Utilisé par la recherche seulement.',
        'class LocaliteCarte {',
        '  const LocaliteCarte(this.nom, this.lat, this.lng);',
        '  final String nom;',
        '  final double lat;',
        '  final double lng;',
        '}',
        '',
        'const List<LocaliteCarte> localitesBamako = [',
        *[f"  LocaliteCarte('{echapper(n)}', {la:.6f}, {lo:.6f})," for n, la, lo in localites],
        '];',
        '',
    ]
    return '\n'.join(lignes)


def main():
    racine = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
    dossier = os.path.join(racine, 'taama_app', 'lib', 'donnees')
    connus = lieux_de_la_carte(os.path.join(dossier, 'carte_bamako.dart'))
    localites = extraire(interroger(), connus)
    if len(localites) < MIN_LOCALITES:
        raise SystemExit(f'Seulement {len(localites)} localités (< {MIN_LOCALITES}) : réponse jugée incomplète, rien écrit.')
    date = datetime.date.today().isoformat()
    contenu = fichier_dart(localites, date)
    with open(os.path.join(dossier, 'localites_bamako.dart'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(contenu)
    print(f'Extraction du {date} : {len(localites)} localités, {len(contenu.encode("utf-8"))} octets.')


if __name__ == '__main__':
    sys.exit(main())
