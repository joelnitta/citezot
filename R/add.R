#' Add an item to your Zotero library from a DOI
#'
#' Looks up the metadata for a DOI (via the public Crossref API), checks that
#' the item is not already in your library, and creates it. The default is a
#' **dry run**: the library is *read* and Crossref is queried, but nothing is
#' written to Zotero. Use `dry_run = FALSE` to create the item.
#'
#' The new item is built from Zotero's own template for its type, so it only
#' contains fields valid for that type. The citekey, if you give one, is pinned
#' in the same request (the native `citationKey` field), so there is no moment
#' where the item exists without it. Only DOIs registered with Crossref are
#' supported for now; ISBN, arXiv and PMID lookups are planned.
#'
#' Creating is retry-safe: each request carries a random `Zotero-Write-Token`,
#' so a retried request after a network hiccup cannot create the item twice.
#' Existing items are never changed or deleted.
#'
#' Crossref asks clients to identify themselves with a contact address to use
#' its faster pool. citezot never sends an address by itself; to opt in, set
#' `options(citezot.mailto = "you@example.org")`.
#'
#' @param id A DOI, with or without a `https://doi.org/` or `doi:` prefix.
#' @param key Optional citekey to pin on the new item, e.g. `"Kent2002"`. It
#'   must be usable as a pandoc citation key and not already used in your
#'   library. Use `"auto"` to generate one from your Better BibTeX formula
#'   (see [cz_suggest_key()] and [cz_key_format()]); a letter is appended if
#'   the key is taken. The key is shown in the dry run.
#' @param collection Optional collection to add the item to: its 8-character
#'   key, or its exact name.
#' @param dry_run If `TRUE` (default), show what would be created and write
#'   nothing.
#' @param auth Credentials from [cz_auth()] (a key with write access to write).
#' @param cache Passed to [cz_fetch_items()], which is used for the duplicate
#'   check.
#'
#' @return Invisibly, a list with `item` (the payload), `key` (the new Zotero
#'   item ID, or `NULL`), `existing` (matching rows of [cz_find()] if the item
#'   was already in the library) and `written`.
#' @export
#' @examples
#' \dontrun{
#' cz_add("10.3767/000651906X622210", key = "Ebihara2006")        # preview
#' cz_add("10.3767/000651906X622210", key = "Ebihara2006", dry_run = FALSE)
#' }
cz_add <- function(
  id,
  key = NULL,
  collection = NULL,
  dry_run = TRUE,
  auth = cz_auth(),
  cache = getOption("citezot.cache", FALSE)
) {
  rlang::check_string(id)
  if (!is.null(key)) rlang::check_string(key)
  if (!is.null(collection)) rlang::check_string(collection)
  rlang::check_bool(dry_run)
  doi <- cz_add_doi_or_abort(id)
  auto_key <- identical(key, "auto")
  if (!is.null(key) && !auto_key) cz_check_key_syntax(key)

  items <- cz_fetch_items(auth, cache = cache)

  existing <- cz_find(doi = doi, items = items)
  if (nrow(existing) > 0) {
    cli::cli_inform(c(
      "i" = "Already in your library, nothing added: item {existing$item[1]}{if (!is.na(existing$citekey[1])) paste0(' (', existing$citekey[1], ')') else ''}."
    ))
    return(invisible(list(item = NULL, key = NULL, existing = existing, written = FALSE)))
  }
  if (!is.null(key) && !auto_key) {
    clash <- cz_find(citekey = key, items = items)
    if (nrow(clash) > 0) {
      cli::cli_abort(c(
        "The citekey {.val {key}} is already used by item {clash$item[1]}.",
        "i" = "Choose another key."
      ))
    }
  }
  coll_key <- if (is.null(collection)) NULL else cz_resolve_collection(auth, collection)

  msg <- cz_crossref_fetch(doi)
  type <- cz_crossref_type(msg$type %||% "")
  built <- cz_crossref_to_item(msg, type, cz_item_template_fields(type))
  item <- built$item
  if (auto_key) {
    taken <- vapply(items, cz_item_key, character(1))
    key <- cz_suggest_key(item, existing = taken[!is.na(taken)])
  }
  if (!is.null(key)) item$citationKey <- key
  if (!is.null(coll_key)) item$collections <- list(coll_key)

  result <- list(item = item, key = NULL, existing = NULL, written = FALSE)
  lines <- cz_describe_new_item(item, coll_key)

  if (dry_run) {
    cli::cli_inform(c(
      "i" = "Dry run: nothing written. Use {.code dry_run = FALSE} to add this item.",
      lines
    ))
    return(invisible(result))
  }

  token <- rlang::hash(list(Sys.time(), Sys.getpid(), tempfile(), proc.time(), doi))
  resp <- cz_request(auth, "items") |>
    httr2::req_method("POST") |>
    httr2::req_headers(`Zotero-Write-Token` = token) |>
    httr2::req_body_json(list(item), auto_unbox = TRUE) |>
    cz_perform(on_412 = c(
      "Zotero reports this request was already processed (HTTP 412, write token reused).",
      "i" = "The item was most likely created by an earlier attempt: check your library before retrying."
    ))
  new_key <- cz_new_item_key(httr2::resp_body_json(resp, simplifyVector = FALSE))

  cli::cli_inform(c("v" = "Added item {new_key}.", lines))
  result$key <- new_key
  result$written <- TRUE
  invisible(result)
}

