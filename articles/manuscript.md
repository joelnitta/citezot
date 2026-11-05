# Writing a manuscript with citezot

This vignette follows one manuscript from the first citation to a
rendered document. The chunks that need your Zotero account are shown
but not run here; the parts that work offline are run.

``` r

library(citezot)
```

## Setup

Before starting you need a Zotero API key, your user ID in
`~/.Renviron`, and citekeys on your items.
[`vignette("setup")`](https://joelnitta.github.io/citezot/articles/setup.md)
walks through this. Check that citezot can see your credentials (the key
is never printed):

``` r

cz_auth()
#> <cz_auth> user library 1234567 (API key hidden)
```

## The loop: cite, update, render

In `manuscript.qmd`, cite as usual and point Quarto at the file citezot
will write:

``` markdown
---
title: "On the Origin of Species"
bibliography: references.bib
---

The origin of species is explained by @Darwin1859; see also @Weiß2015.
```

Citezot finds the citations in the text. Code chunks are ignored, as are
Quarto cross-references such as `@fig-map`:

``` r

qmd <- tempfile(fileext = ".qmd")
writeLines(c(
  "---",
  "bibliography: references.bib",
  "---",
  "The origin of species is explained by @Darwin1859; see also @Weiß2015 and @fig-map.",
  "",
  "```{r}",
  "x@slot  # not a citation",
  "```"
), qmd)

cz_qmd_keys(qmd)
```

    #> [1] "Darwin1859" "Weiß2015"

Now write the bibliography:

``` r

cz_update_bib("manuscript.qmd")
#> ✔ 2/2 cited keys found; 'references.bib' updated.
```

and render the document with Quarto as normal
(`quarto render manuscript.qmd`, to HTML, PDF or Typst). Only the cited
items are written, in key order, as BibLaTeX straight from Zotero’s
exporter. For CSL-YAML give a `.yaml` name:
`cz_update_bib("manuscript.qmd", out = "references.yaml")`.

### When a key is missing

Suppose the text cites `@Kent2002` but the item has no such citekey in
Zotero. The update **stops and does not touch your existing file**:

``` r

cz_update_bib("manuscript.qmd")
#> Error in `cz_update_bib()`:
#> ! Cited in the documents but not found in Zotero: "Kent2002".
#> ✖ 'references.bib' was NOT touched, because an incomplete bibliography would
#>   break the render.
#> ℹ Pin the citekey in Zotero (see `cz_pin_key()`), check the spelling, or use
#>   `allow_incomplete = TRUE` to write what was found.
```

Three things can be wrong, and citezot helps with each.

1.  **A typo, or the item is there under another key.** Search for it:

    ``` r

    cz_find("kent blat")
    cz_find(doi = "10.1101/gr.229202")
    ```

2.  **The item is in Zotero but has no key yet.** Pin one. Like every
    write, it is a dry run until you say so:

    ``` r

    cz_pin_key("10.1101/gr.229202", "Kent2002")                  # preview
    cz_pin_key("10.1101/gr.229202", "Kent2002", dry_run = FALSE) # write
    ```

3.  **The item is not in your library.** Add it from its DOI:

    ``` r

    cz_add("10.1101/gr.229202", key = "Kent2002")                  # preview
    cz_add("10.1101/gr.229202", key = "Kent2002", dry_run = FALSE) # create
    ```

    The preview shows the title, authors, date and key it would create,
    and
    [`cz_add()`](https://joelnitta.github.io/citezot/reference/cz_add.md)
    first checks that the DOI and the key are not already in your
    library. (Only DOIs registered with Crossref are supported so far.)

Run
[`cz_update_bib()`](https://joelnitta.github.io/citezot/reference/cz_update_bib.md)
again and the document is complete.

## Fixing an entry

A date is wrong. Preview the change, then apply it:

``` r

cz_update_item("Regnier2024", list(date = "in press"))
#> ℹ Dry run: nothing written. Use `dry_run = FALSE` to apply to item ABCD2345 (...).
#> • date: "2026" -> "in press"

