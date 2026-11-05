# Handoff: turn the Zotero helpers into a portable R package

**For:** Claude Code, working in a fresh R package project with Joel Nitta.
**From:** Claude Code in the `goflag_filmies` manuscript repo (a targets/Quarto project).
**Goal:** Extract the Zotero code from that repo into a reusable, installable R package, so any manuscript project can pull a bibliography from Zotero, fix items, and add items without copying code.

Read this whole file first, then propose a plan to Joel before writing code. The package name is not decided; ask.

---

## 1. What exists today (source repo)

All paths are in the `goflag_filmies` repo (`/project` on Joel's machine). The full code is reproduced verbatim in the Appendix at the end of this file, so nothing needs to be fetched from that repo. The key locations:

| Where | What |
|---|---|
| `R/functions.R`, section `# Zotero -> references.yaml` (lines 7593-7959) | All the logic (functions below; code in Appendix A1) |
| `R/update_references.R` | 29-line Rscript wrapper: loads `.env.local`, sources `functions.R`, calls `update_references_from_zotero()` |
| `_targets.R` (about line 1107) | `zotero_refs` target: `tar_file()` with `cue = tar_cue(mode = "always")`, so it re-pulls on every `tar_make()` |
| `R/packages.R` | Loads `.env.local` via `dotenv`; attaches `httr2` |

### Functions to port

| Function | Role |
|---|---|
| `extract_qmd_citekeys(qmd_path)` | Finds pandoc `@key` citations in a qmd/Rmd. Strips fenced code blocks first, drops Quarto cross-refs (`@fig-`, `@tbl-`, `@eq-`, `@sec-`, etc.), allows embedded periods (e.g. `WatkinsJr.2012`), and ignores emails. |
| `extract_bare_citekeys(path)` | Finds bare citekey-shaped tokens (`Ebihara2006`, `Dubuisson2013a`) in CSV or text files. Regex is deliberately conservative. |
| `citekey_source_files` | Hard-coded vector of project CSVs to scan. **Must become an argument or option in the package, not a constant.** |
| `zotero_fetch_all_items(library_id, api_key, library_type = "user", page_size = 100)` | Pages through `GET /{users\|groups}/{id}/items/top?format=csljson` with `httr2` (bearer auth, `Zotero-API-Version: 3`, `req_retry(max_tries = 3)`). Reads the `Total-Results` header to page. Returns a list of CSL-JSON items (`simplifyVector = FALSE`). |
| `zotero_item_citekey(item)` | Returns the pinned Better BibTeX key. Checks native `citation-key` first, then falls back to a `Citation Key: <key>` line in `note` (the Extra field). |
| `zotero_extract_citekey(note)` | The `note`-parsing half of the above. |
| `zotero_strip_citekey_line(note)` | Removes the `Citation Key:` line from a note, so it doesn't leak into the bibliography. |
| `zotero_pin_citekey(item_id, citekey, ...)` | The only existing **write** function. GETs the item for its `version`, then `PATCH`es `{citationKey = ...}` with `If-Unmodified-Since-Version`. Accepts `"KEY"` or `"libraryID/KEY"` (the CSL-JSON form). |
| `update_references_from_zotero(qmd_paths, bare_paths, out_path, library_id, api_key, library_type, allow_incomplete = FALSE, quiet = FALSE)` | The orchestrator. Collects cited keys, fetches the library, matches keys, writes a CSL-YAML file with only the used items. Returns `out_path` invisibly so it works with `tar_file()`. |

### Behaviors to preserve (these were hard-won)

1. **Only used items are written.** The manuscript's `@citations` decide *which* references are needed. Zotero decides their *content*. There is no separate Zotero collection to keep in sync.
2. **Refuse to overwrite on missing manuscript keys.** If a key cited with `@` in a qmd isn't found in Zotero, it errors and leaves the existing output file untouched (`allow_incomplete = FALSE`). A bibliography that silently loses entries breaks the render. Missing *bare* keys (from CSVs) only warn.
3. **Duplicate citekeys** in Zotero produce a warning and use the first match.
4. **Output is CSL-YAML** (`---` line, then `references:` list), with `id` and `citation-key` both set to the key, items sorted by key.
5. **Native field first, `note` fallback.** Early pins were written as `Citation Key:` lines in Extra. Later ones used the native `citationKey` field. Both exist in Joel's library. Commit `5e8da15` fixed a bug where only `note` was checked.
6. **Periods in keys.** Commit `a6bad4b` added support for keys like `WatkinsJr.2012`.
7. Better BibTeX **does not need to be running**. The package reads pinned keys from the API, so keys must be pinned in Zotero first (right-click, "Pin BibTeX Key").

---

## 2. What is NOT in the repo (important)

Joel said the workflow also includes "make corrections and add data via claude". That was done **ad hoc through the API in earlier sessions, and the code was not saved**. Only `zotero_pin_citekey()` survives. For example, `@Kent2002` (BLAT) "was added via the API from its DOI", and the Regnier et al. entry was corrected to date "in press". Nothing in git records how.

So the package's **write side must be designed fresh**. Ask Joel what he actually does, and whether he wants these (suggested scope):

- `zotero_get_item(key)`: fetch one item in Zotero's native JSON (not CSL), including its `version`.
- `zotero_update_item(key, fields, dry_run = TRUE)`: `PATCH` selected fields (title, date, DOI, `extra`, creators, etc.) using `If-Unmodified-Since-Version`. Should show a before/after diff.
- `zotero_add_item_from_doi(doi, collection = NULL, citekey = NULL, dry_run = TRUE)`: look up metadata (Crossref REST API is the obvious source) and create the item. Optionally pin a citekey in the same step. Should check for an existing item with the same DOI first.
- `zotero_find(query / doi / citekey)`: search before adding, to avoid duplicates.
- `zotero_pin_citekey()`: port as is.

Notes on the Zotero Web API v3 (from general knowledge, **verify against https://www.zotero.org/support/dev/web_api/v3/write_requests before relying on it**):
- Writes use Zotero's native item JSON (`itemType`, `title`, `creators`, `DOI`, `date`, ...), not CSL-JSON. Get valid field names per type from `/itemTypeFields?itemType=` and `/items/new?itemType=`.
- Creating items: `POST /users/{id}/items` with a JSON array (max 50 per request) and a `Zotero-Write-Token` header (random 32 chars) so retries don't duplicate.
- Updating: `PATCH` with an `If-Unmodified-Since-Version` header set to the item's current `version` (as `zotero_pin_citekey()` does). A `412` means someone else changed it; re-fetch and retry deliberately, never blindly.
- Respect `Backoff` and `Retry-After` headers. `httr2::req_retry()` can be told how to read them.
- A `204` is success for PATCH. `POST` returns a `successful` / `failed` map.

---

## 3. Safety rules (carry these over; they come from Joel's standing preferences)

- **Writes to a live library are outward-facing and hard to reverse.** Every write function should default to `dry_run = TRUE`, printing exactly what would be sent. Joel flips it deliberately.
- **No deletes** in v1. If Joel later wants them, require explicit confirmation and a Zotero trash (not permanent) route.
- **API keys:** read from `ZOTERO_API_KEY` and `ZOTERO_LIBRARY_ID` (env vars, optionally loaded from a gitignored `.env.local`). Never print, log, or store the key in test fixtures or snapshots. A read-only key is enough for the pull; writes need a key with write access. The docs describe a single key and note that read-only is technically safer (decided after the first draft, which recommended two keys).
- **Do not commit** unless Joel asks. He reviews changes first.
- The package must not run network calls at load or at check time. Tests use recorded fixtures only.

---

## 3b. Existing packages: check before building (searched 2026-11-04)

A web search found these. Only search-result summaries were read, **not their code or maintenance status**, so verify before depending on any of them (read the docs, check CRAN/GitHub activity, try against a test library).

**R packages wrapping the Zotero Web API, including writes**
- [`zot`](https://stat.ethz.ch/CRAN/web/packages/zot/readme/README.html) (CRAN): Web API wrapper plus read-only queries over a local Zotero database. Write functions include `zotPost()`, `zotPatch()`, `zotTrash()`, `ztAttach()`, and a batch-plan feature.
- [`c2z`](https://search.r-project.org/CRAN/refmans/c2z/html/Zotero.html) (CRAN): add, edit, copy and delete items and collections; its example adds items by ISBN.
- [`zoter`](https://github.com/kleinlennart/zoter) (GitHub only): Web API v3 client; appeared read-only.

**Claude editing a Zotero library:** no R package found. The tools for this are MCP servers in Python/TypeScript, e.g. [zotero-toolkit](https://github.com/adolinjonathan-bot/zotero-toolkit/releases/tag/v1.0.0) (create/update/trash, version-checked updates), [BirdInTheTree Zotero MCP](https://mcp.so/servers/zotero-mcp-birdinthetree?tab=tools) (create from DOI, BibTeX import, merge duplicates) and [xevos117/mcp-zotero](https://lobehub.com/en/mcp/xevos117-mcp-zotero). [local-zotero-mcp](https://pypi.org/project/local-zotero-mcp/0.1.5/) is read-only. Joel's current workflow needs no MCP server: Claude runs R code that calls the API.

**What this means for scope**
- The generic fetch/post/patch layer (sections 1 and 2, write side) may already be solved by `zot` or `c2z`. Evaluate them first. Options: depend on one, wrap one, or write a thin layer if neither fits (e.g. no `dry_run`, no version-conflict handling, no CSL-JSON paging by `/items/top`).
- Likely still unique, and the real reason for this package: scanning qmd files and CSVs for citekeys; matching pinned Better BibTeX keys (native `citation-key` first, `note` fallback); refusing to overwrite the output when manuscript keys are missing; writing only cited items as CSL-YAML; the `targets` pattern; and `dry_run = TRUE` defaults on writes. None of these appeared in the packages above.
- Tell Joel what you find before choosing, so the package does not duplicate existing work.

---

## 4. Suggested package design

- **Dependencies (Imports):** `httr2`, `yaml`, `purrr`, `cli` (or `rlang::abort`), optionally `jsonlite`. The old code used `assertthat`; replace with `rlang`/`cli` checks. `dotenv` is not needed in the package: read env vars with `Sys.getenv()` and let users load `.env.local` themselves (document it).
- **Suggests:** `testthat`, `httptest2` (or `webmockr`), `withr`, `targets` (for the example only).
- **Layout idea:**
  - `R/api.R`: one internal request builder (base URL, `Zotero-API-Version`, bearer auth, retry/backoff, user/group path). The old code duplicates this logic in the fetch and pin functions; centralize it.
  - `R/citekeys.R`: `extract_qmd_citekeys()`, `extract_bare_citekeys()`, `zotero_item_citekey()`, etc. These are pure functions, so they're the easiest to test.
  - `R/read.R`: fetch (paged), optionally `since = <library version>` to use conditional requests and cut API load, since the target currently re-pulls the whole library every run.
  - `R/write.R`: pin/update/add.
  - `R/bibliography.R`: `zotero_update_bibliography()` (renamed `update_references_from_zotero()`).
  - `R/auth.R`: `zotero_credentials()` that resolves env vars and errors with a helpful message.
- **Exports:** use a `zotero_` (or the package's) prefix consistently. The old `extract_*` names are too generic for a package namespace.
- **Make configurable what the old code hard-coded:** the list of bare-key files, the cross-reference prefixes, the output format (CSL-YAML now; CSL-JSON or BibTeX could be options), the `library_type`.
- **targets integration:** keep the pattern that works today, a `tar_file()` target with `cue = tar_cue(mode = "always")` that returns the output path. Put a short example in the README or a vignette. Note that the downstream `tar_quarto()` target lists `references.yaml` in `extra_files`, so its content hash triggers a re-render.
- **Docs:** README with the one-time setup (create API key at zotero.org/settings/keys; the numeric user ID is on that page; pin keys with Better BibTeX), plus a vignette on the manuscript workflow.

### Tests (port first, before refactoring)

The current repo has no Zotero tests, so write them as you port:
- `extract_qmd_citekeys()`: keys in code fences are ignored; `@fig-x` / `@tbl-x` dropped; `WatkinsJr.2012` kept; trailing period not captured (`@Foo2020.`); `joel@example.com` ignored.
- `extract_bare_citekeys()`: matches `Ebihara2006`, `Boucheron-Dubuisson2024`, `Dubuisson2013a`; does not match `Hsu7949` or `Ebihara 2006`.
- `zotero_item_citekey()`: native field wins; `note` fallback; neither gives `NA`.
- `zotero_strip_citekey_line()`: keeps other note content; returns `NULL` if nothing is left.
- `update_references_from_zotero()` with a mocked API: missing manuscript key errors and leaves the existing file byte-identical; `allow_incomplete = TRUE` writes anyway; missing bare key warns only; duplicate key warns; output is sorted and has `id` = `citation-key`.
- Paging: mock a `Total-Results` of 250 and check three requests are made.
- Write functions: `dry_run = TRUE` sends nothing; a `412` surfaces a clear error.

---

## 5. Suggested first steps for the new session

1. Evaluate `zot` and `c2z` (section 3b) and report back. Then ask Joel for: the package name, whether it's going on GitHub/CRAN or staying private, and the exact write operations he wants (section 2).
2. Scaffold with `usethis::create_package()` (MIT or whatever Joel prefers), `use_testthat(3)`. No `use_pipe()` is needed, since the code uses the native `|>` (R >= 4.1).
3. Port the pure functions and their tests first.
4. Build the central request helper, then port fetch and pin on top of it.
5. Port `update_references_from_zotero()` and its mocked tests.
6. Only then design and add the write side, with `dry_run` defaults.
7. Finish with the README, then a minimal `devtools::check()` pass.

## 6. Context about Joel's environment (may help)

- R project managed with `renv`; long R jobs launched with `RENV_WATCHDOG_ENABLED=FALSE` because the renv watchdog slows startup.
- Background jobs should use `tmux`, not `nohup`.
- Check `pgrep` for a running `tar_make` before starting one in the manuscript repo.
- Joel's Zotero library is a **user** library (not a group) and uses Better BibTeX keys like `Ebihara2006`, `li2013aligning`, `mendez-reneau2026what`. Key style is mixed, so don't assume a pattern.

---

# Appendix: source code (verbatim from the goflag_filmies repo)

This is the complete current code, copied unchanged so this document is self-contained. Line numbers refer to the original files at commit `4a2d6f1` (plus uncommitted edits elsewhere). It is the starting point to port and refactor, not the target design. Fences use four backticks because `extract_qmd_citekeys()` contains a literal triple-backtick string.

## A1. `R/functions.R`, section "Zotero -> references.yaml" (lines 7593-7959)

Depends on: `httr2`, `yaml`, `purrr`, `assertthat`. `citekey_source_files` is project-specific (CSVs in that repo); make it an argument in the package.

````r
# Zotero -> references.yaml -------------------------------------------------
#
# references.yaml is generated FROM Zotero, not hand-edited. Workflow:
# 1. Cite sources in the qmd as usual (@CitationKey).
# 2. In Zotero, pin the Better BibTeX citekey for that item (right-click ->
#    "Pin BibTeX Key"), which writes `Citation Key: <key>` into the item's
#    Extra field - this is what lets a plain Zotero Web API pull reproduce
#    BBT's citekeys without running the BBT plugin itself.
# 3. Run `Rscript R/update_references.R` (or let the `zotero_refs` target in
#    _targets.R do it - it re-runs on every tar_make() via an "always" cue).
#
# Only items whose pinned citekey is actually used in the qmd are written out,
# so there is no separate Zotero collection to keep in sync - the manuscript's
# own @citations are the source of truth for *which* references are needed;
# Zotero is the source of truth for their content.
#
# Requires the environment variables ZOTERO_LIBRARY_ID and ZOTERO_API_KEY
# (e.g. via a gitignored .env.local, loaded in R/packages.R if present).

#' Extract pandoc citation keys used in a qmd/Rmd file
#'
#' Strips fenced code blocks first (so `@` in R code, e.g. R6/S4 slot access,
#' is never mistaken for a citation), finds `@key` tokens, then drops Quarto
#' cross-references (`@fig-x`, `@tbl-x`, `@eq-x`, ...), which use the same `@`
#' syntax but are not bibliography citations.
#'
#' @param qmd_path Path to the .qmd file.
#'
#' @return Sorted character vector of unique citation keys (no leading `@`).
extract_qmd_citekeys <- function(qmd_path) {
  lines <- readLines(qmd_path, warn = FALSE)
  in_code <- FALSE
  kept <- character(0)
  for (ln in lines) {
    if (grepl("^\\s*```", ln)) {
      in_code <- !in_code
      next
    }
    if (!in_code) kept <- c(kept, ln)
  }
  txt <- paste(kept, collapse = "\n")
  # a citekey is @ + alphanumerics/hyphens, optionally with embedded periods
  # (e.g. Better BibTeX keys like WatkinsJr.2012), not preceded by a word
  # character (so emails like joel@example.com in code/text are not mistaken
  # for citations). A period is only consumed when immediately followed by
  # more alnum/hyphen text, so a sentence-ending "@Foo2020." doesn't pull in
  # the trailing period.
  m <- gregexpr(
    "(?<![[:alnum:]_])@[[:alnum:]-]+(?:\\.[[:alnum:]-]+)*",
    txt,
    perl = TRUE
  )
  hits <- regmatches(txt, m)[[1]]
  keys <- sub("^@", "", hits)
  crossref_prefix <- "^(fig|tbl|eq|sec|lst|thm|lem|cor|prp|cnj|def|exm|exr|rem|sol|nte)-"
  keys <- keys[!grepl(crossref_prefix, keys, ignore.case = TRUE)]
  sort(unique(keys))
}

#' Extract bare (no `@`) citekey-shaped tokens from a plain text/data file
#'
#' For files that reference sources informally, e.g. a "comments" column like
#' `data_tracked/subgenera.csv`'s ("Subgenus defined in Dubuisson2013a"), which
#' use Better BibTeX citekeys as plain shorthand rather than pandoc `@`
#' citations. Matches an author-name-shaped run of letters (hyphens allowed)
#' immediately followed by a 19xx/20xx year and an optional lowercase
#' disambiguator letter - e.g. `Ebihara2006`, `Boucheron-Dubuisson2024`,
#' `Dubuisson2013a`. Deliberately conservative: prose like "in Ebihara 2006"
#' (space-separated) or voucher numbers like "Hsu7949" won't match.
#'
#' @param path Path to the file to scan.
#'
#' @return Sorted character vector of unique citekey-shaped tokens.
extract_bare_citekeys <- function(path) {
  txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
  m <- gregexpr(
    "(?<![[:alnum:]])[A-Za-z][A-Za-z-]*(19|20)[0-9]{2}[a-z]*(?![[:alnum:]])",
    txt,
    perl = TRUE
  )
  sort(unique(regmatches(txt, m)[[1]]))
}

# Files (beyond the manuscript qmd itself) scanned for bare citekey-shaped
# tokens that should exist in the Zotero-backed bibliography. Add more paths
# here as other tracked files start referencing sources informally.
citekey_source_files <- c(
  "data_tracked/subgenera.csv",
  "data_tracked/lit_review_trichomanoid.csv",
  "data_tracked/lit_review_hymenophyllum.csv"
)

#' Fetch every top-level item in a Zotero library as CSL-JSON
#'
#' Uses the `/items/top` endpoint (excludes notes/attachments/child items) and
#' pages through the full library.
#'
#' @param library_id Zotero numeric user ID (or group ID).
#' @param api_key Zotero API key (read-only access is enough).
#' @param library_type "user" (personal library) or "group".
#' @param page_size Items per page (Zotero's max is 100).
#'
#' @return List of CSL-JSON item lists (as parsed by `httr2::resp_body_json()`
#'   with `simplifyVector = FALSE`).
zotero_fetch_all_items <- function(
  library_id,
  api_key,
  library_type = "user",
  page_size = 100
) {
  assertthat::assert_that(
    nzchar(library_id) && nzchar(api_key),
    msg = paste(
      "ZOTERO_LIBRARY_ID / ZOTERO_API_KEY not set.",
      "Set them in a gitignored .env.local (see zotero.org/settings/keys)."
    )
  )
  type_path <- switch(
    library_type,
    user = "users",
    group = "groups",
    stop("library_type must be 'user' or 'group'")
  )

  req_base <- httr2::request("https://api.zotero.org") |>
    httr2::req_url_path_append(type_path, library_id, "items", "top") |>
    httr2::req_headers(`Zotero-API-Version` = "3") |>
    httr2::req_auth_bearer_token(api_key) |>
    httr2::req_retry(max_tries = 3)

  first <- req_base |>
    httr2::req_url_query(format = "csljson", limit = page_size, start = 0) |>
    httr2::req_perform()
  total <- as.integer(httr2::resp_header(first, "Total-Results", "0"))
  items <- httr2::resp_body_json(first, simplifyVector = FALSE)$items

  starts <- seq(page_size, max(total - 1, 0), by = page_size)
  for (start in starts) {
    page <- req_base |>
      httr2::req_url_query(format = "csljson", limit = page_size, start = start) |>
      httr2::req_perform()
    items <- c(items, httr2::resp_body_json(page, simplifyVector = FALSE)$items)
  }

  items
}

#' Pull the Better BibTeX citekey out of a CSL item's `note` field
#'
#' Zotero's CSL-JSON export puts the Extra field verbatim into `note`; Better
#' BibTeX writes a pinned key there as a `Citation Key: <key>` line. This is
#' the older of two pinning mechanisms - see `zotero_item_citekey()`, which
#' should be used instead when working with a full CSL item, since some
#' items are pinned via Zotero's native `citationKey` field instead (surfaced
#' as CSL-JSON's own `citation-key` property, not folded into `note`).
#'
#' @param note A CSL item's `note` field (character or NULL).
#'
#' @return The citekey, or NA if the item has no pinned Better BibTeX key.
zotero_extract_citekey <- function(note) {
  if (is.null(note) || !nzchar(note)) {
    return(NA_character_)
  }
  m <- regmatches(
    note,
    regexpr("(?m)^Citation Key:[ \t]*(\\S+)", note, perl = TRUE)
  )
  if (length(m) == 0) {
    return(NA_character_)
  }
  sub("^Citation Key:[ \t]*", "", m)
}

#' Get a Zotero CSL item's pinned Better BibTeX citekey, however it's pinned
#'
#' Better BibTeX can pin a citekey two ways: natively, via Zotero's own
#' `citationKey` field (surfaced in CSL-JSON as the item's own `citation-key`
#' property - this is what a synced desktop BBT install uses, and what
#' `zotero_pin_citekey()` sets via the Web API), or via an older
#' `Citation Key: <key>` line in the Extra field (surfaced in CSL-JSON as
#' `note`) - some items in the library were pinned this way before
#' `zotero_pin_citekey()` switched to the native field. Checks the native
#' field first, falling back to `note`.
#'
#' @param item A single CSL-JSON item as returned by `zotero_fetch_all_items()`.
#'
#' @return The citekey, or NA if the item has no pinned Better BibTeX key.
zotero_item_citekey <- function(item) {
  native <- item[["citation-key"]]
  if (!is.null(native) && nzchar(native)) {
    return(native)
  }
  zotero_extract_citekey(item$note)
}

# Drop the "Citation Key: ..." line from a note, keeping any other content
zotero_strip_citekey_line <- function(note) {
  if (is.null(note)) {
    return(NULL)
  }
  lines <- strsplit(note, "\n")[[1]]
  lines <- lines[!grepl("^Citation Key:[ \t]*\\S+[ \t]*$", lines)]
  txt <- paste(trimws(lines), collapse = "\n") |> trimws()
  if (!nzchar(txt)) NULL else txt
}

#' Pin a Better BibTeX citekey onto a Zotero item via the Web API
#'
#' Sets the item's native `citationKey` field directly - the same field a
#' desktop Better BibTeX install manages, surfaced in CSL-JSON as the item's
#' own `citation-key` property (see `zotero_item_citekey()`). Requires an API
#' key with library write access.
#'
#' @param item_id A Zotero item id/key, either bare (`"Q62TD7I9"`) or prefixed
#'   with the library id as `format = "csljson"` returns it
#'   (`"6265773/Q62TD7I9"`) - the prefix is stripped automatically.
#' @param citekey The Better BibTeX key to pin.
#' @param library_id,api_key,library_type See `zotero_fetch_all_items()`.
#'
#' @return `invisible(TRUE)` on success; errors on a non-2xx response (e.g. a
#'   version conflict from a concurrent edit).
zotero_pin_citekey <- function(
  item_id,
  citekey,
  library_id = Sys.getenv("ZOTERO_LIBRARY_ID"),
  api_key = Sys.getenv("ZOTERO_API_KEY"),
  library_type = "user"
) {
  item_key <- sub("^.*/", "", item_id)
  type_path <- switch(
    library_type,
    user = "users",
    group = "groups",
    stop("library_type must be 'user' or 'group'")
  )
  req_base <- httr2::request("https://api.zotero.org") |>
    httr2::req_url_path_append(type_path, library_id, "items", item_key) |>
    httr2::req_headers(`Zotero-API-Version` = "3") |>
    httr2::req_auth_bearer_token(api_key)

  item <- (req_base |> httr2::req_perform()) |>
    httr2::resp_body_json(simplifyVector = FALSE)

  req_base |>
    httr2::req_headers(`If-Unmodified-Since-Version` = as.character(item$version)) |>
    httr2::req_method("PATCH") |>
    httr2::req_body_json(list(citationKey = citekey)) |>
    httr2::req_perform()

  invisible(TRUE)
}

#' Refresh references.yaml from Zotero, restricted to keys actually used
#'
#' Keys come from two kinds of source: `@key` pandoc citations in `qmd_paths`
#' (these are what the rendered manuscript needs - a missing one breaks the
#' render), and bare citekey-shaped tokens in `bare_paths` (informal
#' documentation references, e.g. `data_tracked/subgenera.csv`'s comments -
#' missing ones don't break anything but are worth knowing about).
#'
#' @param qmd_paths Path(s) scanned for `@citekey`s (`extract_qmd_citekeys()`).
#' @param bare_paths Path(s) scanned for bare citekey-shaped tokens
#'   (`extract_bare_citekeys()`); defaults to `citekey_source_files`.
#' @param out_path Path to write the CSL-YAML bibliography to.
#' @param library_id,api_key,library_type See `zotero_fetch_all_items()`.
#' @param allow_incomplete If `FALSE` (the default), refuse to write
#'   `out_path` at all when a key cited in the manuscript has no matching
#'   pinned Zotero item - leaving the last good `out_path` untouched is much
#'   safer than silently replacing a complete bibliography with a broken one.
#'   Set `TRUE` to write out whatever was found anyway (e.g. while you're
#'   still in the middle of pinning keys for the first time).
#' @param quiet Suppress the summary message.
#'
#' @return `out_path`, invisibly (for use with `tar_file()`).
update_references_from_zotero <- function(
  qmd_paths,
  bare_paths = citekey_source_files,
  out_path,
  library_id = Sys.getenv("ZOTERO_LIBRARY_ID"),
  api_key = Sys.getenv("ZOTERO_API_KEY"),
  library_type = "user",
  allow_incomplete = FALSE,
  quiet = FALSE
) {
  qmd_keys <- sort(unique(unlist(purrr::map(qmd_paths, extract_qmd_citekeys))))
  bare_keys <- sort(unique(unlist(purrr::map(bare_paths, extract_bare_citekeys))))
  # a key required by the manuscript still counts as "required" even if it
  # also happens to appear in a bare-scanned file
  bare_only_keys <- setdiff(bare_keys, qmd_keys)
  cited_keys <- sort(unique(c(qmd_keys, bare_only_keys)))

  items <- zotero_fetch_all_items(library_id, api_key, library_type)

  citekeys <- vapply(items, zotero_item_citekey, character(1))
  dupe_keys <- unique(citekeys[duplicated(citekeys) & !is.na(citekeys)])
  if (length(dupe_keys) > 0) {
    warning(
      "Multiple Zotero items pinned with the same citekey (using the first): ",
      paste(dupe_keys, collapse = ", ")
    )
  }

  matched <- match(cited_keys, citekeys)
  found <- cited_keys[!is.na(matched)]
  missing <- cited_keys[is.na(matched)]
  missing_qmd <- intersect(missing, qmd_keys)
  missing_bare <- setdiff(missing, qmd_keys)

  if (length(missing_qmd) > 0) {
    msg <- paste0(
      "references.yaml: cited in the manuscript but NOT FOUND in Zotero ",
      "(pin the Better BibTeX key, or check spelling): ",
      paste(sort(missing_qmd), collapse = ", ")
    )
    if (!isTRUE(allow_incomplete)) {
      stop(
        msg,
        ". Refusing to overwrite ", out_path, " with an incomplete ",
        "bibliography that would break the manuscript render - it has NOT ",
        "been touched. Pin the missing keys in Zotero and re-run, or pass ",
        "allow_incomplete = TRUE to write out what was found anyway.",
        call. = FALSE
      )
    }
    warning(msg, " - writing out an incomplete bibliography anyway ",
      "(allow_incomplete = TRUE).", call. = FALSE)
  }
  if (length(missing_bare) > 0) {
    warning(
      "references.yaml: referenced in ", paste(bare_paths, collapse = ", "),
      " but NOT FOUND in Zotero (pin the Better BibTeX key, or check ",
      "spelling): ",
      paste(sort(missing_bare), collapse = ", "),
      call. = FALSE
    )
  }

  out_items <- purrr::map2(matched[!is.na(matched)], found, function(i, key) {
    item <- items[[i]]
    item$note <- zotero_strip_citekey_line(item$note)
    item$id <- key
    item[["citation-key"]] <- key
    item
  })
  out_items <- out_items[order(found)]

  yaml_text <- yaml::as.yaml(
    list(references = out_items),
    indent.mapping.sequence = TRUE
  )
  writeLines(c("---", yaml_text), out_path)

  if (!quiet) {
    message(sprintf(
      "references.yaml: %d/%d referenced keys matched a pinned Zotero item ",
      length(found),
      length(cited_keys)
    ), sprintf(
      "(%d from the manuscript, %d from %s)",
      length(qmd_keys),
      length(bare_only_keys),
      paste(bare_paths, collapse = ", ")
    ))
  }

  invisible(out_path)
}
````

## A2. `R/update_references.R` (standalone Rscript wrapper)

````r
#!/usr/bin/env Rscript
# Refresh references.yaml from Zotero.
#
# Run this whenever you've added/changed a citation in the qmd or edited an
# item in Zotero. Requires the environment variables ZOTERO_LIBRARY_ID and
# ZOTERO_API_KEY (get an API key at zotero.org/settings/keys - your numeric
# user ID is on that same page) - set them in a gitignored .env.local file
# in the project root (never committed).
#
#   Rscript R/update_references.R
#
# See the "Zotero -> references.yaml" section of R/functions.R for how
# citekeys are matched (Better BibTeX keys must be pinned in Zotero).

suppressMessages({
  library(dotenv)
  if (file.exists(".env.local")) load_dot_env(".env.local")
  library(httr2)
  library(yaml)
  library(purrr)
  library(assertthat)
})

source("R/functions.R")

update_references_from_zotero(
  qmd_paths = "goflag_filmies.qmd",
  out_path = "references.yaml"
)
````

## A3. `_targets.R` (lines 1106-1118): the target that calls it

`tar_file()` plus an "always" cue so the bibliography re-pulls on every `tar_make()`. The `ms` target (`tar_quarto()`) lists `references.yaml` in `extra_files` so a changed bibliography re-renders the manuscript.

````r

  # Refresh references.yaml from Zotero (see "Zotero -> references.yaml" in
  # R/functions.R). Re-runs every tar_make() (cheap: one API pull) so the
  # bibliography is always current; requires ZOTERO_LIBRARY_ID/ZOTERO_API_KEY
  # (.env.local). Can also be run standalone: Rscript R/update_references.R
  tar_file(
    zotero_refs,
    update_references_from_zotero(
      qmd_paths = c("goflag_filmies.qmd", "si_hybrids.qmd", "si_siamense_table.qmd"),
      out_path = "references.yaml"
    ),
    cue = tar_cue(mode = "always")
  ),
````

## A4. `R/packages.R` (the relevant lines only)

````r
library(dotenv)
# Local secrets (ZOTERO_LIBRARY_ID, ZOTERO_API_KEY), gitignored; .env itself
# stays tracked for non-secret config.
if (file.exists(".env.local")) dotenv::load_dot_env(".env.local")
library(httr2) # Zotero -> references.yaml (R/update_references.R)
````

`.env.local` format (never commit; replace with real values):

````
ZOTERO_LIBRARY_ID=1234567
ZOTERO_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxx
````
