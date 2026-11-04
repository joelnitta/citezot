# Citation-key generation from a Better BibTeX-style formula, e.g.
#   auth.lower + year + shorttitle(1).lower
# Only a documented subset of the formula language is supported; anything else
# is an error that says what is supported, never a silently different key.

# Words skipped by shorttitle(), as in Better BibTeX's default list.
cz_skip_words <- c(
  "a", "ab", "aboard", "about", "above", "across", "after", "against", "al",
  "along", "amid", "among", "an", "and", "anti", "around", "as", "at", "before",
  "behind", "below", "beneath", "beside", "besides", "between", "beyond", "but",
  "by", "d", "da", "das", "de", "del", "dell", "dello", "dei", "degli", "della",
  "delle", "dem", "den", "der", "des", "det", "die", "dos", "du", "ein", "eine",
  "einem", "einen", "einer", "eines", "el", "en", "et", "for", "from", "gli",
  "i", "il", "in", "inside", "into", "is", "l", "la", "las", "le", "les", "los",
  "near", "nor", "of", "off", "on", "onto", "or", "over", "per", "plus", "round",
  "s", "sans", "since", "than", "the", "through", "to", "toward", "towards",
  "un", "una", "une", "unter", "up", "upon", "versus", "via", "vom", "von",
  "vor", "with", "within", "without", "yet", "zu", "zum"
)

cz_key_functions <- c("auth", "year", "shorttitle", "title")
cz_key_filters <- c("lower", "upper", "fold", "transliterate", "clean", "condense", "nopunct")

# The Better BibTeX default pattern, used when the user gives no formula.
cz_default_key_format <- "auth.lower + shorttitle(3,3) + year"

cz_fold <- function(x) {
  x <- chartr(cz_fold_from, cz_fold_to, x)
  for (k in names(cz_fold_multi)) x <- gsub(k, cz_fold_multi[[k]], x, fixed = TRUE)
  x
}

# Split on top-level '+' (not inside quotes or parentheses).
cz_split_plus <- function(formula) {
  chars <- strsplit(formula, "")[[1]]
  parts <- character()
  cur <- character()
  depth <- 0
  quote <- ""
  for (ch in chars) {
    if (nzchar(quote)) {
      if (ch == quote) quote <- ""
    } else if (ch %in% c("'", "\"")) {
      quote <- ch
    } else if (ch == "(") {
      depth <- depth + 1
    } else if (ch == ")") {
      depth <- depth - 1
    } else if (ch == "+" && depth == 0) {
      parts <- c(parts, paste(cur, collapse = ""))
      cur <- character()
      next
    }
    cur <- c(cur, ch)
  }
  c(parts, paste(cur, collapse = ""))
}

cz_unsupported_formula <- function(what, formula) {
  cli::cli_abort(c(
    "Unsupported in the key formula {.code {formula}}: {what}.",
    "i" = "Supported functions: {.code {cz_key_functions}}; filters: {.code {cz_key_filters}}; joined with {.code +}; quoted text is kept as is.",
    "i" = "Use {.code cz_pin_key()} to set a key by hand, or ask Better BibTeX for the key if Zotero is running."
  ), call = NULL)
}

