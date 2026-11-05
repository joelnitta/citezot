# Delete citezot's cached library data

Removes cache files created by
[`cz_fetch_items()`](https://joelnitta.github.io/citezot/reference/cz_fetch_items.md)
when caching is enabled. Only citezot's own cache files are removed;
nothing in Zotero is touched.

## Usage

``` r
cz_clear_cache(auth = NULL)
```

## Arguments

- auth:

  Credentials from
  [`cz_auth()`](https://joelnitta.github.io/citezot/reference/cz_auth.md)
  to clear just that library's cache, or `NULL` (default) to clear every
  cached library.

## Value

Invisibly, the number of files removed.

## Examples

``` r
# Use an empty temporary cache directory so nothing real is deleted
old <- options(citezot.cache_dir = tempfile("citezot-cache"))
cz_clear_cache()
options(old)
```
