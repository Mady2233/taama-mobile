#!/usr/bin/env bash
# outils/controles/verifier_commit.sh — contrôles avant un commit des apps,
# sans rien commiter. À lancer depuis le dépôt, une fois les fichiers mis en
# attente (git add).
#
# Usage : outils/controles/verifier_commit.sh [taama_app] [taama_conducteur]
#   Sans argument : les apps touchées par ce qui est en attente.
#
# 1. ce qui est en attente et ses statistiques ;
# 2. recherche de secrets dans les lignes ajoutées (valeurs masquées) ;
#    MAPTILER_KEY, si elle est dans l'environnement, est cherchée telle quelle ;
# 3. copie propre à HEAD (git worktree, dossier temporaire), où l'on applique
#    exactement ce qui est en attente : git diff --cached --binary | git apply ;
# 4. dans cette copie : flutter analyze (« No issues found » exigé, aucun
#    filtre) et flutter test, pour chaque app ;
# 5. la copie est supprimée. Dernière ligne : VERT ou ROUGE.
set -u

racine=$(git rev-parse --show-toplevel) || exit 1
cd "$racine" || exit 1

if git diff --cached --quiet; then
  echo "Rien en attente : mettre d'abord les fichiers en attente (git add)."
  exit 1
fi

echo "== en attente"
git diff --cached --name-status
echo "== stat"
git diff --cached --stat | tail -1

ajouts=$(git diff --cached --text | grep '^+' | grep -v '^+++')
echo "== key= dans les ajouts (valeurs masquées)"
printf '%s\n' "$ajouts" | grep -n 'key=' | sed -E 's/key=[^&" )]+/key=***/g' | cut -c1-120
echo "== clés AIza : $(printf '%s\n' "$ajouts" | grep -c 'AIza')  | clés privées : $(printf '%s\n' "$ajouts" | grep -c 'PRIVATE KEY')"
if [ -n "${MAPTILER_KEY:-}" ]; then
  echo "== clé MapTiler réelle dans les ajouts : $(printf '%s\n' "$ajouts" | grep -cF "$MAPTILER_KEY")"
else
  echo "== MAPTILER_KEY absente de l'environnement : recherche de la clé réelle non faite"
fi

apps=("$@")
if [ ${#apps[@]} -eq 0 ]; then
  for a in taama_app taama_conducteur; do
    git diff --cached --quiet -- "$a" || apps+=("$a")
  done
fi

base=$(mktemp -d "${TMPDIR:-/tmp}/taama-verif-XXXXXX") || exit 1
copie="$base/copie"
nettoyer() {
  cd "$racine" || return
  git worktree remove --force "$copie" >/dev/null 2>&1
  rm -rf "${base:?}"
}
trap nettoyer EXIT

git worktree add -q --detach "$copie" HEAD || { echo ROUGE; exit 1; }
# Appliqué à l'index de la copie, puis reporté dans ses fichiers : les fins de
# ligne restent celles que git produit sur ce poste (core.autocrlf).
if ! git diff --cached --binary | git -C "$copie" apply --index; then
  echo "== ce qui est en attente ne s'applique pas sur HEAD"
  echo ROUGE
  exit 1
fi

resultat=VERT
if [ ${#apps[@]} -eq 0 ]; then
  echo "== aucune app touchée : ni analyse ni tests"
fi
for a in "${apps[@]}"; do
  echo "== $a"
  (
    cd "$copie/$a" || exit 1
    flutter pub get --offline >/dev/null 2>&1 || flutter pub get >/dev/null 2>&1
    analyse=$(flutter analyze 2>&1)
    printf '%s\n' "$analyse" | grep -E "issues? found|No issues"
    tests=$(flutter test 2>&1 | tail -1)
    echo "$tests"
    printf '%s\n' "$analyse" | grep -q "No issues found" && printf '%s\n' "$tests" | grep -q "All tests passed"
  ) || resultat=ROUGE
done

echo "$resultat"
[ "$resultat" = VERT ]
