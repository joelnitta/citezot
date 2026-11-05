# Write a bibliography file from the references cited in your documents

Scans Quarto / R Markdown documents for `@key` citations, looks the keys
up among the pinned citekeys in your Zotero library, and writes a
bibliography file containing only the cited items. Zotero is the source
of truth for the content of each reference; the documents decide which
references are needed.

## Usage

``` r
cz_update_bib(
  qmd = NULL,
  out = NULL,
  format = NULL,
  bare = NULL,
  allow_incomplete = FALSE,
  auth = cz_auth(),
  cache = getOption("citezot.cache", FALSE),
  quiet = FALSE
)
```

## Arguments

- qmd:

  Documents to scan for `@key` citations. Defaults to every `.qmd` and
  `.Rmd` file under the working directory, skipping hidden and
  underscore-prefixed directories, `renv`, `packrat` and `node_modules`.

- out:

  Bibliography file to write. Defaults to the file named by
  `bibliography:` in the documents' YAML front matter (or the project's
  `_quarto.yml`), else `references.bib`. If the documents name different
  files, `out` must be given.

- format:

  `"bib"` or `"yaml"`; inferred from `out` if `NULL`.

- bare:

  Optional files (e.g. CSVs) scanned for bare citekey-shaped tokens such
  as `Ebihara2006`. Missing ones only warn.

- allow_incomplete:

  Write the file even if keys cited in `qmd` are not found in Zotero.

- auth:

  Credentials from
  [`cz_auth()`](https://joelnitta.github.io/citezot/reference/cz_auth.md).

- cache:

  Passed to
  [`cz_fetch_items()`](https://joelnitta.github.io/citezot/reference/cz_fetch_items.md):
  keep a local copy of the library so repeat runs are fast. Defaults to
  `getOption("citezot.cache", FALSE)`.

- quiet:

  Suppress the summary message.

## Value

`out`, invisibly (handy for `targets::tar_target(format = "file")`).

## Details

Safety: if a key cited in a document is not found in Zotero, the
function stops and leaves the existing output file untouched (a
bibliography that silently loses entries breaks the render). Set
`allow_incomplete = TRUE` to write what was found anyway. Keys found
only in `bare` files, and duplicate citekeys in Zotero (the first match
is used), give warnings. The file is only rewritten when its content
would change, so unchanged bibliographies keep their modification time.

## Output formats

`"bib"` (default) writes BibLaTeX using Zotero's own exporter, with each
entry keyed by its pinned citekey; it works with every Quarto output
format, including Typst. `"yaml"` writes CSL-YAML (a `references:` list
with `id` and `citation-key` set to the citekey). The format is inferred
from the extension of `out` (`.bib` or `.yaml`/`.yml`).

## Examples

``` r
if (FALSE) { # \dontrun{
# reads ZOTERO_LIBRARY_ID / ZOTERO_API_KEY from the environment
cz_update_bib("manuscript.qmd")
cz_update_bib("manuscript.qmd", out = "references.yaml")
} # }
```