cz_add_doi_or_abort <- function(id) {
  if (!grepl("^(10\\.[0-9]{4,9}/|https?://(dx\\.)?doi\\.org/|doi:)", id, ignore.case = TRUE)) {
    cli::cli_abort(c(
      "{.val {id}} doesn't look like a DOI.",
      "i" = "Only DOIs are supported so far; ISBN, arXiv and PMID lookups are planned."
    ))
  }
  doi <- cz_norm_doi(id)
  if (!grepl("^10\\.[0-9]{4,9}/\\S+$", doi)) {
    cli::cli_abort("{.val {id}} doesn't look like a DOI.")
  }
  doi
}

# The key must work as a pandoc citation key, or the item could be pinned but
# never cited.
cz_check_key_syntax <- function(key) {
  ok <- grepl("(*UCP)^[[:alnum:]_][[:alnum:]_:.#$%&+?<>~/-]*$", key, perl = TRUE) &&
    !grepl("[:.#$%&+?<>~/-]$", key, perl = TRUE)
  if (!ok) {
    cli::cli_abort(c(
      "{.val {key}} can't be used as a pandoc citation key.",
      "i" = "Start with a letter, digit or underscore; use letters, digits and internal punctuation only."
    ))
  }
}

# Valid field names for an item type, from Zotero's item template (cached for
# the session: the schema doesn't change within one).
cz_item_template_fields <- function(type) {
  cached <- .cz_state$templates[[type]]
  if (!is.null(cached)) {
    return(cached)
  }
  fields <- cz_request_global("items", "new") |>
    httr2::req_url_query(itemType = type) |>
    cz_perform() |>
    httr2::resp_body_json(simplifyVector = FALSE) |>
    names()
  .cz_state$templates[[type]] <- fields
  fields
}

# --- collections ---------------------------------------------------------------

cz_collections <- function(auth) {
  out <- list()
  start <- 0
  repeat {
    resp <- cz_request(auth, "collections") |>
      httr2::req_url_query(limit = 100, start = start) |>
      cz_perform()
    page <- httr2::resp_body_json(resp, simplifyVector = FALSE)
    out <- c(out, page)
    total <- as.integer(httr2::resp_header(resp, "Total-Results", "0"))
    start <- start + 100
    if (start >= total || !length(page)) break
  }
  data.frame(
    key = vapply(out, function(x) x$key, character(1)),
    name = vapply(out, function(x) x$data$name, character(1)),
    stringsAsFactors = FALSE
  )
}

# Collection key from a key or an exact name.
cz_resolve_collection <- function(auth, x) {
  all <- cz_collections(auth)
  by_key <- all$key[all$key == x]
  if (length(by_key) == 1) {
    return(by_key)
  }
  by_name <- all[all$name == x, , drop = FALSE]
  if (nrow(by_name) == 1) {
    return(by_name$key)
  }
  if (nrow(by_name) > 1) {
    cli::cli_abort(c(
      "{nrow(by_name)} collections are named {.val {x}}; use the key instead.",
      stats::setNames(sprintf("%s (%s)", by_name$name, by_name$key), rep("*", nrow(by_name)))
    ))
  }
  cli::cli_abort("No collection with the key or exact name {.val {x}}.")
}

# --- output --------------------------------------------------------------------

cz_describe_new_item <- function(item, coll_key = NULL) {
  creators <- vapply(item$creators %||% list(), function(cr) {
    if (!is.null(cr$name)) cr$name else paste(cr$lastName, cr$firstName)
  }, character(1))
  creators <- if (length(creators) > 3) c(creators[1:3], "...") else creators
  one <- function(label, value) {
    if (is.null(value) || !length(value) || !nzchar(paste(value, collapse = ""))) {
      return(NULL)
    }
    cz_cli_escape(sprintf("%s: %s", label, cz_show_value(paste(value, collapse = "; "), 90)))
  }
  container <- item$publicationTitle %||% item$bookTitle %||% item$proceedingsTitle %||%
    item$repository %||% item$university
  parts <- c(
    one("type", item$itemType), one("title", item$title), one("authors", creators),
    one("date", item$date), one("in", container), one("DOI", item$DOI),
    one("citekey", item$citationKey), one("collection", coll_key)
  )
  stats::setNames(parts, rep("*", length(parts)))
}

# Key of the created item from Zotero's write response. The docs name the map
# of successes both `successful` (full objects) and `success` (just keys).
cz_new_item_key <- function(body) {
  k <- body$successful[["0"]]$key %||% body$success[["0"]]
  if (!is.null(k)) {
    return(k)
  }
  failed <- body$failed[["0"]]
  if (!is.null(failed)) {
    cli::cli_abort(c(
      "Zotero did not create the item: {failed$message %||% 'unknown error'} (code {failed$code %||% '?'}).",
      "i" = "Nothing was added."
    ))
  }
  if (length(body$unchanged)) {
    cli::cli_abort("Zotero reports the item as unchanged; nothing was added.")
  }
  cli::cli_abort("Unexpected response from Zotero when creating the item; check your library.")
}
