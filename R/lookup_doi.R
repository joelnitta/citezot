# DOI -> Zotero item, via the Crossref REST API (public; no key needed).
#
# Crossref is only a source of metadata. The result is mapped onto Zotero's
# native item JSON, using Zotero's own item template for the item type so the
# payload only contains fields that are valid for that type.

#' Fetch Crossref metadata for a DOI
#' @return The `message` part of Crossref's response (a list).
#' @noRd
cz_crossref_fetch <- function(doi) {
  enc <- gsub("%2F", "/", utils::URLencode(doi, reserved = TRUE), fixed = TRUE)
  req <- httr2::request("https://api.crossref.org/works") |>
    httr2::req_url_path_append(enc) |>
    httr2::req_user_agent("citezot (R package)") |>
    httr2::req_retry(max_tries = 3, is_transient = function(resp) httr2::resp_status(resp) %in% c(429, 503)) |>
    httr2::req_error(is_error = function(resp) FALSE)
  # Crossref asks for a contact address to use its faster "polite" pool. Only
  # sent if the user sets it; we never send an address on their behalf.
  mailto <- getOption("citezot.mailto")
  if (!is.null(mailto)) req <- httr2::req_url_query(req, mailto = mailto)

  resp <- httr2::req_perform(req)
  status <- httr2::resp_status(resp)
  if (status == 404) {
    cli::cli_abort(c(
      "Crossref has no record of the DOI {.val {doi}}.",
      "i" = "Check the DOI. It may be registered with another agency (e.g. DataCite), which is not supported yet."
    ))
  }
  if (status >= 400) {
    cli::cli_abort("Crossref returned HTTP {status} for the DOI {.val {doi}}.")
  }
  httr2::resp_body_json(resp, simplifyVector = FALSE)$message
}

# Crossref "type" -> Zotero item type
cz_crossref_type <- function(type) {
  map <- c(
    "journal-article" = "journalArticle",
    "book" = "book", "monograph" = "book", "edited-book" = "book",
    "reference-book" = "book", "book-set" = "book", "book-series" = "book",
    "book-chapter" = "bookSection", "book-section" = "bookSection",
    "book-part" = "bookSection", "reference-entry" = "bookSection",
    "proceedings-article" = "conferencePaper",
    "posted-content" = "preprint",
    "dissertation" = "thesis",
    "report" = "report", "report-component" = "report",
    "dataset" = "dataset"
  )
  out <- unname(map[type])
  if (length(out) != 1 || is.na(out)) "document" else out
}

# Strip markup from Crossref text. Titles keep the few tags Zotero renders
# (<i>, <b>, <sub>, <sup>); JATS/MathML wrappers and everything else go.
cz_strip_markup <- function(x, keep = c("i", "b", "sub", "sup")) {
  if (is.null(x) || is.na(x)) {
    return(NA_character_)
  }
  pattern <- if (length(keep)) {
    sprintf("<(?!/?(?:%s)\\b)[^>]*>", paste(keep, collapse = "|"))
  } else {
    "<[^>]*>"
  }
  x <- gsub(pattern, "", x, perl = TRUE)
  x <- gsub("&lt;", "<", x, fixed = TRUE)
  x <- gsub("&gt;", ">", x, fixed = TRUE)
  x <- gsub("&quot;", "\"", x, fixed = TRUE)
  x <- gsub("&apos;|&#39;", "'", x)
  x <- gsub("&amp;", "&", x, fixed = TRUE)
  trimws(gsub("\\s+", " ", x))
}

cz_crossref_date <- function(msg) {
  for (nm in c("issued", "published", "published-print", "published-online")) {
    parts <- tryCatch(unlist(msg[[nm]]$`date-parts`[[1]]), error = function(e) NULL)
    if (length(parts)) {
      return(paste(c(sprintf("%04d", parts[1]), sprintf("%02d", parts[-1])), collapse = "-"))
    }
  }
  NA_character_
}

# Old Crossref records often have names in ALL CAPS ("WATSON J. D."). Convert
# only names that are entirely upper case, word by word; initials such as
# "J." and mixed-case names ("McDonald") are left alone.
cz_fix_caps <- function(x) {
  if (is.null(x) || is.na(x) || !nzchar(x)) {
    return(x)
  }
  letters_only <- gsub("[^[:alpha:]]", "", x)
  if (nchar(letters_only) < 2 || letters_only != toupper(letters_only)) {
    return(x)
  }
  words <- strsplit(x, "(?<=[ -])", perl = TRUE)[[1]]
  fix <- function(w) {
    core <- gsub("[^[:alpha:]]", "", w)
    if (nchar(core) <= 1 || grepl(".", w, fixed = TRUE)) {
      w
    } else {
      paste0(toupper(substring(w, 1, 1)), tolower(substring(w, 2)))
    }
  }
  paste(vapply(words, fix, character(1)), collapse = "")
}

