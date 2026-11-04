#' Fetch every top-level item in a Zotero library as CSL-JSON
#'
#' Uses the `/items/top` endpoint (excludes notes, attachments and other child
#' items) and pages through the whole library using the `Total-Results`
#' header. After the first page, the remaining pages are requested in parallel
#' (at most `getOption("citezot.max_active", 4)` at a time, and throttled) and
#' the library version is checked so that a library edited mid-download is
#' re-fetched rather than returned inconsistent.
#'
#' @param auth Credentials from [cz_auth()].
#' @param page_size Items per request (Zotero's maximum is 100).
#'
#' @return A list of CSL-JSON items (plain lists, `simplifyVector = FALSE`).
#' @export
cz_fetch_items <- function(auth = cz_auth(), page_size = 100) {
  rlang::check_number_whole(page_size, min = 1, max = 100)
  cz_fetch_pages(auth, page_size)$items
}

# Fetch all pages of /items/top as CSL-JSON. Returns
# list(items, version). If the library is edited while pages are downloading
# (the Last-Modified-Version header differs between pages) the download is
# repeated once, then fails.
cz_fetch_pages <- function(auth, page_size, retries = 1) {
  page_req <- function(start) {
    cz_request(auth, "items", "top") |>
      httr2::req_url_query(format = "csljson", limit = page_size, start = start) |>
      httr2::req_throttle(rate = 5)
  }

  first <- cz_perform(page_req(0))
  total <- as.integer(httr2::resp_header(first, "Total-Results", "0"))
  starts <- if (total > page_size) {
    seq(page_size, total - 1, by = page_size)
  } else {
    integer(0)
  }
  rest <- if (length(starts)) cz_perform_parallel(lapply(starts, page_req)) else list()

  versions <- vapply(c(list(first), rest), cz_resp_version, integer(1))
  versions <- versions[!is.na(versions)]
  if (length(unique(versions)) > 1) {
    if (retries > 0) {
      return(cz_fetch_pages(auth, page_size, retries = retries - 1))
    }
    cli::cli_abort(c(
      "The Zotero library changed while it was being downloaded.",
      "i" = "Run the command again."
    ))
  }

  items <- lapply(c(list(first), rest), function(r) {
    httr2::resp_body_json(r, simplifyVector = FALSE)$items
  })
  list(
    items = unlist(items, recursive = FALSE),
    version = if (length(versions)) versions[[1]] else NA_integer_
  )
}