cz_update_item("Regnier2024", list(date = "in press"), dry_run = FALSE)
```

Only fields that change are sent, together with the item’s version. If
someone (or Zotero desktop) edited the item after citezot read it,
Zotero answers HTTP 412 and nothing is overwritten; run the command
again after looking at the item with `cz_get_item("Regnier2024")`.
Creators, tags and collections are replaced as a whole, so to add one
tag pass the full list of tags. Identity fields (`key`, `version`,
`itemType`, dates added/modified) and the citekey cannot be changed
here; use
[`cz_pin_key()`](https://joelnitta.github.io/citezot/reference/cz_pin_key.md)
for the key.

## Citekeys

If you use Better BibTeX, your keys follow a pattern such as
`auth.lower + year + shorttitle(1).lower`. citezot can generate keys for
new items with the same pattern:

``` r

item <- list(
  itemType = "journalArticle",
  title = "On the origin of species by means of natural selection",
  date = "1859",
  creators = list(list(creatorType = "author", firstName = "Charles", lastName = "Darwin"))
)

cz_suggest_key(item, "auth.lower + year + shorttitle(1).lower")
#> [1] "darwin1859origin"

# a taken key gets a letter
cz_suggest_key(item, "auth.lower + year + shorttitle(1).lower",
               existing = "darwin1859origin")
#> [1] "darwin1859origina"

# Better BibTeX's own default pattern
cz_suggest_key(item, "auth.lower + shorttitle(3,3) + year")
#> [1] "darwinOriginSpeciesMeans1859"
```

`cz_add(..., key = "auto")` uses the pattern from
[`cz_key_format()`](https://joelnitta.github.io/citezot/reference/cz_key_format.md):
the `citezot.key_format` option if you set it, otherwise the one Better
BibTeX saved in your Zotero profile, otherwise Better BibTeX’s default.
Only a subset of the formula language is supported (`auth`, `year`,
`shorttitle`, `title`, a few filters, `+`); anything else is an error
rather than a different key. Better BibTeX itself is not needed: any key
you pin with
[`cz_pin_key()`](https://joelnitta.github.io/citezot/reference/cz_pin_key.md)
or give to
[`cz_add()`](https://joelnitta.github.io/citezot/reference/cz_add.md)
works.

Words in titles follow Better BibTeX’s rules: HTML tags are dropped,
titles are cut at the first colon or sentence end, short function words
such as “a” and “the” are skipped, and hyphens and other punctuation are
removed inside words (`early-diverging` becomes `earlydiverging`).

## Speed

A first download of a big library takes tens of seconds. Turn on the
cache and later runs only fetch what changed:

``` r

options(citezot.cache = TRUE)   # put this in your .Rprofile
system.time(cz_update_bib("manuscript.qmd"))
#>    user  system elapsed
#>   0.121   0.019   0.342
```

The cache lives in `tools::R_user_dir("citezot", "cache")` and holds
bibliographic metadata only. `cz_fetch_items(refresh = TRUE)` forces a
full download, and
[`cz_clear_cache()`](https://joelnitta.github.io/citezot/reference/cz_clear_cache.md)
deletes it.

## Automating it

Update the bibliography every time the project renders by adding a
`pre-render` step to `_quarto.yml`:

``` yaml
project:
  pre-render: Rscript -e 'citezot::cz_update_bib()'
```

In a [targets](https://docs.ropensci.org/targets/) pipeline, return the
path and let targets track the file:

``` r

tar_target(
  references,
  cz_update_bib("manuscript.qmd", quiet = TRUE),
  format = "file",
  cue = tar_cue(mode = "always")
)
```

Because
[`cz_update_bib()`](https://joelnitta.github.io/citezot/reference/cz_update_bib.md)
leaves the file alone when nothing changed, the render is only repeated
when your references really changed.

## Troubleshooting

- **“Zotero credentials not found.”** The environment variables are not
  set in this R session. Check `Sys.getenv("ZOTERO_API_KEY") != ""` and
  restart R after editing `~/.Renviron`.
- **HTTP 403.** The key is invalid or lacks the access needed. Writing
  needs a key with write access.
- **HTTP 412 on an update.** The item changed since it was read. Look at
  it again with
  [`cz_get_item()`](https://joelnitta.github.io/citezot/reference/cz_get_item.md)
  and retry on purpose.
- **A cited key “not found” although the item is in Zotero.** The item
  has no citekey saved on it (or a different one). Use
  [`cz_find()`](https://joelnitta.github.io/citezot/reference/cz_find.md)
  to see what the item’s key is, and
  [`cz_pin_key()`](https://joelnitta.github.io/citezot/reference/cz_pin_key.md)
  to set it.
- **A key containing odd characters** (such as `??`) cannot be cited
  from a document. Fix it in Zotero or with
  `cz_pin_key(..., overwrite = TRUE)`.
