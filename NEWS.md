# citezot 0.0.0.9000

* `cz_update_bib()` writes a BibLaTeX (default) or CSL-YAML bibliography containing only the items cited in `.qmd` / `.Rmd` files, reading the output path from `bibliography:`. It refuses to overwrite the file when a cited key is missing from Zotero.
* `cz_update_bib()` no longer leaves HTML tags in titles and other fields of the BibLaTeX output. Zotero's exporter leaves tags such as `<span class="nocase">`, `<em>`, `<strong>` and small-caps spans as literal text; they are now converted to LaTeX commands (a `shorttitle` that Zotero cut in the middle of a tag is dropped) (#1).
* `cz_fetch_items()` downloads a library in parallel pages, with an opt-in local cache that refreshes incrementally.
* `cz_find()`, `cz_get_item()`, `cz_add()`, `cz_update_item()` and `cz_pin_key()` search and change the library. Every write is a dry run by default, uses version checks (or a write token when creating), and honors Zotero's `Backoff` header. There is no delete.
* `cz_suggest_key()` and `cz_key_format()` generate citekeys from a Better BibTeX-style formula, which `cz_add(key = "auto")` uses.
* `cz_set_auth()` prompts for your Zotero ID and API key and saves them to `.Renviron` (user-level by default), so you do not have to edit the file by hand.
* `cz_auth()` reads `ZOTERO_API_KEY` and `ZOTERO_LIBRARY_ID` and never prints the key.
