# Optional on-disk cache of a library's CSL-JSON items.
#
# Opt-in only (options(citezot.cache = TRUE) or cache = TRUE): nothing is
# written to the user's file space unless asked. The cache holds bibliographic
# metadata from the library and the library version it corresponds to; it
# never contains the API key. One file per library.

cz_cache_dir <- function() {
  getOption("citezot.cache_dir", tools::R_user_dir("citezot", "cache"))
}

cz_cache_file <- function(auth) {
  file.path(cz_cache_dir(), sprintf("%s-%s.rds", auth$library_type, auth$library_id))
}

# Returns list(version, items) or NULL if absent/unreadable/invalid. A bad
# cache is never an error: the caller just does a full fetch.
cz_cache_read <- function(auth) {
  path <- cz_cache_file(auth)
  if (!file.exists(path)) {
    return(NULL)
  }
  x <- tryCatch(readRDS(path), error = function(e) NULL)
  ok <- is.list(x) &&
    identical(x$schema, 1L) &&
    identical(x$library_id, auth$library_id) &&
    identical(x$library_type, auth$library_type) &&
    is.numeric(x$version) && length(x$version) == 1 && !is.na(x$version) &&
    is.list(x$items)
  if (!ok) NULL else x
}

# Write atomically (temp file, then rename) so an interrupted write cannot
# leave a truncated cache behind.
cz_cache_write <- function(auth, version, items) {
  path <- cz_cache_file(auth)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  saveRDS(
    list(
      schema = 1L,
      library_id = auth$library_id,
      library_type = auth$library_type,
      version = as.integer(version),
      items = items
    ),
    tmp
  )
  file.rename(tmp, path)
  invisible(path)
}

#' Delete citezot's cached library data
#'
#' Removes cache files created by [cz_fetch_items()] when caching is enabled.
#' Only citezot's own cache files are removed; nothing in Zotero is touched.
#'
#' @param auth Credentials from [cz_auth()] to clear just that library's
#'   cache, or `NULL` (default) to clear every cached library.
#'
#' @return Invisibly, the number of files removed.
#' @export
#' @examples
#' # Use an empty temporary cache directory so nothing real is deleted
#' old <- options(citezot.cache_dir = tempfile("citezot-cache"))
#' cz_clear_cache()
#' options(old)
cz_clear_cache <- function(auth = NULL) {
  files <- if (is.null(auth)) {
    list.files(cz_cache_dir(), pattern = "^(user|group)-[0-9]+\\.rds$", full.names = TRUE)
  } else {
    f <- cz_cache_file(auth)
    f[file.exists(f)]
  }
  invisible(sum(file.remove(files)))
}
