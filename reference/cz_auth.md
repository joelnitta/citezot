# Zotero credentials

Resolves the library ID and API key, by default from the environment
variables `ZOTERO_LIBRARY_ID` (or, for a user library, `ZOTERO_USER_ID`)
and `ZOTERO_API_KEY`. Load them yourself (e.g. from a gitignored
`.Renviron` or `.env.local`); citezot never reads files or stores the
key. The key is never printed.

## Usage

``` r
cz_auth(
  library_id = NULL,
  api_key = Sys.getenv("ZOTERO_API_KEY"),
  library_type = c("user", "group")
)
```

## Arguments

- library_id:

  Numeric user ID (or group ID), as a string or number. If `NULL`
  (default), taken from `ZOTERO_LIBRARY_ID`; for a user library
  `ZOTERO_USER_ID` is used as a fallback.

- api_key:

  Zotero API key.

- library_type:

  `"user"` (personal library) or `"group"`.

## Value

A `cz_auth` object, for the `auth` argument of other functions.

## Details

Create a key at <https://www.zotero.org/settings/keys>; the numeric user
ID is on the same page. A read-only key is enough for
[`cz_fetch_items()`](https://joelnitta.github.io/citezot/reference/cz_fetch_items.md);
use a separate key with write access for functions that change the
library.

## Examples

``` r
# Explicit values (normally these come from environment variables). The key
# is never shown when the object is printed.
cz_auth(library_id = "1234567", api_key = "not-a-real-key")
#> <cz_auth> user library 1234567 (API key hidden)
```
