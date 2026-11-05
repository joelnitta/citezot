# citezot

R package: pull cited references from Zotero into Quarto bibliographies (`.bib` default), plus dry-run-by-default helpers to find/add/update Zotero items. Exports are prefixed `cz_`.

Read before working:
- `dev/zotero_package_handoff.md` — original handoff: source code to port, behaviors to preserve, safety rules.
- `dev/plan.md` — approved design and order of work.

Rules: writes default to `dry_run = TRUE`; no deletes in v1; never print or store API keys; no network at load/check/test time; do not commit unless asked.

Before committing: `devtools::check()` clean, and the pre-commit hooks pass (`pre-commit install` once; they run styler and lintr, and check that `README.md` was rendered from `README.Rmd`; run by hand with `pre-commit run --all-files`). The same install adds a pre-push hook that runs `devtools::check()` and refuses the push unless it has no errors, warnings or notes. Code follows the tidyverse style at 80 columns (prose in the README and vignettes is not wrapped). Edit `README.Rmd`, never `README.md`.
