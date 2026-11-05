# Extract bare (no `@`) citekey-shaped tokens from a text/data file

For files that reference sources informally (e.g. a CSV "comments"
column saying "defined in Dubuisson2013a"). Matches an author-shaped run
of letters (hyphens allowed) immediately followed by a 19xx/20xx year
and an optional lowercase disambiguator, e.g. `Ebihara2006`,
`Boucheron-Dubuisson2024`. Deliberately conservative: `Ebihara 2006` or
`Hsu7949` do not match.

## Usage

``` r
cz_bare_keys(path)
```

## Arguments

- path:

  Path to the file to scan.

## Value

Sorted character vector of unique citekey-shaped tokens.

## Examples

``` r
notes <- tempfile(fileext = ".csv")
writeLines(c("site,comment", "A,defined in Darwin1859", "B,see Ebihara 2006"), notes)
cz_bare_keys(notes) # "Ebihara 2006" does not match
#> character(0)
```
