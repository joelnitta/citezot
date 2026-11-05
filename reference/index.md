# Package index

## Build a bibliography

Write a bibliography file containing only the references cited in your
Quarto or R Markdown documents.

- [`cz_update_bib()`](https://joelnitta.github.io/citezot/reference/cz_update_bib.md)
  : Write a bibliography file from the references cited in your
  documents

- [`cz_qmd_keys()`](https://joelnitta.github.io/citezot/reference/cz_qmd_keys.md)
  : Extract pandoc citation keys used in a qmd/Rmd file

- [`cz_bare_keys()`](https://joelnitta.github.io/citezot/reference/cz_bare_keys.md)
  :

  Extract bare (no `@`) citekey-shaped tokens from a text/data file

## Connect to Zotero

Credentials, downloading your library, and the local cache.

- [`cz_auth()`](https://joelnitta.github.io/citezot/reference/cz_auth.md)
  : Zotero credentials
- [`cz_fetch_items()`](https://joelnitta.github.io/citezot/reference/cz_fetch_items.md)
  : Fetch every top-level item in a Zotero library as CSL-JSON
- [`cz_clear_cache()`](https://joelnitta.github.io/citezot/reference/cz_clear_cache.md)
  : Delete citezot's cached library data

## Find, add and edit items

Every function that changes your library is a dry run by default.

- [`cz_find()`](https://joelnitta.github.io/citezot/reference/cz_find.md)
  : Find items in your Zotero library
- [`cz_get_item()`](https://joelnitta.github.io/citezot/reference/cz_get_item.md)
  : Get one item in Zotero's native JSON
- [`cz_add()`](https://joelnitta.github.io/citezot/reference/cz_add.md)
  : Add an item to your Zotero library from a DOI
- [`cz_update_item()`](https://joelnitta.github.io/citezot/reference/cz_update_item.md)
  : Update fields of a Zotero item
- [`cz_pin_key()`](https://joelnitta.github.io/citezot/reference/cz_pin_key.md)
  : Pin a citekey onto a Zotero item

## Citekeys

Read pinned citekeys, and generate new ones from a formula.

- [`cz_item_key()`](https://joelnitta.github.io/citezot/reference/cz_item_key.md)
  : Get a CSL item's pinned citekey, however it is pinned
- [`cz_suggest_key()`](https://joelnitta.github.io/citezot/reference/cz_suggest_key.md)
  : Suggest a citekey for an item
- [`cz_key_format()`](https://joelnitta.github.io/citezot/reference/cz_key_format.md)
  : Which key formula citezot will use
