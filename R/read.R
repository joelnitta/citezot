#' Fetch every top-level item in a Zotero library as CSL-JSON
#'
#' Uses the `/items/top` endpoint (excludes notes, attachments and other child
#' items) and pages through the whole library using the `Total-Results`
#' header.
#'
#' @param auth Credentials from [cz_auth()].
#' @param page_size Items per request (Zotero's maximum is 100).
#'
#' @return A list of CSL-JSON items (plain lists, `simplifyVector = FALSE`).
#' @export
cz_fetch_items <- function(auth = cz_auth(), page_size = 100) {
  rlang::check_number_whole(page_size, min = 1, max = 100)

  fetch_page <- function(start) {
    resp <- cz_request(auth, "items", "top") |>
      httr2::req_url_query(format = "csljson", limit = page_size, start = start) |>
      cz_perform()
    list(
      total = as.integer(httr2::resp_header(resp, "Total-Results", "0")),
      items = httr2::resp_body_json(resp, simplifyVector = FALSE)$items
    )
  }

  first <- fetch_page(0)
  starts <- if (first$total > page_size) {
    seq(page_size, first$total - 1, by = page_size)
  } else {
    integer(0)
  }
  rest <- lapply(starts, function(s) fetch_page(s)$items)
  c(first$items, unlist(rest, recursive = FALSE))
}
