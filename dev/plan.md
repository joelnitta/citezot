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
- `format = c("bib", "yaml")` in `cz_update_bib()`; **default is `.bib`** (works with Typst, which doesn't read CSL-YAML; also LaTeX/HTML). Bib route: Zotero `format=biblatex` export with entry keys rewritten to the pinned citekeys (same safety rules). YAML (CSL-YAML from `csljson`) stays as an option. Default `out_path` = front-matter `bibliography:`, else `references.bib`; format inferred from the file extension when given. Port tests must cover both formats; verify biblatex entries render in Typst via Quarto.
- `out_path` default read from the qmd's front-matter `bibliography:`; `qmd_paths` default = all `.qmd`/`.Rmd` in the Quarto project (respect `_quarto.yml` render list).
- Missing-key error points to `cz_find()`, `cz_add()`, `cz_pin_key()`.

## Use scenario (sketch)
Setup: API keys at zotero.org/settings/keys (read-only key for pulling, separate write key for edits) in a gitignored `.Renviron`/`.env.local`:
```
ZOTERO_LIBRARY_ID=1234567
ZOTERO_API_KEY=xxxx
```
Day-to-day, writing `manuscript.qmd` (front matter `bibliography: references.bib`):
```r
library(citezot)

# 1. Write with @Ebihara2006, @Kent2002 ... then pull refs
cz_update_bib("manuscript.qmd")                 # writes references.bib (path from front matter)
cz_update_bib("manuscript.qmd", out_path = "references.yaml")   # yaml inferred from extension
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

## Citekey generation for new items (supports BBT users' own formula)
`cz_suggest_key(item, formula = NULL)`, used by `cz_add(key = "auto")`. Resolution order (details to VERIFY against BBT docs/source during build):
1. **BBT JSON-RPC** (`http://localhost:23119/better-bibtex/json-rpc`) when Zotero desktop + BBT run: exact key from Joel's real formula. Local, opt-in, never at load/check time.
2. **Formula read from `prefs.js`** in the Zotero profile (`extensions.zotero.translators.better-bibtex.citekeyFormat`; profile dir via option/auto-detect on macOS/Win/Linux), evaluated by a small R interpreter for a subset of the BBT formula language. Unsupported tokens → clear error pointing to route 1 or 3. Tests start with `auth.lower + year + shorttitle(1).lower`.
3. **Manual**: `options(citezot.key_format = "auth.lower + year + shorttitle(1).lower")` or `formula=`.
4. No formula → default author+year(+letter). `dry_run` always shows the key before pinning; collisions checked against existing library keys.
Pinning goes through the Web API (`citationKey`), so BBT sees it as pinned after sync.

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
1. `usethis::create_package()`, `use_testthat(3)`, license, `.Rbuildignore` (ignore `.env.local`, handoff md).
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
