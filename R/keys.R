#' Extract pandoc citation keys used in a qmd/Rmd file
#'
#' Strips fenced code blocks first (so `@` in R code is never mistaken for a
#' citation), finds `@key` tokens, then drops Quarto cross-references
#' (`@fig-x`, `@tbl-x`, `@eq-x`, ...), which use the same syntax but are not
#' bibliography citations.
#'
#' @param path Path to a .qmd or .Rmd file.
#' @param crossref_prefixes Cross-reference prefixes to drop (without the
#'   trailing hyphen).
#'
#' @return Sorted character vector of unique citation keys (no leading `@`).
#' @export
cz_qmd_keys <- function(
  path,
  crossref_prefixes = c(
    "fig", "tbl", "eq", "sec", "lst", "thm", "lem", "cor", "prp", "cnj",
    "def", "exm", "exr", "rem", "sol", "nte"
  )
) {
  lines <- readLines(path, warn = FALSE)
  in_code <- FALSE
  kept <- character(0)
  for (ln in lines) {
    if (grepl("^\\s*```", ln)) {
      in_code <- !in_code
      next
    }
    if (!in_code) kept <- c(kept, ln)
  }
  txt <- paste(kept, collapse = "\n")
  # @ + alphanumerics/hyphens, optionally with embedded periods (e.g.
  # WatkinsJr.2012); not preceded by a word character (so emails are ignored);
  # a period is only consumed when followed by more alnum/hyphen text, so a
  # sentence-ending "@Foo2020." does not capture the period.
  m <- gregexpr(
    "(?<![[:alnum:]_])@[[:alnum:]-]+(?:\\.[[:alnum:]-]+)*",
    txt,
    perl = TRUE
  )
  keys <- sub("^@", "", regmatches(txt, m)[[1]])
  prefix_re <- paste0("^(", paste(crossref_prefixes, collapse = "|"), ")-")
  keys <- keys[!grepl(prefix_re, keys, ignore.case = TRUE)]
  sort(unique(keys), method = "radix")
}

#' Extract bare (no `@`) citekey-shaped tokens from a text/data file
#'
#' For files that reference sources informally (e.g. a CSV "comments" column
#' saying "defined in Dubuisson2013a"). Matches an author-shaped run of letters
#' (hyphens allowed) immediately followed by a 19xx/20xx year and an optional
#' lowercase disambiguator, e.g. `Ebihara2006`, `Boucheron-Dubuisson2024`.
#' Deliberately conservative: `Ebihara 2006` or `Hsu7949` do not match.
#'
#' @param path Path to the file to scan.
#'
#' @return Sorted character vector of unique citekey-shaped tokens.
#' @export
cz_bare_keys <- function(path) {
  txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
  m <- gregexpr(
    "(?<![[:alnum:]])[A-Za-z][A-Za-z-]*(19|20)[0-9]{2}[a-z]*(?![[:alnum:]])",
    txt,
    perl = TRUE
  )
  sort(unique(regmatches(txt, m)[[1]]), method = "radix")
}

#' Pull a pinned citekey out of a CSL item's `note` (Extra) field
#'
#' Zotero's CSL-JSON export puts the Extra field verbatim into `note`; an
#' older pinning style writes a `Citation Key: <key>` line there. See
#' [cz_item_key()], which also checks the native field.
#'
#' @param note A CSL item's `note` field (character or `NULL`).
#'
#' @return The citekey, or `NA_character_`.
#' @keywords internal
cz_note_key <- function(note) {
  if (is.null(note) || !nzchar(note)) {
    return(NA_character_)
  }
  m <- regmatches(
    note,
    regexpr("(?m)^Citation Key:[ \t]*(\\S+)", note, perl = TRUE)
  )
  if (length(m) == 0) {
    return(NA_character_)
  }
  sub("^Citation Key:[ \t]*", "", m)
}

#' Get a CSL item's pinned citekey, however it is pinned
#'
#' Checks the native `citation-key` property first, then falls back to a
#' `Citation Key:` line in `note`.
#'
#' @param item A single CSL-JSON item (a list).
#'
#' @return The citekey, or `NA_character_`.
#' @export
cz_item_key <- function(item) {
  native <- item[["citation-key"]]
  if (!is.null(native) && nzchar(native)) {
    return(native)
  }
  cz_note_key(item$note)
}

#' Drop the `Citation Key:` line from a note, keeping other content
#'
#' @param note A note string or `NULL`.
#'
#' @return The cleaned note, or `NULL` if nothing is left.
#' @keywords internal
cz_strip_key_line <- function(note) {
  if (is.null(note)) {
    return(NULL)
  }
  lines <- strsplit(note, "\n")[[1]]
  lines <- lines[!grepl("^Citation Key:[ \t]*\\S+[ \t]*$", lines)]
  txt <- trimws(paste(trimws(lines), collapse = "\n"))
  if (!nzchar(txt)) NULL else txt
}
