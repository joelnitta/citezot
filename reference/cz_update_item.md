# Update fields of a Zotero item

Changes selected fields of one item and shows exactly what will change.
The default is a dry run: the item is read and a before/after diff is
shown, but nothing is written. Use `dry_run = FALSE` to write.

## Usage

``` r
cz_update_item(
  item,
  fields,
  dry_run = TRUE,
  auth = cz_auth(),
  cache = getOption("citezot.cache", FALSE)
)
```

## Arguments

- item:

  The item: a DOI, Zotero item ID, citekey, or one-row result of
  [`cz_find()`](https://joelnitta.github.io/citezot/reference/cz_find.md).

- fields:

  A named list of new values, e.g.
  `list(date = "in press", DOI = "10.1234/abc")`. Names must be fields
  that exist for the item's type; see `names(cz_get_item(item)$data)`.

- dry_run:

  If `TRUE` (default), show the diff and write nothing.

- auth:

  Credentials from
  [`cz_auth()`](https://joelnitta.github.io/citezot/reference/cz_auth.md)
  (a key with write access to write).

- cache:

  Passed to
  [`cz_fetch_items()`](https://joelnitta.github.io/citezot/reference/cz_fetch_items.md)
  when `item` has to be looked up.

## Value

Invisibly, a list with `item`, `changes` (for each changed field, its
`before` and `after`) and `written`.

## Details

Only fields whose value actually changes are sent (a PATCH), together
with `If-Unmodified-Since-Version`: if the item was edited elsewhere
since it was read, Zotero rejects the write (HTTP 412) and nothing is
overwritten.

Plain fields take a single string (use `""` to clear one). `creators`,
`tags`, `collections` and `relations` take lists and are **replaced as a
whole**, so to add one tag pass the full list of tags. Identity and
bookkeeping fields (`key`, `version`, `itemType`, dates, `parentItem`,
`deleted`) can't be changed, and the citekey is changed with
[`cz_pin_key()`](https://joelnitta.github.io/citezot/reference/cz_pin_key.md).

## Examples

``` r
if (FALSE) { # \dontrun{
cz_update_item("Regnier2024", list(date = "in press"))                  # preview
cz_update_item("Regnier2024", list(date = "in press"), dry_run = FALSE) # write
} # }
```
