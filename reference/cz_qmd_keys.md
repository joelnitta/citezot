# Extract pandoc citation keys used in a qmd/Rmd file

Strips fenced code blocks first (so `@` in R code is never mistaken for
a citation), finds `@key` tokens, then drops Quarto cross-references
(`@fig-x`, `@tbl-x`, `@eq-x`, ...), which use the same syntax but are
not bibliography citations.

## Usage

``` r
cz_qmd_keys(
  path,
  crossref_prefixes = c("fig", "tbl", "eq", "sec", "lst", "thm", "lem", "cor", "prp",
    "cnj", "def", "exm", "exr", "rem", "sol", "nte")
)
```

## Arguments

- path:

  Path to a .qmd or .Rmd file.

- crossref_prefixes:

  Cross-reference prefixes to drop (without the trailing hyphen).

## Value

Sorted character vector of unique citation keys (no leading `@`).

## Examples

``` r
qmd <- tempfile(fileext = ".qmd")
writeLines(c(
  "Species evolve by natural selection [@Darwin1859]; see @fig-map.",
  "```{r}",
  "x@slot  # not a citation",
  "```"
), qmd)
cz_qmd_keys(qmd)
#> [1] "Darwin1859"
```
