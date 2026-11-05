# citezot 0.0.0.9000

* `cz_update_bib()` writes a BibLaTeX (default) or CSL-YAML bibliography containing only the items cited in `.qmd` / `.Rmd` files, reading the output path from `bibliography:`. It refuses to overwrite the file when a cited key is missing from Zotero.
* `cz_fetch_items()` downloads a library in parallel pages, with an opt-in local cache that refreshes incrementally.
* `cz_find()`, `cz_get_item()`, `cz_add()`, `cz_update_item()` and `cz_pin_key()` search and change the library. Every write is a dry run by default, uses version checks (or a write token when creating), and honours Zotero's `Backoff` header. There is no delete.
* `cz_suggest_key()` and `cz_key_format()` generate citekeys from a Better BibTeX-style formula, which `cz_add(key = "auto")` uses.
* `cz_auth()` reads `ZOTERO_API_KEY` and `ZOTERO_LIBRARY_ID` (or `ZOTERO_USER_ID`) and never prints the key.
