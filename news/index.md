# Changelog

## citezot 0.0.0.9000

- [`cz_update_bib()`](https://joelnitta.github.io/citezot/reference/cz_update_bib.md)
  writes a BibLaTeX (default) or CSL-YAML bibliography containing only
  the items cited in `.qmd` / `.Rmd` files, reading the output path from
  `bibliography:`. It refuses to overwrite the file when a cited key is
  missing from Zotero.
- [`cz_fetch_items()`](https://joelnitta.github.io/citezot/reference/cz_fetch_items.md)
  downloads a library in parallel pages, with an opt-in local cache that
  refreshes incrementally.
- [`cz_find()`](https://joelnitta.github.io/citezot/reference/cz_find.md),
  [`cz_get_item()`](https://joelnitta.github.io/citezot/reference/cz_get_item.md),
  [`cz_add()`](https://joelnitta.github.io/citezot/reference/cz_add.md),
  [`cz_update_item()`](https://joelnitta.github.io/citezot/reference/cz_update_item.md)
  and
  [`cz_pin_key()`](https://joelnitta.github.io/citezot/reference/cz_pin_key.md)
  search and change the library. Every write is a dry run by default,
  uses version checks (or a write token when creating), and honours
  Zotero’s `Backoff` header. There is no delete.
- [`cz_suggest_key()`](https://joelnitta.github.io/citezot/reference/cz_suggest_key.md)
  and
  [`cz_key_format()`](https://joelnitta.github.io/citezot/reference/cz_key_format.md)
  generate citekeys from a Better BibTeX-style formula, which
  `cz_add(key = "auto")` uses.
- [`cz_auth()`](https://joelnitta.github.io/citezot/reference/cz_auth.md)
  reads `ZOTERO_API_KEY` and `ZOTERO_LIBRARY_ID` (or `ZOTERO_USER_ID`)
  and never prints the key.
