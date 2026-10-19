# CLAUDE.md

## Language

Everything written in the repository must be in English: Markdown files, code comments, docstrings and
documentation comments, and the names of functions, methods, classes, structs, enums, protocols, variables,
constants, objects, files and tests.

## Summary at the end of a task

Whenever you finish a task and write the summary of the implemented changes, include the name of the build
that contains those changes, for example `build-30-1bca82e`.

- The `.github/workflows/build.yml` workflow names builds of branches other than `main` as
  `build-<N>-<commit>`: `N` is the workflow run number (`GITHUB_RUN_NUMBER`) and `commit` is the first
  7 characters of the commit hash (`git rev-parse --short=7 HEAD`).
- On `main` the build is the `0.x.0` version computed by the same workflow.
- Get `N` after pushing, by looking up the *Build IPA* run for that commit in GitHub Actions.
  If it does not show up yet, say so in the summary and give the short commit (`build-<N>-1bca82e`).
