# Which key formula citezot will use

In order: `getOption("citezot.key_format")`; the Better BibTeX pattern
in your Zotero profile (see Details); Better BibTeX's default pattern.

## Usage

``` r
cz_key_format()
```

## Value

A list with `formula` and `source` (`"option"`, `"zotero profile"` or
`"default"`).

## Details

Detection of the Zotero profile reads one line of its `prefs.js` and
only happens when a key is generated, never at load. Set
`options(citezot.key_format = ...)` to choose a formula yourself and
skip the detection, and `options(citezot.zotero_profile = "<folder>")`
if Zotero keeps its profile somewhere unusual. The source in use is
reported once per session.

## Examples

``` r
options(citezot.key_format = "auth.lower + year")
cz_key_format()
#> $formula
#> [1] "auth.lower + year"
#> 
#> $source
#> [1] "option"
#> 
```
