#' Zotero credentials
#'
#' Resolves the library ID and API key, by default from the environment
#' variables `ZOTERO_LIBRARY_ID` (or, for a user library, `ZOTERO_USER_ID`)
#' and `ZOTERO_API_KEY`. Load them yourself
#' (e.g. from a gitignored `.Renviron` or `.env.local`); citezot never reads
#' files or stores the key. The key is never printed.
#'
#' Create a key at <https://www.zotero.org/settings/keys>; the numeric user ID
#' is on the same page. A read-only key is enough for [cz_fetch_items()];
#' use a separate key with write access for functions that change the library.
#'
#' @param library_id Numeric user ID (or group ID), as a string or number.
#'   If `NULL` (default), taken from `ZOTERO_LIBRARY_ID`; for a user library
#'   `ZOTERO_USER_ID` is used as a fallback.
#' @param api_key Zotero API key.
#' @param library_type `"user"` (personal library) or `"group"`.
#'
#' @return A `cz_auth` object, for the `auth` argument of other functions.
#' @export
#' @examples
#' # Explicit values (normally these come from environment variables). The key
#' # is never shown when the object is printed.
#' cz_auth(library_id = "1234567", api_key = "not-a-real-key")
cz_auth <- function(
  library_id = NULL,
  api_key = Sys.getenv("ZOTERO_API_KEY"),
  library_type = c("user", "group")
) {
  library_type <- rlang::arg_match(library_type)
  if (is.null(library_id)) {
    library_id <- Sys.getenv("ZOTERO_LIBRARY_ID")
    if (!nzchar(library_id) && library_type == "user") {
      library_id <- Sys.getenv("ZOTERO_USER_ID")
    }
  }
  library_id <- as.character(library_id)
  if (length(library_id) != 1 || is.na(library_id) || !nzchar(library_id) ||
    !rlang::is_string(api_key) || !nzchar(api_key)) {
    cli::cli_abort(c(
      "Zotero credentials not found.",
      "i" = "Set {.envvar ZOTERO_LIBRARY_ID} (or {.envvar ZOTERO_USER_ID} for a user library) and {.envvar ZOTERO_API_KEY}, or pass {.arg library_id} and {.arg api_key}.",
      "i" = "Create a key at {.url https://www.zotero.org/settings/keys}."
    ))
  }
  structure(
    list(library_id = library_id, api_key = api_key, library_type = library_type),
    class = "cz_auth"
  )
}

#' @export
print.cz_auth <- function(x, ...) {
  cli::cli_text("<cz_auth> {x$library_type} library {x$library_id} (API key hidden)")
  invisible(x)
}
