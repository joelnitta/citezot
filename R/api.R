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

# Requests to Zotero endpoints that are not under a library (item templates,
# item types): same headers and retry, but no credentials.
cz_request_global <- function(...) {
  httr2::request(cz_base_url()) |>
    httr2::req_url_path_append(...) |>
    httr2::req_headers(`Zotero-API-Version` = "3") |>
    httr2::req_user_agent("citezot") |>
    httr2::req_retry(
      max_tries = 3,
      is_transient = function(resp) httr2::resp_status(resp) %in% c(429, 503),
      after = cz_retry_after
    )
}

# Evaluate `expr` (an httr2 perform call), turning the common Zotero failures
# into clear errors.
cz_translate_errors <- function(expr, on_412 = NULL) {
  tryCatch(
    expr,
    httr2_http_412 = function(e) {
      if (!is.null(on_412)) {
        cli::cli_abort(on_412, call = NULL)
      }
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

# Zotero's `Backoff: <seconds>` header can arrive on any response, including
# successful ones: finish what is needed, then pause before the next request.
# Remember the deadline and honour it before the next request is sent.
.cz_state <- new.env(parent = emptyenv())
.cz_state$backoff_until <- NULL
.cz_state$templates <- list()

cz_sleep <- function(seconds) Sys.sleep(seconds)

cz_note_backoff <- function(resp) {
  h <- suppressWarnings(as.numeric(httr2::resp_header(resp, "Backoff", NA)))
  if (!is.na(h) && h > 0) {
    .cz_state$backoff_until <- Sys.time() + min(h, 300)
  }
  invisible(resp)
}

cz_wait_backoff <- function() {
  until <- .cz_state$backoff_until
  if (!is.null(until)) {
    wait <- as.numeric(difftime(until, Sys.time(), units = "secs"))
    .cz_state$backoff_until <- NULL
    if (wait > 0) {
      cli::cli_inform(c("i" = "Zotero asked for a pause; waiting {round(wait)} second{?s}."))
      cz_sleep(wait)
    }
  }
  invisible()
}

cz_perform <- function(req, on_412 = NULL) {
  cz_wait_backoff()
  resp <- cz_translate_errors(httr2::req_perform(req), on_412 = on_412)
  cz_note_backoff(resp)
  resp
}

# Perform several requests with a small, capped concurrency. Requests should
# already be throttled (see cz_fetch_pages()) so we stay polite to the API.
cz_perform_parallel <- function(reqs) {
  cz_wait_backoff()
  resps <- cz_translate_errors(
    httr2::req_perform_parallel(
      reqs,
      max_active = getOption("citezot.max_active", 4),
      on_error = "stop",
      progress = interactive()
    )
  )
  for (r in resps) cz_note_backoff(r)
  resps
}

# Library version from a response (NA if the header is absent).
cz_resp_version <- function(resp) {
  suppressWarnings(as.integer(httr2::resp_header(resp, "Last-Modified-Version", NA)))
}
