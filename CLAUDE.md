# CLAUDE.md

## Resumen al terminar una tarea

Cada vez que termines una tarea y escribas el resumen de los cambios implementados, incluye el nombre del
build que contiene esos cambios, por ejemplo `build-30-1bca82e`.

- El workflow `.github/workflows/build.yml` nombra los builds de ramas distintas de `main` como
  `build-<N>-<commit>`: `N` es el número de ejecución del workflow (`GITHUB_RUN_NUMBER`) y `commit` son los
  7 primeros caracteres del hash del commit (`git rev-parse --short=7 HEAD`).
- En `main` el build es la versión `0.x.0` que calcula el mismo workflow.
- Obtén `N` después de hacer push, consultando la ejecución de *Build IPA* para ese commit en GitHub Actions.
  Si todavía no aparece, indícalo en el resumen junto con el commit corto (`build-<N>-1bca82e`).
