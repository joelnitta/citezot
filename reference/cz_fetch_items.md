# Fetch every top-level item in a Zotero library as CSL-JSON

Uses the `/items/top` endpoint (excludes notes, attachments and other
child items) and pages through the whole library using the
`Total-Results` header. After the first page, the remaining pages are
requested in parallel (at most `getOption("citezot.max_active", 4)` at a
time, and throttled) and the library version is checked so that a
library edited mid-download is re-fetched rather than returned
inconsistent.

## Usage

``` r
cz_fetch_items(
  auth = cz_auth(),
  page_size = 100,
  cache = getOption("citezot.cache", FALSE),
  refresh = FALSE
)
```

## Arguments

- auth:

  Credentials from
  [`cz_auth()`](https://joelnitta.github.io/citezot/reference/cz_auth.md).

- page_size:

  Items per request (Zotero's maximum is 100).

- cache:

  Use and update the local cache? Defaults to
  `getOption("citezot.cache", FALSE)`.

- refresh:

  If `TRUE`, ignore any existing cache and download the whole library
  (the cache, if enabled, is then rewritten).

## Value

A list of CSL-JSON items (plain lists, `simplifyVector = FALSE`). The
order is not guaranteed.

## Details

A full download of a large library takes a while. With `cache = TRUE`
the items are stored in a local file (in
`tools::R_user_dir("citezot", "cache")`, or
`getOption("citezot.cache_dir")`), and later calls download only what
changed since: one request if nothing changed, otherwise the changed
items plus the lists of deleted and trashed items. The cache holds the
library's bibliographic metadata, never your API key. It is opt-in:
nothing is written to disk unless you ask, either here or with
`options(citezot.cache = TRUE)`. Use `refresh = TRUE` to ignore the
cache and download everything again, and
[`cz_clear_cache()`](https://joelnitta.github.io/citezot/reference/cz_clear_cache.md)
to delete it.

## Examples

``` r
if (FALSE) { # \dontrun{
items <- cz_fetch_items()
length(items)

# Keep a local copy, so later calls download only what changed
items <- cz_fetch_items(cache = TRUE)
} # }
```
