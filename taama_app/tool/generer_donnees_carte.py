"""
Génère les données de carte (quartiers et repères de Bamako) à partir
d'OpenStreetMap, pour les deux apps :
  taama_app/lib/donnees/carte_bamako.dart
  taama_conducteur/lib/donnees/carte_bamako.dart

Usage (depuis la racine du dépôt Taama_mobile) :
  python taama_app/tool/generer_donnees_carte.py

Règles :
- source unique : OpenStreetMap (© OpenStreetMap contributors, ODbL), via
  l'API Overpass ; jamais de donnée ajoutée ou corrigée à la main ;
- en cas d'échec (réseau, serveur surchargé, réponse invalide) ou de
  données anormalement petites, RIEN n'est écrit : les fichiers existants
  restent intacts ;
- affiche le compte par catégorie, à reporter dans CONTEXTE.md avec la date.
"""
import datetime
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

EMPRISE = (12.50, -8.10, 12.72, -7.85)  # sud, ouest, nord, est (Bamako)
SERVEURS = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
]
USER_AGENT = 'Taama/1.0 (generation des donnees de carte, Bamako)'
MIN_QUARTIERS = 50  # en dessous : réponse jugée incomplète, rien n'est écrit

# Catégorie Taama -> (tags OSM (clé, valeur), importance : 1 = la plus forte).
# L'ORDRE compte : à importance égale, une catégorie plus haut dans la liste
# passe devant quand deux étiquettes se disputent la même place à l'écran
# (on se repère à Bamako par les pharmacies et les écoles avant les bureaux).
CATEGORIES = {
    'marche': ([('amenity', 'marketplace')], 1),
    'hopital': ([('amenity', 'hospital')], 1),
    'gare': ([('amenity', 'bus_station')], 1),
    'universite': ([('amenity', 'university')], 1),
    'centreCommercial': ([('shop', 'mall')], 1),
    'pont': ([('man_made', 'bridge')], 1),
    'stade': ([('leisure', 'stadium')], 1),
    'parc': ([('leisure', 'park')], 1),
    'clinique': ([('amenity', 'clinic')], 2),
    'culte': ([('amenity', 'place_of_worship')], 2),
    'carburant': ([('amenity', 'fuel')], 2),
    'banque': ([('amenity', 'bank')], 2),
    'police': ([('amenity', 'police')], 2),
    'hotel': ([('tourism', 'hotel')], 2),
    'supermarche': ([('shop', 'supermarket')], 2),
    'mairie': ([('amenity', 'townhall'), ('amenity', 'courthouse')], 2),
    'ambassade': ([('office', 'diplomatic')], 2),
    'poste': ([('amenity', 'post_office')], 2),
    'pharmacie': ([('amenity', 'pharmacy')], 3),
    'ecole': ([('amenity', 'school'), ('amenity', 'college'), ('amenity', 'kindergarten')], 3),
    'restaurant': ([('amenity', 'restaurant'), ('amenity', 'cafe')], 3),
    # Pas office=telecommunication : à Bamako, surtout des armoires et
    # chambres du réseau (« CH L3T À CRÉER »), pas des agences.
    'agence': ([('shop', 'mobile_phone'), ('amenity', 'money_transfer'),
                ('amenity', 'bureau_de_change')], 3),
    'bureau': ([('office', 'company'), ('office', 'ngo'), ('office', 'insurance'), ('office', 'yes')], 3),
    'administration': ([('office', 'government')], 3),
}
ORDRE = {c: i for i, c in enumerate(CATEGORIES)}

# office=government est très bruité à Bamako (boutiques, équipements réseau) :
# seuls les noms d'administrations sont gardés. Règle sur le NOM, jamais une
# donnée ajoutée ou corrigée à la main.
MOTS_ADMINISTRATION = re.compile(
    r'\b(minist[eè]re|direction|agence|office|institut|inspection|pr[ée]fecture|'
    r'gouvernorat|assembl[ée]e|primature|pr[ée]sidence|douanes?|imp[oô]ts|tr[ée]sor|'
    r'commissariat|conseil|secr[ée]tariat|caisse|commission|autorit[ée]|d[ée]l[ée]gation|'
    r'haut[e]? |cellule|cour |tribunal|mairie|ambassade|consulat|police|gendarmerie|'
    r'protection civile|centre national|observatoire|recensement|cadastre|domaines)\b',
    re.IGNORECASE)
FILTRES = {('office', 'government'): MOTS_ADMINISTRATION}

# Éléments du réseau télécom importés avec un nom de chantier : jamais affichés.
BRUIT = re.compile(r'(\b[àa] cr[ée]{1,2}r\b|splitter|\bmsan\b|^ch [a-z]\d)', re.IGNORECASE)

# Un lieu qui ne porte que le nom de la ville n'aide ni sur la carte ni dans
# la recherche (« Bamako » n'est pas une destination).
NOMS_VILLE = {'bamako'}


def requete():
    s, o, n, e = EMPRISE
    bbox = f'({s},{o},{n},{e})'
    lignes = [f'nwr["place"~"^(suburb|quarter|neighbourhood)$"]["name"]{bbox};']
    for tags, _ in CATEGORIES.values():
        for cle, valeur in tags:
            lignes.append(f'nwr["{cle}"="{valeur}"]["name"]{bbox};')
    return '[out:json][timeout:120];(' + ''.join(lignes) + ');out center tags;'


