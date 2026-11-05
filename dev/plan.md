# Plan: citezot — Zotero → Quarto bibliography R package

## Context
`zotero_package_handoff.md` describes extracting Zotero helpers from the `goflag_filmies` manuscript repo into a portable package. Core value (not found in other packages): scan qmd/CSV files for citekeys, match pinned keys (native `citation-key` first, `note` fallback), refuse to overwrite output when manuscript keys are missing, write only cited items, `dry_run = TRUE` write defaults.

## Decisions (confirmed with Joel)
- Name **citezot**; all exports prefixed **`cz_`** and kept short (`bibliography`→`bib`, etc.). Working dir `/Users/joelnitta/repos/citezot` (not a git repo; `git init`/commits only when asked).
- GitHub now, **CRAN-ready** (no network at load/check/test; fixtures only; MIT unless Joel prefers otherwise).
- v1 write scope: pin key, find, update fields, add from DOI. No deletes.
- Thin **httr2** layer, minimal Imports (`httr2`, `yaml`, `purrr`, `cli`/`rlang`; `jsonlite` only if needed).
- **Better BibTeX is not required.** Package only reads keys stored on items (native `citationKey`, then `Citation Key:` in Extra).

## Comparison with existing R packages
Based on CRAN/GitHub README and manual pages only (code not read; "not documented" ≠ "absent"). Re-verify `rbbt` and `zot` against source/a test library early in the build.

| | **citezot (planned)** | **rbbt** (GitHub, paleolimbot) | **zot** 0.5.0 (CRAN, 2026-10) | **c2z** 0.2.0 (CRAN, 2023) |
|---|---|---|---|---|
| Purpose | Qmd → bibliography file, plus safe library edits | Pull BibLaTeX for Rmd/qmd citations via Better BibTeX | General Zotero API client + local DB reads | General Zotero API client, imports, exports |
| Needs Zotero desktop running | No (Web API only) | **Yes**, plus Better BibTeX | No for API; local DB mode reads files | No |
| Needs Better BibTeX | No (reads pinned keys; BBT optional for key formula) | **Yes** | No | No |
| Works headless / CI / `targets` | Yes | No | Yes | Yes |
| Scan document for `@keys` | Yes (qmd, strips code, ignores cross-refs; plus CSV bare keys) | Yes (`bbt_update_bib()`; .qmd support unclear) | Not documented | Not documented |
| Writes bib file from cited keys only | Yes (`.bib` default, YAML option) | Yes (`.bib`) | Not documented | Export (BibLaTeX etc.), not cited-only |
| Refuses to overwrite on missing keys | Yes | Not documented | n/a | n/a |
| Add items (DOI) | Yes, dry-run default, duplicate check | No | `ztCrossref()` maps DOI→payload; `zotPost()` creates | Yes (DOI, ISBN, more) |
| Update items | Yes: diff, `If-Unmodified-Since-Version`, dry-run | No | `zotPatch()`, plan/preview/approve/execute | Edit/copy |
| Version-conflict (412) handling | Yes | n/a | "versioned writes" (details not documented) | Not documented |
| Dry-run | Default on every write | n/a | Plan-based preview, not a flag | Not documented |
| Deletes | None in v1 | No | `zotTrash()` | Yes, incl. destructive `ragnarok` |
| Dependencies | httr2, yaml, purrr, cli | httr/jsonlite-type, RStudio addins | httr2, jsonlite, data.table, DBI, RSQLite, digest | dplyr, httr, tibble, tidyr, rvest, … |
| Maintenance | new | 64 commits, no releases listed | active (published 2026-10-25) | last update 2023 |

**Conclusion.** `rbbt` is the closest to the Quarto use case but needs Zotero + BBT open and can't write; `zot` and `c2z` cover generic API access but not the "cited keys → bib file" workflow, the safety rules, or lightweight deps. Hence a new package with its own thin httr2 layer.
**Reuse:** no package dependency. Read `zot::ztCrossref()` (DOI→Zotero fields mapping) and `rbbt` (document key scanning, addin design) as references, checking licenses before borrowing any code. If `rbbt` already scans qmds well, compare its regex against the handoff's `extract_qmd_citekeys` tests.
**Differentiators to state in README:** works without desktop Zotero/BBT, never overwrites with an incomplete bibliography, dry-run-by-default writes, minimal dependencies.

