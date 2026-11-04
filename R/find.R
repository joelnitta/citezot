#' Find items in your Zotero library
#'
#' Searches the library for items matching *all* the criteria given. Matching
#' is done locally on the library's CSL-JSON (see [cz_fetch_items()]), because
#' Zotero's server-side search cannot look items up by DOI or citekey. Use
#' `cache = TRUE` (or `options(citezot.cache = TRUE)`) to make this fast on
#' repeat calls.
#'
#' @param query Free text. Every word must appear (case-insensitively) in the
#'   title, authors, year, journal or citekey.
#' @param doi A DOI, with or without a `https://doi.org/` or `doi:` prefix.
#' @param isbn An ISBN (hyphens and spaces are ignored).
#' @param citekey An exact pinned citekey.
#' @param auth Credentials from [cz_auth()].
#' @param cache Passed to [cz_fetch_items()].
#' @param items Items already fetched with [cz_fetch_items()], to avoid
#'   fetching again.
#'
#' @return A data frame with one row per match and columns `item` (Zotero item
#'   ID), `citekey`, `author`, `year`, `title`, `doi` and `type`. It can be
#'   passed as the `item` argument of [cz_pin_key()] when it has one row.
#' @export
#' @examples
#' \dontrun{
#' cz_find(doi = "10.3767/000651906X622210")
#' cz_find("Ebihara Hymenophyllaceae revision")
#' cz_find(citekey = "Ebihara2006")
#' }
cz_find <- function(
  query = NULL,
  doi = NULL,
  isbn = NULL,
  citekey = NULL,
  auth = cz_auth(),
  cache = getOption("citezot.cache", FALSE),
  items = NULL
) {
  for (x in list(query, doi, isbn, citekey)) {
    if (!is.null(x)) rlang::check_string(x)
  }
  if (is.null(query) && is.null(doi) && is.null(isbn) && is.null(citekey)) {
    cli::cli_abort("Give at least one of {.arg query}, {.arg doi}, {.arg isbn} or {.arg citekey}.")
  }
  if (is.null(items)) items <- cz_fetch_items(auth, cache = cache)

  tab <- cz_items_table(items)
  keep <- rep(TRUE, nrow(tab))
  if (!is.null(doi)) {
    keep <- keep & !is.na(tab$doi_norm) & tab$doi_norm == cz_norm_doi(doi)
  }
  if (!is.null(isbn)) {
    want <- cz_norm_isbn(isbn)
    keep <- keep & vapply(tab$isbn_norm, function(x) want %in% x, logical(1))
  }
  if (!is.null(citekey)) {
    keep <- keep & !is.na(tab$citekey) & tab$citekey == citekey
  }
  if (!is.null(query)) {
    for (w in strsplit(tolower(trimws(query)), "\\s+")[[1]]) {
      keep <- keep & grepl(w, tab$haystack, fixed = TRUE)
    }
  }

  out <- tab[keep, c("item", "citekey", "author", "year", "title", "doi", "type"), drop = FALSE]
  out <- out[order(out$citekey, method = "radix", na.last = TRUE), , drop = FALSE]
  rownames(out) <- NULL
  out
}

# --- helpers -----------------------------------------------------------------

cz_norm_doi <- function(x) {
  x <- tolower(trimws(x))
  sub("^(https?://(dx\\.)?doi\\.org/|doi:\\s*)", "", x)
}

cz_norm_isbn <- function(x) {
  toupper(gsub("[^0-9Xx]", "", unlist(strsplit(x, "[ ,;]+(?=[0-9])", perl = TRUE))))
}

cz_chr1 <- function(x) {
  if (is.null(x) || !length(x)) NA_character_ else as.character(x[[1]])
}

# One row per CSL item, with the columns cz_find() shows plus normalised and
# search-only columns.
cz_items_table <- function(items) {
  chr <- function(f) vapply(items, f, character(1))
  names_of <- function(i) {
    people <- i$author
    if (is.null(people) || !length(people)) people <- i$editor
    vapply(people %||% list(), function(p) cz_chr1(p$family %||% p$literal), character(1))
  }
  year_of <- function(i) {
    y <- tryCatch(i$issued$`date-parts`[[1]][[1]], error = function(e) NULL)
    if (is.null(y)) NA_character_ else as.character(y)
  }
  author_label <- function(i) {
    n <- names_of(i)
    n <- n[!is.na(n)]
    if (!length(n)) NA_character_ else if (length(n) == 1) n else if (length(n) == 2) paste(n, collapse = " & ") else paste(n[1], "et al.")
  }
  tab <- data.frame(
    item = chr(function(i) sub("^.*/", "", cz_chr1(i$id))),
    citekey = chr(cz_item_key),
    author = chr(author_label),
    year = chr(year_of),
    title = chr(function(i) cz_chr1(i$title)),
    doi = chr(function(i) cz_chr1(i$DOI)),
    type = chr(function(i) cz_chr1(i$type)),
    doi_norm = chr(function(i) {
      d <- cz_chr1(i$DOI)
      if (is.na(d)) NA_character_ else cz_norm_doi(d)
    }),
    haystack = chr(function(i) {
      parts <- c(
        cz_chr1(i$title), paste(names_of(i), collapse = " "), year_of(i),
        cz_chr1(i$`container-title`), cz_item_key(i)
      )
      tolower(paste(parts[!is.na(parts)], collapse = " "))
    }),
    stringsAsFactors = FALSE
  )
  tab$isbn_norm <- lapply(items, function(i) {
    isbn <- cz_chr1(i$ISBN)
    if (is.na(isbn)) character(0) else cz_norm_isbn(isbn)
  })
  tab
}

# Turn whatever the user gave as `item` into a Zotero item ID.
#   * a one-row data frame from cz_find()
#   * a Zotero item ID ("Q62TD7I9" or "1234/Q62TD7I9")
#   * a DOI (or doi.org URL)
#   * an exact pinned citekey
# Errors if nothing, or more than one item, matches.
cz_resolve_item <- function(item, auth, cache = getOption("citezot.cache", FALSE), items = NULL) {
  if (is.data.frame(item)) {
    if (!"item" %in% names(item) || nrow(item) != 1) {
      cli::cli_abort("{.arg item} must be a single item: a data frame from {.fn cz_find} needs exactly one row (it has {nrow(item)}).")
    }
    return(item$item)
  }
  rlang::check_string(item, arg = "item")
  bare <- sub("^[0-9]+/", "", item)
  if (grepl("^(10\\.[0-9]{4,9}/|https?://(dx\\.)?doi\\.org/|doi:)", item, ignore.case = TRUE)) {
    hits <- cz_find(doi = item, auth = auth, cache = cache, items = items)
    what <- sprintf("DOI %s", item)
  } else if (grepl("^[23456789ABCDEFGHIJKLMNPQRSTUVWXYZ]{8}$", bare)) {
    return(bare)
  } else {
    hits <- cz_find(citekey = item, auth = auth, cache = cache, items = items)
    what <- sprintf("citekey %s", item)
  }
  if (nrow(hits) == 0) {
    cli::cli_abort("No item in the library matches {what}.")
  }
  if (nrow(hits) > 1) {
    shown <- utils::head(sprintf("%s (%s): %s", hits$item, hits$citekey, substr(hits$title, 1, 50)), 5)
    cli::cli_abort(c(
      "{nrow(hits)} items match {what}; be more specific.",
      stats::setNames(shown, rep("*", length(shown)))
    ))
  }
  hits$item
}
