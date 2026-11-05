# Find items in your Zotero library

Searches the library for items matching *all* the criteria given.
Matching is done locally on the library's CSL-JSON (see
[`cz_fetch_items()`](https://joelnitta.github.io/citezot/reference/cz_fetch_items.md)),
because Zotero's server-side search cannot look items up by DOI or
citekey. Use `cache = TRUE` (or `options(citezot.cache = TRUE)`) to make
this fast on repeat calls.

## Usage

``` r
cz_find(
  query = NULL,
  doi = NULL,
  isbn = NULL,
  citekey = NULL,
  auth = cz_auth(),
  cache = getOption("citezot.cache", FALSE),
  items = NULL
)
```

## Arguments

- query:

  Free text. Every word must appear (case-insensitively) in the title,
  authors, year, journal or citekey.

- doi:

  A DOI, with or without a `https://doi.org/` or `doi:` prefix.

- isbn:

  An ISBN (hyphens and spaces are ignored).

- citekey:

  An exact pinned citekey.

- auth:

  Credentials from
  [`cz_auth()`](https://joelnitta.github.io/citezot/reference/cz_auth.md).

- cache:

  Passed to
  [`cz_fetch_items()`](https://joelnitta.github.io/citezot/reference/cz_fetch_items.md).

- items:

  Items already fetched with
  [`cz_fetch_items()`](https://joelnitta.github.io/citezot/reference/cz_fetch_items.md),
  to avoid fetching again.

## Value

A data frame with one row per match and columns `item` (Zotero item ID),
`citekey`, `author`, `year`, `title`, `doi` and `type`. It can be passed
as the `item` argument of
[`cz_pin_key()`](https://joelnitta.github.io/citezot/reference/cz_pin_key.md)
when it has one row.

## Examples

``` r
if (FALSE) { # \dontrun{
cz_find(doi = "10.3767/000651906X622210")
cz_find("Ebihara Hymenophyllaceae revision")
cz_find(citekey = "Ebihara2006")
} # }
```