## Primary use case: writing Quarto docs
One call produces the `references.yaml` / `references.bib` that the qmd's `bibliography:` points to. `targets` is optional.
- `format = c("bib", "yaml")` in `cz_update_bib()`; **default is `.bib`** (works with Typst, which doesn't read CSL-YAML; also LaTeX/HTML). Bib route (as built): Zotero's own `format=biblatex` export of just the cited items (`itemKey=`, 50 per request), which already uses the pinned citekeys as entry keys. Entries come back in arbitrary order, so they are matched to items by key, never by position; an entry exported under a different key (e.g. pinned only via Extra) is re-fetched alone and its key rewritten. YAML (CSL-YAML from `csljson`) stays as an option. Default `out` = front-matter `bibliography:` (then `_quarto.yml`), else `references.bib`; format inferred from the extension. Verified live: renders in Quarto html and typst.
- Argument names: `cz_update_bib(qmd, out, format, bare, allow_incomplete, auth, cache, quiet)`. `qmd` default = all `.qmd`/`.Rmd` under the working directory (skipping hidden/underscore dirs, renv, packrat, node_modules). Honouring the `_quarto.yml` render list is not done yet.
- Missing-key error points to `cz_find()`, `cz_add()`, `cz_pin_key()`.

## Use scenario (sketch)
Setup: API keys at zotero.org/settings/keys (one key; read-only is enough for pulling and technically safer, write access only if you add or edit items) in a gitignored `.Renviron`/`.env.local`:
```
ZOTERO_LIBRARY_ID=1234567
ZOTERO_API_KEY=xxxx
```
Day-to-day, writing `manuscript.qmd` (front matter `bibliography: references.bib`):
```r
library(citezot)

# 1. Write with @Ebihara2006, @Kent2002 ... then pull refs
cz_update_bib("manuscript.qmd")                 # writes references.bib (path from front matter)
cz_update_bib("manuscript.qmd", out = "references.yaml")   # yaml inferred from extension
cz_update_bib()                                 # all qmds in the project

# 2. A key is missing -> error; existing references.yaml untouched
cz_find(doi = "10.1101/gr.229202")              # already in library?
cz_find("Kent BLAT")                            # search title/creator
cz_add("10.1101/gr.229202", key = "auto")       # dry_run = TRUE: prints item + generated key
cz_add("10.1101/gr.229202", key = "auto", dry_run = FALSE)   # deliberate live write
cz_add("978-0-262-03384-8")                     # ISBN (later release)

# 3. Fix an existing entry
cz_get_item("Regnier2024")                      # native fields + version
cz_update_item("Regnier2024", list(date = "in press"))                   # dry run: before/after diff
cz_update_item("Regnier2024", list(date = "in press"), dry_run = FALSE)  # 412 if changed elsewhere

# 4. Pin a key on an item that has none
cz_pin_key("10.1101/gr.229202", "Kent2002")                 # item = DOI (dry run)
cz_find("Kent BLAT") |> cz_pin_key("Kent2002", dry_run = FALSE)   # item = result of cz_find()
cz_pin_key("Q62TD7I9", "Kent2002", dry_run = FALSE)          # or Zotero's 8-char item ID
# `item` in cz_pin_key/cz_get_item/cz_update_item accepts: DOI, Zotero item ID (also "libraryID/ID"),
# existing citekey, or a cz_find() result. Zero or multiple matches -> error asking to be more specific.

# 5. Re-run step 1, then quarto render (html, pdf, or typst)
```
Optional automation: Quarto `pre-render` script calling `cz_update_bib()`, or a `targets` target (`tar_file()` + `tar_cue(mode = "always")`).

## Citekey generation (as built)
`cz_suggest_key(item, formula, existing)` evaluates a documented subset of the Better BibTeX pattern language (auth, year, shorttitle(n, m), title; filters lower, upper, fold, transliterate, clean, condense, nopunct; `+`; quoted literals). Unsupported syntax is an error, never a different key. A taken key gets a letter (a, b, ... aa). `cz_add(key = "auto")` uses it.

`cz_key_format()` picks the formula: `options(citezot.key_format)`, then the `better-bibtex.citekeyFormat` line of the Zotero profile's `prefs.js` (read only on key generation, announced once per session; override location with `citezot.zotero_profile`), then BBT's default `auth.lower + shorttitle(3,3) + year`.

**Validated** on Joel's library: `auth.lower + year + shorttitle(1).lower` reproduces 353/359 (98.3%) of his lower-case keys. The other 6 come from data the items no longer have (BBT does not regenerate pinned keys), so 100% is not attainable. Rules learned: title HTML stripped; title words split on whitespace, "/" and en/em dashes; hyphens and punctuation dropped inside title words; Unicode hyphens in author names kept as "-"; collision letters start at "a".

**BBT JSON-RPC route: NOT built, deliberately.** Probed (read-only): its methods only work on items already in Zotero; none generates a key for item JSON, none exposes the pattern, and `item.regenerate_key` would rewrite pinned keys. Not useful for `cz_add()`.

## What `cz_add(id, key = NULL, collection = NULL, dry_run = TRUE)` does
`id` is an identifier; type auto-detected by pattern (override with `type =`). Renamed from `cz_add_doi()`.
- **v1: DOI** (Crossref). **Later, via the same internal dispatch (`R/lookup_*.R`, one resolver per type): ISBN (Open Library / Google Books), arXiv (arXiv API), PMID (NCBI E-utilities).** Zotero's own translators are not exposed by the Web API, so each source is a small resolver mapping to native item JSON. Unsupported type → clear error.
1. Searches library for the identifier (DOI/ISBN field, etc.); if found, stops and returns the existing item (no duplicates).
2. Fetches metadata from the resolver and maps it to Zotero native item JSON.
3. Key: `"auto"` → `cz_suggest_key()`; literal string → used as is; `NULL` → none set.
4. `dry_run = TRUE` prints the item + key, sends nothing. `FALSE` POSTs with a `Zotero-Write-Token` (retry-safe), optionally into a collection, then pins the key. Creates only; never edits/deletes existing items.

## Package layout (all exports `cz_*`)
- `R/api.R` — one internal request builder (base URL, `Zotero-API-Version: 3`, bearer auth, user/group path, retry honoring `Backoff`/`Retry-After`, 412 → clear error).
- `R/auth.R` — `cz_auth()` from `ZOTERO_API_KEY`/`ZOTERO_LIBRARY_ID`; never prints key.
- `R/keys.R` — `cz_qmd_keys()`, `cz_bare_keys()` (bare-file list and cross-ref prefixes are arguments), `cz_item_key()`, `cz_strip_key_line()`, `cz_suggest_key()`.
- `R/read.R` — `cz_fetch_items()` (paged `/items/top?format=csljson`; optional `since=` later).
- `R/bib.R` — `cz_update_bib()` (from `update_references_from_zotero`): refuse overwrite on missing qmd keys, bare keys warn, dup keys warn, sorted output (yaml: `id` = `citation-key`; bib: entry key = pinned key), returns path invisibly. Old "references.yaml" messages become format-neutral.
- `R/write.R` — `cz_pin_key()`, `cz_get_item()`, `cz_find()`, `cz_update_item()`, `cz_add()`; `dry_run = TRUE` default, print exact payload/diff, `If-Unmodified-Since-Version`, `Zotero-Write-Token` on POST.
- `R/lookup_doi.R` (Crossref; v1), later `lookup_isbn.R`, `lookup_arxiv.R`, `lookup_pmid.R` — each maps to Zotero native item JSON; `cz_add()` dispatches by identifier type.
- Docs: README (setup, two-key advice, BBT optional), vignette (Quarto workflow + targets).

## Order of work
1. (done) `usethis::create_package()`, `use_testthat(3)`, license, `.Rbuildignore` (ignore `.env.local`, handoff md).
2. Port pure key functions + tests (cases in handoff §4).
3. Central request helper, then fetch + pin on top.
4. Port `cz_update_bib()` with mocked-API tests (missing key leaves file byte-identical, `allow_incomplete`, dup warn, paging `Total-Results` 250 → 3 requests); add bib format.
5. Verify Zotero write API v3 docs before designing writes.
6. Write side: get → find → update → add-from-DOI; tests: dry_run sends nothing, 412 clear error.
7. Key generation (routes 3 → 2 → 1).
8. README + vignette; `devtools::check()`.

## Verification
- `devtools::test()` green offline (httptest2/webmockr fixtures, keys scrubbed).
- `devtools::check()` with no network: 0 errors/warnings.
- Smoke test with read-only key: run `cz_update_bib()` on goflag_filmies, diff against current `references.yaml`.
- Write smoke tests only on a scratch item with `dry_run = TRUE` first; Joel flips to live deliberately.

## Open items
- License (default MIT); `since=` conditional fetch in v1 or later; how much of the BBT formula language to support.

## Status (2026-11-04)
Steps 1-7 are implemented and committed, plus README, NEWS and vignette. Live-verified read paths and the write path (one throwaway item, since trashed). Not built / ideas: ISBN, arXiv and PMID lookups for `cz_add()`; honouring the `_quarto.yml` render list in `cz_update_bib()`; Greek/Cyrillic transliteration for keys; BBT JSON-RPC (see above). Before a release or an rOpenSci submission: re-run `devtools::check(cran = TRUE)`, consider `goodpractice::gp()`, and decide on CRAN versus GitHub-only.