#' Parse a key formula into terms
#' @noRd
cz_parse_key_format <- function(formula) {
  rlang::check_string(formula, arg = "formula")
  if (grepl("\\|\\||&&|;|\\?|\\[|\\]", formula)) {
    cz_unsupported_formula("alternatives (`||`), conditions, `;` or the old `[...]` syntax", formula)
  }
  lapply(trimws(cz_split_plus(formula)), function(term) {
    if (!nzchar(term)) cz_unsupported_formula("an empty term", formula)
    lit <- regmatches(term, regexec("^(['\"])(.*)\\1$", term))[[1]]
    if (length(lit)) {
      return(list(kind = "lit", value = lit[3]))
    }
    m <- regmatches(term, regexec("^([A-Za-z][A-Za-z0-9]*)(?:\\(([^)]*)\\))?((?:\\.[A-Za-z]+)*)$", term, perl = TRUE))[[1]]
    if (!length(m)) cz_unsupported_formula(sprintf("the term `%s`", term), formula)
    fn <- m[2]
    if (!fn %in% cz_key_functions) {
      cz_unsupported_formula(sprintf("the function `%s`", fn), formula)
    }
    filters <- if (nzchar(m[4])) strsplit(sub("^\\.", "", m[4]), ".", fixed = TRUE)[[1]] else character()
    filters <- tolower(filters)
    bad <- setdiff(filters, cz_key_filters)
    if (length(bad)) cz_unsupported_formula(sprintf("the filter `%s`", bad[1]), formula)
    args <- if (nzchar(m[3])) suppressWarnings(as.integer(trimws(strsplit(m[3], ",")[[1]]))) else integer()
    if (anyNA(args)) cz_unsupported_formula(sprintf("the arguments of `%s`", fn), formula)
    list(kind = "fn", name = fn, args = args, filters = filters)
  })
}

# Bibliographic fields the formula functions need, from either a Zotero native
# item (or the payload built by cz_add()) or a CSL-JSON item.
cz_key_fields <- function(item) {
  if (!is.null(item$data)) item <- item$data
  year <- function(x) {
    m <- regmatches(x, regexpr("(?<![0-9])[0-9]{4}(?![0-9])", x, perl = TRUE))
    if (length(m)) m else ""
  }
  if (!is.null(item$itemType) || !is.null(item$creators)) {
    cr <- item$creators %||% list()
    types <- vapply(cr, function(p) p$creatorType %||% "", character(1))
    pick <- cr[types == "author"]
    if (!length(pick)) pick <- cr[types == "editor"]
    authors <- vapply(pick, function(p) p$lastName %||% p$name %||% "", character(1))
    return(list(authors = authors, title = item$title %||% "", year = year(item$date %||% "")))
  }
  people <- item$author
  if (is.null(people) || !length(people)) people <- item$editor
  authors <- vapply(people %||% list(), function(p) p$family %||% p$literal %||% "", character(1))
  y <- tryCatch(as.character(item$issued$`date-parts`[[1]][[1]]), error = function(e) "")
  list(authors = authors, title = cz_chr1(item$title) %||% "", year = if (length(y)) y else "")
}

# Words of a title, as Better BibTeX sees them: HTML tags removed, cut at the
# first sentence break, split on whitespace, "/" and en/em dashes. Inside a
# word, hyphens and other punctuation are dropped ("early-diverging" is one
# word, "earlydiverging").
cz_title_words <- function(title, main_only = TRUE) {
  if (is.na(title)) title <- ""
  title <- gsub("<[^>]*>", "", title)
  if (main_only) {
    main <- sub("^(.*?)([:?!]|\\.(\\s|$)).*$", "\\1", title, perl = TRUE)
    if (nzchar(trimws(main))) title <- main
  }
  w <- strsplit(trimws(title), "[[:space:]\u00a0/\u2013\u2014]+")[[1]]
  w <- gsub("[^[:alnum:]]", "", cz_fold(w))
  w[nzchar(w)]
}

cz_apply_filter <- function(x, f) {
  switch(f,
    lower = tolower(x),
    upper = toupper(x),
    fold = , transliterate = cz_fold(x),
    clean = gsub("[^[:alnum:]]", "", cz_fold(x)),
    condense = gsub("[[:space:]]+", "", x),
    nopunct = gsub("[[:punct:]]", "", x)
  )
}

