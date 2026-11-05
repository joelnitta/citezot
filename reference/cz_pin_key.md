# Pin a citekey onto a Zotero item

Sets the item's native `citationKey` field via the Web API (the same
field a desktop Better BibTeX install manages), so
[`cz_item_key()`](https://joelnitta.github.io/citezot/reference/cz_item_key.md)
and
[`cz_fetch_items()`](https://joelnitta.github.io/citezot/reference/cz_fetch_items.md)
see it. Requires a key with write access.

## Usage

``` r
cz_pin_key(
  item,
  key,
  dry_run = TRUE,
  overwrite = FALSE,
  auth = cz_auth(),
  cache = getOption("citezot.cache", FALSE)
)
```

## Arguments

- item:

  The item to pin: a DOI, a Zotero item ID (bare, `"Q62TD7I9"`, or with
  the library ID as in CSL-JSON, `"6265773/Q62TD7I9"`), an existing
  citekey, or a one-row result of
  [`cz_find()`](https://joelnitta.github.io/citezot/reference/cz_find.md).
  Zero or several matches is an error.

- key:

  The citekey to pin.

- dry_run:

  If `TRUE` (default), report what would change and write nothing.

- overwrite:

  Replace a *different* key that is already pinned. Defaults to `FALSE`,
  because changing a pinned key breaks documents citing it.

- auth:

  Credentials from
  [`cz_auth()`](https://joelnitta.github.io/citezot/reference/cz_auth.md).

- cache:

  Passed to
  [`cz_fetch_items()`](https://joelnitta.github.io/citezot/reference/cz_fetch_items.md)
  when `item` is a DOI or citekey that has to be looked up.

## Value

Invisibly, a list with `item`, `before`, `after` and `written`.

## Details

The default is a dry run: the item is *read* (to get its current version
and key) but nothing is written. Set `dry_run = FALSE` to write. The
write sends `If-Unmodified-Since-Version`, so if the item changed in the
meantime Zotero rejects it (HTTP 412) and nothing is overwritten.

## Examples

``` r
if (FALSE) { # \dontrun{
cz_pin_key("10.1016/0022-5193(64)90038-4", "Hamilton1964") # dry run
cz_pin_key("10.1016/0022-5193(64)90038-4", "Hamilton1964", dry_run = FALSE)
} # }
```
