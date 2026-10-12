# CLAUDE.md — Taama

Relu automatiquement à chaque session. Règles stables uniquement.
L'état courant du projet (chantiers ouverts, bugs connus, décisions récentes)
vit dans `CONTEXTE.md` : **le lire avant toute tâche**.

---

## 1. Ce qu'est Taama, et pourquoi ça compte pour le code

Taama est une plateforme de VTC et moto-taxi pour Bamako. C'est un produit
commercial : il doit gagner de l'argent face à Heetch, Yango et d'autres apps
déjà installées. On ne gagnera pas sur le budget marketing ni sur le nombre
de chauffeurs au départ. On gagne sur ce que les gros font mal ici :

- **Prix fixe annoncé avant la course**, jamais de surprise à l'arrivée.
- **Portefeuille Mobile Money** (Orange Money, Moov, Wave via PayDunya) :
  pas de monnaie à rendre.
- **La moto comme service de premier plan**, pas un ajout.
- **Léger et tolérant au réseau** : téléphones d'entrée de gamme, 3G instable,
  forfaits data chers.
- **Chauffeurs bien traités** : commission de 10 % claire, gains visibles.
- **Écrans beaux** : le client compare en dix secondes avec Heetch.

Conséquences directes pour chaque tâche :

- **La confiance est le produit.** Un seul prix faux, un double débit ou un
  nom de chauffeur qui fuite, et le client repart chez Heetch pour de bon.
  En cas de doute entre « ça marche » et « c'est sûr », choisir sûr.
- **Chaque octet réseau coûte à nos utilisateurs.** Pas de polling serré,
  pas de rechargement inutile, pas de payload gonflé.
- **Un écran cassé ou vide est un client perdu.** Aucun état sans issue.

---

## 2. Architecture

```
Taama_mobile/
├── taama_backend/     Django + DRF + Channels/Daphne, Redis, PostgreSQL
├── taama_app/         Flutter — application client
└── taama_conducteur/  Flutter — application chauffeur
```

- Hébergement : **Render** (pas PythonAnywhere, pas Railway).
  Démarrage via `entrypoint.sh` : migrate → collectstatic → exec daphne.
- Stockage : **Cloudflare R2**, deux buckets — privé (KYC, URLs signées)
  et public (avatars, URLs permanentes).
- Carte : `flutter_map` + OpenStreetMap, tuiles via `TaamaMapTiles`
  (`--dart-define`). Itinéraires OSRM, repli Haversine côté serveur.
- Temps réel : WebSocket `LocationConsumer` pour les positions chauffeur.
- Paiement : PayDunya (API PAR). SMS : Orange SMS.
- Thème client : `lib/theme/taama_theme.dart`, utilitaires dans
  `lib/utils/format.dart`. Aucune couleur hex en dur dans les écrans.

---

## 3. Règles de travail — non négociables

1. **Lire `CONTEXTE.md` avant de commencer.**
2. **Rapport puis diffs AVANT toute modification.** Attendre ma validation.
   Quand je dis « STOP », s'arrêter là.
3. **Jamais `git add`, jamais `git commit`, jamais `git push`.**
4. **Jamais `migrate` sur une base réelle** sans sauvegarde explicite et
   mon accord. Générer les migrations, ne pas les appliquer en prod.
5. **Un commit = un sujet.** Ne pas mélanger un correctif et un refactor.
6. **Rester dans le périmètre demandé.** Un problème vu hors périmètre :
   le signaler, ne pas le corriger en douce.
7. **Signaler ce qui ne marche pas.** Si un correctif demandé est impossible
   ou dangereux, le dire et expliquer, plutôt que livrer une version dégradée.

---

## 4. Argent — règles absolues

- `Decimal`, jamais `float`, pour tout montant.
- `select_for_update()` sur **toute** écriture financière (portefeuille,
  paiement, commission, recharge).
- **Prix toujours calculé côté serveur.** Jamais accepter un montant envoyé
  par l'app.
