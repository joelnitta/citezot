# Suggest a citekey for an item

Builds a key from a Better BibTeX-style formula, e.g.
`"auth.lower + year + shorttitle(1).lower"`. If the key is already
taken, a letter (`a`, `b`, ...) is appended, as Better BibTeX does.

## Usage

``` r
cz_suggest_key(item, formula = NULL, existing = character())
```

## Arguments

- item:

  A Zotero native item (as from
  [`cz_get_item()`](https://joelnitta.github.io/citezot/reference/cz_get_item.md),
  or the payload
  [`cz_add()`](https://joelnitta.github.io/citezot/reference/cz_add.md)
  builds) or a CSL-JSON item.

- formula:

  The key formula. See Details.

- existing:

  Keys already in use, so the result can be made unique.

## Value

A single string.

## Details

The formula is, in order of preference, the `formula` argument, then the
one found by
[`cz_key_format()`](https://joelnitta.github.io/citezot/reference/cz_key_format.md)
(the `citezot.key_format` option, your Zotero profile's Better BibTeX
pattern, or Better BibTeX's default
`auth.lower + shorttitle(3,3) + year`). Supported functions are `auth`
(first author's last name), `year`, `shorttitle(n, m)` (first `n` words
of the title, skipping short function words, with the first `m`
capitalised), and `title`; filters are `lower`, `upper`, `fold`,
`transliterate`, `clean`, `condense` and `nopunct`; terms are joined
with `+` and quoted text is kept as is. Anything else is an error rather
than a silently different key. The result is ASCII and safe to cite in
pandoc.

## Examples

``` r
item <- list(
  itemType = "journalArticle",
  title = "A taxonomic revision of Hymenophyllaceae",
  date = "2006",
  creators = list(list(creatorType = "author", firstName = "A", lastName = "Ebihara"))
)
cz_suggest_key(item, "auth.lower + year + shorttitle(1).lower")
#> [1] "ebihara2006taxonomic"
cz_suggest_key(item, existing = "ebihara2006taxonomic",
               formula = "auth.lower + year + shorttitle(1).lower")
#> [1] "ebihara2006taxonomica"
```