cz_crossref_creators <- function(msg) {
  one <- function(p, type) {
    if (!is.null(p$family) && nzchar(p$family)) {
      list(
        creatorType = type,
        firstName = cz_fix_caps(p$given %||% ""),
        lastName = cz_fix_caps(p$family)
      )
    } else if (!is.null(p$name) && nzchar(p$name)) {
      list(creatorType = type, name = p$name)
    }
  }
  c(
    Filter(Negate(is.null), lapply(msg$author %||% list(), one, type = "author")),
    Filter(Negate(is.null), lapply(msg$editor %||% list(), one, type = "editor"))
  )
}

# Name of the first institution, else `fallback`.
cz_first_institution <- function(msg, fallback) {
  nm <- cz_first(msg$institution)
  nm <- if (is.list(nm)) cz_first(nm$name) else NA_character_
  if (is.na(nm)) fallback else nm
}

# First element of a Crossref value that may be missing or an empty array.
cz_first <- function(x) {
  if (is.null(x) || !length(x)) NA_character_ else x[[1]]
}

cz_join <- function(x, sep = ", ") {
  x <- as.character(unlist(x))
  x <- x[!is.na(x) & nzchar(x)]
  if (length(x)) paste(unique(x), collapse = sep) else NA_character_
}

#' Map Crossref metadata onto Zotero's native item JSON
#'
#' @param msg Crossref `message`.
#' @param valid_fields Names of the fields valid for the item type (from Zotero's
#'   item template). Mapped fields not in this set are dropped and reported.
#' @param type The Zotero item type.
#' @return `list(item, dropped)`.
#' @noRd
cz_crossref_to_item <- function(msg, type, valid_fields, accessed = Sys.time()) {
  title <- cz_strip_markup(cz_first(msg$title))
  sub <- cz_strip_markup(cz_first(msg$subtitle))
  if (!is.na(sub) && nzchar(sub) && !is.na(title) && !grepl(sub, title, fixed = TRUE)) {
    title <- paste0(title, ": ", sub)
  }
  container <- cz_strip_markup(cz_first(msg$`container-title`))
  publisher <- cz_strip_markup(msg$publisher %||% NA_character_)
  event <- msg$event

  wanted <- list(
    title = title,
    abstractNote = cz_strip_markup(gsub("^\\s*<jats:title>[^<]*</jats:title>", "", msg$abstract %||% NA_character_, perl = TRUE), keep = character()),
    date = cz_crossref_date(msg),
    DOI = msg$DOI %||% NA_character_,
    url = if (!is.null(msg$DOI)) paste0("https://doi.org/", msg$DOI) else NA_character_,
    language = msg$language %||% NA_character_,
    libraryCatalog = "Crossref",
    accessDate = format(accessed, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  per_type <- switch(type,
    journalArticle = list(
      publicationTitle = container, volume = msg$volume, issue = msg$issue,
      pages = msg$page, ISSN = cz_join(msg$ISSN)
    ),
    book = list(
      publisher = publisher, place = msg$`publisher-location`,
      ISBN = cz_join(msg$ISBN), volume = msg$volume,
      edition = msg$`edition-number`, series = NA_character_
    ),
    bookSection = list(
      bookTitle = container, publisher = publisher, place = msg$`publisher-location`,
      pages = msg$page, ISBN = cz_join(msg$ISBN)
    ),
    conferencePaper = list(
      proceedingsTitle = container, publisher = publisher, pages = msg$page,
      ISBN = cz_join(msg$ISBN), ISSN = cz_join(msg$ISSN), volume = msg$volume,
      conferenceName = event$name, place = event$location
    ),
    preprint = list(repository = cz_first_institution(msg, publisher)),
    thesis = list(university = cz_first_institution(msg, publisher)),
    report = list(institution = cz_first_institution(msg, publisher)),
    dataset = list(repository = publisher),
    document = list(publisher = publisher)
  )
  wanted <- c(wanted, per_type)

  item <- list(itemType = type)
  dropped <- character()
  for (nm in names(wanted)) {
    v <- wanted[[nm]]
    if (is.null(v) || length(v) != 1 || is.na(v) || !nzchar(as.character(v))) next
    if (nm %in% valid_fields) {
      item[[nm]] <- as.character(v)
    } else {
      dropped <- c(dropped, nm)
    }
  }
  creators <- cz_crossref_creators(msg)
  if (length(creators)) item$creators <- creators
  list(item = item, dropped = dropped)
}
