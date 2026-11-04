# Internal Zotero Web API v3 plumbing. Every request goes through
# cz_request() / cz_perform() so headers, auth, retry and error messages live
# in one place.

cz_base_url <- function() {
  getOption("citezot.base_url", "https://api.zotero.org")
}

# Seconds to wait before retrying, from Retry-After or Backoff headers.
# NA lets httr2 fall back to its own exponential backoff.
cz_retry_after <- function(resp) {
  h <- httr2::resp_header(resp, "Retry-After")
  if (is.null(h)) h <- httr2::resp_header(resp, "Backoff")
  if (is.null(h)) {
    return(NA_real_)
  }
  suppressWarnings(as.numeric(h))
}

# Build a request under the library path, e.g. cz_request(auth, "items", "top")
# -> https://api.zotero.org/users/<id>/items/top
cz_request <- function(auth, ...) {
  type_path <- if (auth$library_type == "group") "groups" else "users"
  httr2::request(cz_base_url()) |>
    httr2::req_url_path_append(type_path, auth$library_id, ...) |>
    httr2::req_headers(`Zotero-API-Version` = "3") |>
    httr2::req_auth_bearer_token(auth$api_key) |>
    httr2::req_user_agent("citezot") |>
    httr2::req_retry(
      max_tries = 3,
      is_transient = function(resp) httr2::resp_status(resp) %in% c(429, 503),
      after = cz_retry_after
    )
}

# Perform a request, turning the common Zotero failures into clear errors.
cz_perform <- function(req) {
  tryCatch(
    httr2::req_perform(req),
    httr2_http_412 = function(e) {
      cli::cli_abort(c(
        "The item changed in Zotero since it was read (HTTP 412).",
        "i" = "Nothing was written. Re-fetch the item, check the new version, and retry deliberately."
      ), call = NULL)
    },
    httr2_http_403 = function(e) {
      cli::cli_abort(c(
        "Zotero refused the request (HTTP 403).",
        "i" = "Check that the API key is valid and has the access this call needs (write calls need a key with write access)."
      ), call = NULL)
    }
  )
}
