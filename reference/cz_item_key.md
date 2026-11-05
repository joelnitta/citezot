# Get a CSL item's pinned citekey, however it is pinned

Checks the native `citation-key` property first, then falls back to a
`Citation Key:` line in `note`.

## Usage

``` r
cz_item_key(item)
```

## Arguments

- item:

  A single CSL-JSON item (a list).

## Value

The citekey, or `NA_character_`.

## Examples

``` r
cz_item_key(list(`citation-key` = "Darwin1859"))
#> [1] "Darwin1859"
cz_item_key(list(note = "Citation Key: Darwin1859"))
#> [1] "Darwin1859"
cz_item_key(list(title = "No key pinned"))
#> [1] NA
```
