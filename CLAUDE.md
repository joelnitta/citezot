# citezot

R package: pull cited references from Zotero into Quarto bibliographies (`.bib` default), plus dry-run-by-default helpers to find/add/update Zotero items. Exports are prefixed `cz_`.

Read before working:
- `dev/zotero_package_handoff.md` — original handoff: source code to port, behaviors to preserve, safety rules.
- `dev/plan.md` — approved design and order of work.

Rules: writes default to `dry_run = TRUE`; no deletes in v1; never print or store API keys; no network at load/check/test time; do not commit unless asked.