cz_eval_term <- function(term, fields) {
  if (term$kind == "lit") {
    return(term$value)
  }
  out <- switch(term$name,
    auth = if (length(fields$authors)) {
      # Unicode hyphens (U+2010-2012) count as "-" in names
      gsub("[[:space:]]+", "", gsub("[\u2010\u2011\u2012]", "-", fields$authors[1]))
    } else {
      ""
    },
    year = fields$year,
    title = paste(cz_title_words(fields$title, main_only = FALSE), collapse = ""),
    shorttitle = {
      n <- if (length(term$args) >= 1) term$args[1] else 3L
      m <- if (length(term$args) >= 2) term$args[2] else 0L
      w <- cz_title_words(fields$title)
      w <- utils::head(w[!tolower(w) %in% cz_skip_words], n)
      if (m > 0 && length(w)) {
        i <- seq_len(min(m, length(w)))
        w[i] <- paste0(toupper(substring(w[i], 1, 1)), substring(w[i], 2))
      }
      paste(w, collapse = "")
    }
  )
  for (f in term$filters) out <- cz_apply_filter(out, f)
  out
}

# Make a string safe as a pandoc/BibTeX key: ASCII-fold, drop the rest.
cz_sanitize_key <- function(x) {
  x <- cz_fold(x)
  x <- gsub("[^A-Za-z0-9_:.+-]", "", x)
  gsub("[:.+-]+$", "", x)
}

# a, b, ..., z, aa, ab, ...
cz_postfix <- function(i) {
  out <- character()
  while (i > 0) {
    i <- i - 1
    out <- c(letters[i %% 26 + 1], out)
    i <- i %/% 26
  }
  paste(out, collapse = "")
}

#' Suggest a citekey for an item
#'
#' Builds a key from a Better BibTeX-style formula, e.g.
#' `"auth.lower + year + shorttitle(1).lower"`. If the key is already taken, a
#' letter (`a`, `b`, ...) is appended, as Better BibTeX does.
#'
#' The formula is, in order of preference, the `formula` argument, then the one
#' found by [cz_key_format()] (the `citezot.key_format` option, your Zotero
#' profile's Better BibTeX pattern, or Better BibTeX's default
#' `auth.lower + shorttitle(3,3) + year`). Supported functions are `auth`
#' (first author's last name), `year`, `shorttitle(n, m)` (first `n` words of
#' the title, skipping short function words, with the first `m` capitalised),
#' and `title`; filters are `lower`, `upper`, `fold`, `transliterate`, `clean`,
#' `condense` and `nopunct`; terms are joined with `+` and quoted text is kept
#' as is. Anything else is an error rather than a silently different key. The
#' result is ASCII and safe to cite in pandoc.
#'
#' @param item A Zotero native item (as from [cz_get_item()], or the payload
#'   [cz_add()] builds) or a CSL-JSON item.
#' @param formula The key formula. See Details.
#' @param existing Keys already in use, so the result can be made unique.
#'
#' @return A single string.
#' @export
#' @examples
#' item <- list(
#'   itemType = "journalArticle",
#'   title = "A taxonomic revision of Hymenophyllaceae",
#'   date = "2006",
#'   creators = list(list(creatorType = "author", firstName = "A", lastName = "Ebihara"))
#' )
#' cz_suggest_key(item, "auth.lower + year + shorttitle(1).lower")
#' cz_suggest_key(item, existing = "ebihara2006taxonomic",
#'                formula = "auth.lower + year + shorttitle(1).lower")
cz_suggest_key <- function(item, formula = NULL, existing = character()) {
  if (is.null(formula)) {
    fmt <- cz_key_format()
    cz_announce_format(fmt)
    formula <- fmt$formula
  }
  terms <- cz_parse_key_format(formula)
  fields <- cz_key_fields(item)
  base <- cz_sanitize_key(paste(vapply(terms, cz_eval_term, character(1), fields = fields), collapse = ""))
  if (!nzchar(base)) {
    cli::cli_abort(c(
      "The formula {.code {formula}} gave an empty key for this item.",
      "i" = "The item may lack the author, date or title it uses."
    ))
  }
  key <- base
  i <- 0
  while (key %in% existing) {
    i <- i + 1
    key <- paste0(base, cz_postfix(i))
  }
  key
}

