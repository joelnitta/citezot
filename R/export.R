# BibLaTeX export of selected items, using Zotero's own exporter.
#
# Zotero's export uses an item's pinned citation key as the entry key, but it
# returns entries in an order unrelated to the request, so entries are matched
# to items by key, never by position. An item whose exported key differs from
# the key we want (e.g. one pinned only via a `Citation Key:` line in Extra) is
# re-requested on its own and its entry key rewritten.

# Split BibLaTeX text into entries. Returns a named character vector: names are
# entry keys, values the full entry text.
cz_split_bib <- function(txt) {
  lines <- strsplit(txt, "\r?\n")[[1]]
  starts <- grep("^@[A-Za-z]+\\s*\\{", lines)
  if (!length(starts)) {
    return(stats::setNames(character(0), character(0)))
  }
  ends <- c(starts[-1] - 1, length(lines))
  entries <- mapply(
    function(a, b) {
      paste(
        sub("\\s+$", "", lines[a:b]),
        collapse = "\n"
      ) |> sub(pattern = "\\s+$", replacement = "")
    },
    starts, ends
  )
  keys <- sub("^@[A-Za-z]+\\s*\\{([^,]*),.*$", "\\1", lines[starts])
  stats::setNames(entries, keys)
}

# Zotero fields may hold HTML-ish markup (`<i>`, `<b>`, `<sub>`, `<sup>`,
# small caps, `<span class="nocase">`). Citeproc understands it in CSL, but
# pandoc's BibLaTeX reader does not, so it would show up literally. Turn the
# tags into the LaTeX commands the reader does understand. Zotero's exporter
# converts `<i>` and `<sub>` itself but leaves the other tags escaped, as
# `{\textless}span class="nocase"{\textgreater}`. Tags may arrive raw or
# escaped (`{\textless}` or `\textless{}`), in any case, with single or
# double quotes. Every opening tag becomes a `{`-group and every closing tag a
# `}`, so braces stay balanced even for spans we do not recognize.
cz_html_to_latex <- function(entry) {
  lt <- "(?:<|\\{\\\\textless\\}|\\\\textless(?:\\{\\})?)\\s*"
  gt <- "(?:>|\\{\\\\textgreater\\}|\\\\textgreater(?:\\{\\})?)"
  tag <- function(body) paste0("(?i)", lt, body, "\\s*", gt)
  q <- "[\"']"
  span_attr <- function(re) {
    tag(paste0("span\\b[^<>\\\\]*?", re, "[^<>\\\\]*?"))
  }
  simple <- function(names, cmd) {
    list(
      c(tag(paste0("(?:", names, ")")), paste0("\\\\", cmd, "{")),
      c(tag(paste0("/(?:", names, ")")), "}")
    )
  }
  rules <- c(
    list(
      c(span_attr(paste0("class\\s*=\\s*", q, "[^\"']*\\bnocase\\b")), "{"),
      c(span_attr("font-variant\\s*:\\s*small-caps"), "\\\\textsc{"),
      c(span_attr("font-style\\s*:\\s*italic"), "\\\\emph{"),
      c(span_attr("font-weight\\s*:\\s*bold"), "\\\\textbf{"),
      c(tag("span\\b[^<>\\\\]*?"), "{"),
      # tags with no LaTeX counterpart are dropped, as are empty `<sup/>`
      c(tag("/?(?:p|br|div)\\b[^<>\\\\]*?/?"), ""),
      c(tag("[a-z]+\\b[^<>\\\\]*?/"), ""),
      c(tag("/span"), "}")
    ),
    simple("i|em", "emph"),
    simple("b|strong", "textbf"),
    simple("sub", "textsubscript"),
    simple("sup", "textsuperscript"),
    simple("sc", "textsc"),
    simple("u", "underline"),
    simple("tt|code", "texttt")
  )
  for (r in rules) entry <- gsub(r[1], r[2], entry, perl = TRUE)
  # Zotero cuts `shorttitle` at the first colon, which can split a tag such as
  # `font-variant:small-caps` in two. Such a fragment cannot be repaired; the
  # field is optional, so drop the whole line.
  broken <- "(?m)^[ \\t]*shorttitle\\s*=[^\\n]*(?:\\\\textless|<)[^\\n]*\\n?"
  gsub(broken, "", entry, perl = TRUE)
}

# Replace the entry key of a single BibLaTeX entry.
cz_set_bib_key <- function(entry, key) {
  head_end <- regexpr(",", entry, fixed = TRUE)
  open <- regexpr("{", entry, fixed = TRUE)
  paste0(substr(entry, 1, open), key, substr(entry, head_end, nchar(entry)))
}

# One request per batch of at most 50 item keys (Zotero's limit for `itemKey`).
cz_bib_requests <- function(auth, ids) {
  chunks <- split(ids, ceiling(seq_along(ids) / 50))
  lapply(unname(chunks), function(ch) {
    cz_request(auth, "items") |>
      httr2::req_url_query(
        itemKey = paste(ch, collapse = ","),
        format = "biblatex",
        limit = 50
      ) |>
      httr2::req_throttle(rate = 5)
  })
}

cz_bib_text <- function(resp) {
  if (httr2::resp_has_body(resp)) {
    httr2::resp_body_string(resp, encoding = "UTF-8")
  } else {
    ""
  }
}

#' Export items as BibLaTeX entries keyed by their pinned citekeys
#'
#' @param auth Credentials.
#' @param ids Zotero item keys (not citekeys), e.g. `"Q62TD7I9"`.
#' @param keys The citekey wanted for each item, same length as `ids`.
#' @return Character vector of entries, sorted by key.
#' @noRd
cz_export_bib <- function(auth, ids, keys) {
  stopifnot(length(ids) == length(keys))
  if (!length(ids)) {
    return(character(0))
  }
  reqs <- cz_bib_requests(auth, ids)
  resps <- if (length(reqs) == 1) {
    list(cz_perform(reqs[[1]]))
  } else {
    cz_perform_parallel(reqs)
  }
  got <- unlist(lapply(resps, function(r) cz_split_bib(cz_bib_text(r))))

  out <- character(length(ids))
  for (i in seq_along(ids)) {
    hit <- got[names(got) == keys[i]]
    if (length(hit)) {
      out[i] <- hit[[1]]
      next
    }
    # exported under a different key: fetch this item alone and rewrite the key
    single <- cz_split_bib(cz_bib_text(cz_perform(cz_bib_requests(
      auth,
      ids[i]
    )[[1]])))
    if (length(single) != 1) {
      cli::cli_abort(c(
        paste0(
          "Zotero did not return a BibLaTeX entry for item {ids[i]} (citekey ",
          "{.val {keys[i]}})."
        ),
        "i" = "Nothing was written."
      ))
    }
    out[i] <- cz_set_bib_key(single[[1]], keys[i])
  }
  out <- vapply(out, cz_html_to_latex, character(1), USE.NAMES = FALSE)
  out[order(keys, method = "radix")]
}