def interroger():
    donnees = urllib.parse.urlencode({'data': requete()}).encode()
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


def position(element):
    if 'lat' in element:
        return element['lat'], element['lon']
    centre = element.get('center')
    return (centre['lat'], centre['lon']) if centre else (None, None)


def dans_emprise(lat, lng):
    s, o, n, e = EMPRISE
    return lat is not None and s <= lat <= n and o <= lng <= e


def echapper(texte):
    return texte.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')


def extraire(elements):
    quartiers, reperes, vus = [], [], set()
    for el in elements:
        tags = el.get('tags', {})
        nom = (tags.get('name') or '').strip()
        lat, lng = position(el)
        if not nom or not dans_emprise(lat, lng):
            continue
        place = tags.get('place')
        if place in ('suburb', 'quarter', 'neighbourhood'):
            cle = ('q', nom)
            if cle not in vus:
                vus.add(cle)
                quartiers.append((nom, lat, lng, place == 'suburb'))
            continue
        if BRUIT.search(nom) or nom.lower() in NOMS_VILLE:
            continue
        for categorie, (couples, _) in CATEGORIES.items():
            if any(tags.get(k) == v and (FILTRES.get((k, v)) is None or FILTRES[(k, v)].search(nom))
                   for k, v in couples):
                cle = (categorie, nom, round(lat, 4), round(lng, 4))
                if cle not in vus:
                    vus.add(cle)
                    reperes.append((nom, lat, lng, categorie))
                break
    quartiers.sort(key=lambda q: q[0].lower())
    reperes.sort(key=lambda r: (CATEGORIES[r[3]][1], ORDRE[r[3]], r[0].lower()))
    return quartiers, reperes


def fichier_dart(quartiers, reperes, date):
    lignes = [
        '// GÉNÉRÉ par taama_app/tool/generer_donnees_carte.py — ne pas modifier',
        '// à la main (relancer le script).',
        '// Source : OpenStreetMap (© OpenStreetMap contributors, licence ODbL).',
        f'// Extraction du {date}. Emprise : Bamako {EMPRISE}.',
        '',
        '/// Grand quartier (place=suburb) ou sous-quartier (quarter, neighbourhood).',
        'class QuartierCarte {',
        '  const QuartierCarte(this.nom, this.lat, this.lng, {required this.principal});',
        '  final String nom;',
        '  final double lat;',
        '  final double lng;',
        '  final bool principal;',
        '}',
        '',
        'enum CategorieRepere {',
        *[f'  {c},' for c in CATEGORIES],
        '}',
        '',
        '/// Importance d\'une catégorie : 1 (grands repères) à 3 (pharmacies,',
        '/// écoles, bureaux…). À importance égale, l\'ordre de l\'enum départage.',
        'const Map<CategorieRepere, int> importanceRepere = {',
        *[f'  CategorieRepere.{c}: {imp},' for c, (_, imp) in CATEGORIES.items()],
        '};',
        '',
        'class RepereCarte {',
        '  const RepereCarte(this.nom, this.lat, this.lng, this.categorie);',
        '  final String nom;',
        '  final double lat;',
        '  final double lng;',
        '  final CategorieRepere categorie;',
        '}',
        '',
        f'const String dateExtractionCarte = \'{date}\';',
        '',
        'const List<QuartierCarte> quartiersBamako = [',
        *[f"  QuartierCarte('{echapper(n)}', {la:.6f}, {lo:.6f}, principal: {'true' if p else 'false'}),"
          for n, la, lo, p in quartiers],
        '];',
        '',
        'const List<RepereCarte> reperesBamako = [',
        *[f"  RepereCarte('{echapper(n)}', {la:.6f}, {lo:.6f}, CategorieRepere.{c}),"
          for n, la, lo, c in reperes],
        '];',
        '',
    ]
    return '\n'.join(lignes)


def main():
    racine = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
    elements = interroger()
    quartiers, reperes = extraire(elements)
    if len(quartiers) < MIN_QUARTIERS:
        raise SystemExit(f'Seulement {len(quartiers)} quartiers reçus (< {MIN_QUARTIERS}) : réponse jugée incomplète, rien écrit.')
    date = datetime.date.today().isoformat()
    contenu = fichier_dart(quartiers, reperes, date)
    for app in ('taama_app', 'taama_conducteur'):
        dossier = os.path.join(racine, app, 'lib', 'donnees')
        os.makedirs(dossier, exist_ok=True)
        with open(os.path.join(dossier, 'carte_bamako.dart'), 'w', encoding='utf-8', newline='\n') as f:
            f.write(contenu)
    print(f'Extraction du {date} : {len(quartiers)} quartiers '
          f'({sum(1 for q in quartiers if q[3])} grands), {len(reperes)} repères.')
    compte = {}
    for _, _, _, c in reperes:
        compte[c] = compte.get(c, 0) + 1
    for c in CATEGORIES:
        print(f'  {c:17s} {compte.get(c, 0)}')
    print(f'Taille du fichier : {len(contenu.encode("utf-8"))} octets.')


if __name__ == '__main__':
    sys.exit(main())
