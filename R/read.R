#' Fetch every top-level item in a Zotero library as CSL-JSON
#'
#' Uses the `/items/top` endpoint (excludes notes, attachments and other child
#' items) and pages through the whole library using the `Total-Results`
#' header. After the first page, the remaining pages are requested in parallel
#' (at most `getOption("citezot.max_active", 4)` at a time, and throttled) and
#' the library version is checked so that a library edited mid-download is
#' re-fetched rather than returned inconsistent.
#'
#' A full download of a large library takes a while. With `cache = TRUE` the
#' items are stored in a local file (in `tools::R_user_dir("citezot", "cache")`,
#' or `getOption("citezot.cache_dir")`), and later calls download only what
#' changed since: one request if nothing changed, otherwise the changed items
#' plus the lists of deleted and trashed items. The cache holds the library's
#' bibliographic metadata, never your API key. It is opt-in: nothing is
#' written to disk unless you ask, either here or with
#' `options(citezot.cache = TRUE)`. Use `refresh = TRUE` to ignore the cache
#' and download everything again, and [cz_clear_cache()] to delete it.
#'
#' @param auth Credentials from [cz_auth()].
#' @param page_size Items per request (Zotero's maximum is 100).
#' @param cache Use and update the local cache? Defaults to
#'   `getOption("citezot.cache", FALSE)`.
#' @param refresh If `TRUE`, ignore any existing cache and download the whole
#'   library (the cache, if enabled, is then rewritten).
#'
#' @return A list of CSL-JSON items (plain lists, `simplifyVector = FALSE`).
#'   The order is not guaranteed.
#' @export
#' @examples
#' \dontrun{
#' items <- cz_fetch_items()
#' length(items)
#'
#' # Keep a local copy, so later calls download only what changed
#' items <- cz_fetch_items(cache = TRUE)
#' }
cz_fetch_items <- function(
  auth = cz_auth(),
  page_size = 100,
  cache = getOption("citezot.cache", FALSE),
  refresh = FALSE
) {
  rlang::check_number_whole(page_size, min = 1, max = 100)
  rlang::check_bool(cache)
  rlang::check_bool(refresh)

  if (!cache) {
    if (interactive()) {
      cli::cli_inform(
        c(
          i = paste0(
            "Tip: {.code options(citezot.cache = TRUE)} caches the library ",
            "locally so later runs download only what changed."
          )
        ),
        .frequency = "once",
        .frequency_id = "citezot_cache_hint"
      )
    }
    return(cz_fetch_pages(auth, page_size)$items)
  }

  cached <- if (refresh) NULL else cz_cache_read(auth)

  if (is.null(cached)) {
    full <- cz_fetch_pages(auth, page_size)
    if (!is.na(full$version)) {
      cz_cache_write(auth, full$version, cz_name_items(full$items))
    }
    return(full$items)
  }

  changes <- cz_fetch_pages(auth, page_size, since = cached$version)
  if (changes$unchanged) {
    return(unname(cached$items))
  }

  items <- cached$items
  # permanently deleted and trashed items are not returned by /items/top, so
  # they must be asked for explicitly
  removed <- cz_fetch_removed(auth, cached$version)
  items <- items[!names(items) %in% removed]
  changed <- cz_name_items(changes$items)
  items[names(changed)] <- changed
  if (!is.na(changes$version)) {
    cz_cache_write(auth, changes$version, items)
  }
  unname(items[order(names(items), method = "radix")])
}

# Name CSL items by their Zotero item key (CSL ids look like "libraryID/KEY").
cz_name_items <- function(items) {
  stats::setNames(
    items,
    vapply(items, function(i) sub("^.*/", "", i$id), character(1))
  )
}

# Keys of items permanently deleted or moved to the trash since `version`.
cz_fetch_removed <- function(auth, version) {
  deleted <- cz_request(auth, "deleted") |>
    httr2::req_url_query(since = version) |>
    cz_perform() |>
    httr2::resp_body_json(simplifyVector = FALSE)
  trash_resp <- cz_request(auth, "items", "trash") |>
    httr2::req_url_query(format = "keys", since = version) |>
    cz_perform()
  # an empty trash comes back as an empty body
  trashed <- if (httr2::resp_has_body(trash_resp)) {
    httr2::resp_body_string(trash_resp)
  } else {
    ""
  }
  keys <- c(
    as.character(unlist(deleted$items)),
    strsplit(trashed, "\n", fixed = TRUE)[[1]]
  )
  keys[nzchar(keys)]
}

# Fetch all pages of /items/top as CSL-JSON. Returns
# list(items, version, unchanged). With `since`, only items changed after that
# library version are returned, and a library that has not changed at all
# answers 304 (unchanged = TRUE). If the library is edited while pages are
# downloading (the Last-Modified-Version header differs between pages) the
# download is repeated once, then fails.
cz_fetch_pages <- function(auth, page_size, since = NULL, retries = 1) {
  page_req <- function(start) {
    req <- cz_request(auth, "items", "top") |>
      httr2::req_url_query(
        format = "csljson",
        limit = page_size,
        start = start
      ) |>
      httr2::req_throttle(rate = 5)
    if (!is.null(since)) req <- httr2::req_url_query(req, since = since)
    req
  }

  first_req <- page_req(0)
  if (!is.null(since)) {
    first_req <- httr2::req_headers(
      first_req,
      `If-Modified-Since-Version` = as.character(since)
    )
  }
  first <- cz_perform(first_req)
  if (httr2::resp_status(first) == 304) {
    return(list(items = list(), version = as.integer(since), unchanged = TRUE))
  }
  total <- as.integer(httr2::resp_header(first, "Total-Results", "0"))
  starts <- if (total > page_size) {
    seq(page_size, total - 1, by = page_size)
  } else {
    integer(0)
  }
  rest <- if (length(starts)) {
    cz_perform_parallel(lapply(
      starts,
      page_req
    ))
  } else {
    list()
  }

  versions <- vapply(c(list(first), rest), cz_resp_version, integer(1))
  versions <- versions[!is.na(versions)]
  if (length(unique(versions)) > 1) {
    if (retries > 0) {
      return(cz_fetch_pages(
        auth,
        page_size,
        since = since,
        retries = retries - 1
      ))
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
    version = if (length(versions)) versions[[1]] else NA_integer_,
    unchanged = FALSE
  )
}