- **Montants figés à la création** d'une demande, jamais recalculés après coup.
- Traitements de paiement **idempotents** : un même token PayDunya ne crédite
  jamais deux fois.
- Callback PayDunya : vérifier le hash SHA-512 de la MasterKey, comparer le
  montant reçu au montant attendu. Créditer depuis le callback (IPN), jamais
  depuis la `return_url`.
- **Fail-closed** : en cas de doute ou d'erreur, refuser l'opération.

---

## 5. Données et vie privée

- **Ne jamais inventer de données.** Pas de distance, prix, promo, nom ou
  position factice en cas d'échec. Pas de GPS → pas d'estimation, message
  d'erreur et bouton Réessayer, commande bloquée.
- **Identité chauffeur** : `nom_court` (« Mady T. ») tant que la demande n'est
  pas acceptée, `nom_complet` après. Jamais de téléphone ni de nom complet sur
  un endpoint accessible avant acceptation. `prenom` n'est jamais exposé brut.
- Position d'un chauffeur acceptée **uniquement** depuis son WebSocket
  authentifié ; rejeter les sauts impossibles (> 150 km/h).
- `conducteurs/proches/` : rayon plafonné côté serveur, nombre de résultats
  limité.
- Secrets **uniquement** en variables d'environnement. Aucune clé, aucun token
  dans le code, les tests, les commentaires ou les logs.

---

## 6. Conventions Flutter

- Tout appel HTTP a `.timeout(Duration(seconds: 12))`.
- Tout indicateur de chargement est remis à `false` dans un `finally`.
- `if (!mounted) return;` après chaque `await` avant `setState`.
- **Aucun spinner sans issue, aucun écran vide sans message.** Chaque état
  (chargement, vide, erreur) a un rendu explicite.
- Jamais afficher `null` : masquer le segment si la valeur est vide.
- Écrans présentationnels (données par paramètres, actions par callbacks),
  logique dans un `*_page.dart` séparé.
- Un bouton sans action câblée n'est pas affiché, jamais affiché-mais-inerte.
- Clavier : `resizeToAvoidBottomInset` + `SingleChildScrollView` sur tout
  écran avec saisie.
- Respecter `MediaQuery.disableAnimationsOf` pour les animations.
- `flutter analyze` doit rester vert (les 3 infos préexistantes tolérées).

---

## 7. Conventions Django

- Tests verts avant de rendre : toute la suite, pas seulement le fichier touché.
- Un test par cas limite ajouté (vide, nul, inversé, concurrent).
- Serializers construits champ par champ sur les endpoints publics, pour
  savoir exactement ce qui sort.
- Logs sans données personnelles ni secrets.

---

## 8. Pièges déjà rencontrés — vérifier avant de corriger

- **Des fichiers `*_legacy.dart` coexistent avec les nouveaux.** Avant de
  corriger un bug d'affichage, vérifier que le fichier modifié est bien celui
  rendu à l'écran (tracer la navigation). Un bug « corrigé » qui reste
  identique au pixel près = mauvais fichier.
- **Render ne recharge pas les variables d'environnement** sans redéploiement.
- Commits non poussés = cause la plus fréquente d'un déploiement « qui ne
  prend pas ».
- `flutter_map` 8.x : `TileLayer` n'a pas de `backgroundColor`.
- `share_plus` 11 : `SharePlus.instance.share(ShareParams(...))`,
  pas `Share.share()`.
- Scripts `.sh` en fin de ligne LF (`.gitattributes`), le dev se fait sous
  Windows / PowerShell.

---

## 9. Définition de « terminé »

- [ ] Le rapport et les diffs ont été montrés avant application.
- [ ] `flutter analyze` vert et/ou suite de tests backend verte.
- [ ] Chaque état de l'écran touché (chargement, vide, erreur, succès) rendu.
- [ ] Aucune donnée inventée, aucun secret, aucune fuite d'identité.
- [ ] Rien de commité.
- [ ] Améliorations possibles (perf, sécurité, architecture) proposées à la fin.
