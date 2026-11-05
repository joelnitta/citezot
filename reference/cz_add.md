# Add an item to your Zotero library from a DOI

Looks up the metadata for a DOI (via the public Crossref API), checks
that the item is not already in your library, and creates it. The
default is a **dry run**: the library is *read* and Crossref is queried,
but nothing is written to Zotero. Use `dry_run = FALSE` to create the
item.

## Usage

``` r
cz_add(
  id,
  key = NULL,
  collection = NULL,
  dry_run = TRUE,
  auth = cz_auth(),
  cache = getOption("citezot.cache", FALSE)
)
```

## Arguments

- id:

  A DOI, with or without a `https://doi.org/` or `doi:` prefix.

- key:

  Optional citekey to pin on the new item, e.g. `"Kent2002"`. It must be
  usable as a pandoc citation key and not already used in your library.
  Use `"auto"` to generate one from your Better BibTeX formula (see
  [`cz_suggest_key()`](https://joelnitta.github.io/citezot/reference/cz_suggest_key.md)
  and
  [`cz_key_format()`](https://joelnitta.github.io/citezot/reference/cz_key_format.md));
  a letter is appended if the key is taken. The key is shown in the dry
  run.

- collection:

  Optional collection to add the item to: its 8-character key, or its
  exact name.

- dry_run:

  If `TRUE` (default), show what would be created and write nothing.

- auth:

  Credentials from
  [`cz_auth()`](https://joelnitta.github.io/citezot/reference/cz_auth.md)
  (a key with write access to write).

- cache:

  Passed to
  [`cz_fetch_items()`](https://joelnitta.github.io/citezot/reference/cz_fetch_items.md),
  which is used for the duplicate check.

## Value

Invisibly, a list with `item` (the payload), `key` (the new Zotero item
ID, or `NULL`), `existing` (matching rows of
[`cz_find()`](https://joelnitta.github.io/citezot/reference/cz_find.md)
if the item was already in the library) and `written`.

## Details

The new item is built from Zotero's own template for its type, so it
only contains fields valid for that type. The citekey, if you give one,
is pinned in the same request (the native `citationKey` field), so there
is no moment where the item exists without it. Only DOIs registered with
Crossref are supported for now; ISBN, arXiv and PMID lookups are
planned.

Creating is retry-safe: each request carries a random
`Zotero-Write-Token`, so a retried request after a network hiccup cannot
create the item twice. Existing items are never changed or deleted.

Crossref asks clients to identify themselves with a contact address to
use its faster pool. citezot never sends an address by itself; to opt
in, set `options(citezot.mailto = "you@example.org")`.

## Examples

``` r
if (FALSE) { # \dontrun{
cz_add("10.3767/000651906X622210", key = "Ebihara2006")        # preview
cz_add("10.3767/000651906X622210", key = "Ebihara2006", dry_run = FALSE)
} # }
```
