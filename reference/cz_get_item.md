# Get one item in Zotero's native JSON

Returns the item as Zotero stores it (not CSL-JSON): writable fields are
in `$data`, and `$version` is the item version used for safe updates.

## Usage

``` r
cz_get_item(item, auth = cz_auth(), cache = getOption("citezot.cache", FALSE))
```

## Arguments

- item:

  The item: a DOI, Zotero item ID, citekey, or one-row result of
  [`cz_find()`](https://joelnitta.github.io/citezot/reference/cz_find.md)
  (see
  [`cz_pin_key()`](https://joelnitta.github.io/citezot/reference/cz_pin_key.md)).

- auth:

  Credentials from
  [`cz_auth()`](https://joelnitta.github.io/citezot/reference/cz_auth.md).

- cache:

  Passed to
  [`cz_fetch_items()`](https://joelnitta.github.io/citezot/reference/cz_fetch_items.md)
  when `item` has to be looked up.

## Value

A list with `key`, `version`, `data` and other API fields.

## Examples

``` r
if (FALSE) { # \dontrun{
item <- cz_get_item("Darwin1859")
item$data$title
item$version
} # }
```
