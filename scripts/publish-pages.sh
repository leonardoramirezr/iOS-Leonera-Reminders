#!/usr/bin/env bash
# Publica un build firmado en la rama gh-pages (una carpeta por etiqueta) y regenera la portada.
#
# La rama se reescribe cada vez como un único commit huérfano para que los .ipa no se acumulen
# en el historial. Si otro build publica a la vez, el push con --force-with-lease falla y se
# vuelve a intentar sobre el contenido nuevo.
#
# Entorno:
#   TAG, CHANNEL (stable|branch), IPA, ICON_57, ICON_512, BASE_URL,
#   TITLE, BUNDLE_ID, VERSION, BUILD_NUMBER, BRANCH, COMMIT, COMMIT_TITLE, DEVICES, RUN_URL
#   REMOTE (origin), PAGES_BRANCH (gh-pages), KEEP_BRANCH_BUILDS (50)
set -euo pipefail

: "${TAG:?}" "${CHANNEL:?}" "${IPA:?}" "${ICON_57:?}" "${ICON_512:?}" "${BASE_URL:?}"
REMOTE="${REMOTE:-origin}"
PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"
KEEP_BRANCH_BUILDS="${KEEP_BRANCH_BUILDS:-50}"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
export IPA_NAME="$(basename "$IPA")"

export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-github-actions[bot]}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

GIT_DIR_ABS="$(git rev-parse --absolute-git-dir)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for attempt in 1 2 3 4 5 6; do
  rm -rf "$WORK/old" "$WORK/site" "$WORK/index"
  mkdir -p "$WORK/old" "$WORK/site"

  # Contenido actual de la rama (si existe). Su SHA es la "lease" del push.
  set +e
  git ls-remote --exit-code --heads "$REMOTE" "$PAGES_BRANCH" >/dev/null
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    git fetch --quiet --no-tags "$REMOTE" "refs/heads/$PAGES_BRANCH"
    REMOTE_SHA="$(git rev-parse FETCH_HEAD)"
    git archive "$REMOTE_SHA" | tar -x -C "$WORK/old"
  elif [ "$status" -eq 2 ]; then
    REMOTE_SHA=""  # la rama todavía no existe
  else
    echo "No se pudo consultar $REMOTE/$PAGES_BRANCH" >&2
    exit 1
  fi

  # Sólo se conservan las carpetas de builds (con build.json): la rama pudo crearse desde el código.
  for dir in "$WORK"/old/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    if [ -f "$dir/build.json" ] && [ "$name" != "$TAG" ]; then
      cp -R "$dir" "$WORK/site/$name"
    fi
  done

  mkdir -p "$WORK/site/$TAG"
  cp "$IPA" "$WORK/site/$TAG/$IPA_NAME"
  cp "$ICON_57" "$WORK/site/$TAG/icon-57.png"
  cp "$ICON_512" "$WORK/site/$TAG/icon-512.png"
  python3 "$SCRIPTS/pages.py" build "$WORK/site/$TAG"
  python3 "$SCRIPTS/pages.py" site "$WORK/site" "$KEEP_BRANCH_BUILDS"

  # Commit huérfano con un índice aparte; --force para que un .gitignore (p. ej. *.ipa) no excluya nada.
  export GIT_INDEX_FILE="$WORK/index"
  git -C "$WORK/site" --git-dir="$GIT_DIR_ABS" --work-tree=. add -A --force .
  TREE="$(git write-tree)"
  unset GIT_INDEX_FILE
  COMMIT_SHA="$(git commit-tree "$TREE" -m "Publicar $TAG")"

  if git push --quiet --force-with-lease="refs/heads/$PAGES_BRANCH:$REMOTE_SHA" \
      "$REMOTE" "$COMMIT_SHA:refs/heads/$PAGES_BRANCH"; then
    echo "Publicado $TAG en $PAGES_BRANCH (intento $attempt)."
    exit 0
  fi
  delay=$((attempt * 5 + RANDOM % 5))
  echo "Otro build publicó a la vez; reintentando en ${delay}s…" >&2
  sleep "$delay"
done

echo "No se pudo publicar en $PAGES_BRANCH tras varios intentos." >&2
exit 1
