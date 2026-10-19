# CLAUDE.md

Instrucciones para Claude Code en este repositorio.

## Resumen de cambios y nombre del build

Cada vez que termines una tarea y escribas el resumen de los cambios implementados, incluye el nombre del build que contiene esos cambios, con este formato:

```
build-<run_number>-<sha corto>
```

Ejemplo: `build-30-1bca82e`

- `<sha corto>`: los 7 primeros caracteres del commit que contiene los cambios (`git rev-parse --short=7 HEAD`).
- `<run_number>`: el número de ejecución del workflow `Build IPA` (`.github/workflows/build.yml`) para ese push. Se asigna en GitHub Actions al terminar de subir los cambios; consúltalo ahí. Si todavía no existe, indícalo en el resumen en lugar de inventar el número.
- En `main` el workflow publica una versión `0.x.0` en lugar de `build-…`; en ese caso incluye esa versión.