# --- finding the user's formula ----------------------------------------------

# Candidate Zotero profile folders (each holds a prefs.js).
cz_zotero_profile_dirs <- function() {
  opt <- getOption("citezot.zotero_profile")
  if (!is.null(opt)) {
    return(if (grepl("prefs\\.js$", opt)) dirname(opt) else opt)
  }
  home <- path.expand("~")
  roots <- c(
    file.path(home, "Library", "Application Support", "Zotero", "Profiles"),
    file.path(home, ".zotero", "zotero"),
    file.path(Sys.getenv("APPDATA"), "Zotero", "Zotero", "Profiles")
  )
  roots <- roots[nzchar(roots) & dir.exists(roots)]
  unlist(lapply(roots, list.dirs, recursive = FALSE))
}

#' The Better BibTeX citation-key pattern from the Zotero profile
#'
#' Reads *only* the single `better-bibtex.citekeyFormat` line from the
#' profile's `prefs.js`; nothing else in that file is looked at or kept. The
#' most recently modified profile that has the setting wins. Returns `NULL` if
#' Zotero or Better BibTeX settings are not found.
#' @noRd
cz_bbt_format_from_prefs <- function() {
  dirs <- cz_zotero_profile_dirs()
  files <- file.path(dirs, "prefs.js")
  files <- files[file.exists(files)]
  if (!length(files)) {
    return(NULL)
  }
  files <- files[order(file.mtime(files), decreasing = TRUE)]
  pattern <- "^user_pref\\(\"extensions\\.zotero\\.translators\\.better-bibtex\\.citekeyFormat\",\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\);"
  for (f in files) {
    lines <- readLines(f, warn = FALSE, encoding = "UTF-8")
    hit <- regmatches(lines, regexec(pattern, lines, perl = TRUE))
    hit <- Filter(length, hit)
    if (length(hit)) {
      return(gsub("\\\\(.)", "\\1", hit[[1]][2]))
    }
  }
  NULL
}

#' Which key formula citezot will use
#'
#' In order: `getOption("citezot.key_format")`; the Better BibTeX pattern in
#' your Zotero profile (see Details); Better BibTeX's default pattern.
#'
#' Detection of the Zotero profile reads one line of its `prefs.js` and only
#' happens when a key is generated, never at load. Set
#' `options(citezot.key_format = ...)` to choose a formula yourself and skip
#' the detection, and `options(citezot.zotero_profile = "<folder>")` if Zotero
#' keeps its profile somewhere unusual. The source in use is reported once per
#' session.
#'
#' @return A list with `formula` and `source` (`"option"`, `"zotero profile"`
#'   or `"default"`).
#' @export
#' @examples
#' options(citezot.key_format = "auth.lower + year")
#' cz_key_format()
cz_key_format <- function() {
  opt <- getOption("citezot.key_format")
  if (!is.null(opt)) {
    return(list(formula = opt, source = "option"))
  }
  prefs <- cz_bbt_format_from_prefs()
  if (!is.null(prefs)) {
    return(list(formula = prefs, source = "zotero profile"))
  }
  list(formula = cz_default_key_format, source = "default")
}

cz_announce_format <- function(fmt) {
  msg <- switch(fmt$source,
    option = NULL,
    "zotero profile" = "Citekey formula {.code {fmt$formula}} read from your Zotero profile (Better BibTeX).",
    default = "No citekey formula found; using Better BibTeX's default {.code {fmt$formula}}. Set {.code options(citezot.key_format = \"...\")} to choose your own."
  )
  if (!is.null(msg)) {
    cli::cli_inform(c(i = msg), .frequency = "once", .frequency_id = paste("citezot_format", fmt$source, fmt$formula))
  }
}
