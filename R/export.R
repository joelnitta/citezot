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

# CSL-YAML counterpart of `cz_html_to_latex()`. Pandoc reads the strings of a
# YAML bibliography as markdown (unlike CSL-JSON, where it understands the
# HTML-ish markup itself), so `<i>` would become raw HTML, which the Typst and
# docx writers drop. Turn the tags into Pandoc markdown, walking the tags in
# order with a stack so every closing tag gets the closer of its opener.
# Unknown tags are dropped and their text kept. Text outside tags is left as
# it is.
cz_html_to_markdown <- function(x) {
  if (!is.character(x)) {
    return(x)
  }
  vapply(x, cz_html_to_markdown1, character(1), USE.NAMES = FALSE)
}

cz_html_to_markdown1 <- function(s) {
  if (is.na(s) || !grepl("<", s, fixed = TRUE)) {
    return(s)
  }
  tag_re <- "(?i)</?[a-z][a-z0-9]*\\b[^<>]*?/?>"
  pos <- gregexpr(tag_re, s, perl = TRUE)[[1]]
  if (pos[1] == -1) {
    return(s)
  }
  tags <- regmatches(s, list(pos))[[1]]
  text <- regmatches(s, list(pos), invert = TRUE)[[1]]
  stack <- character()
  out <- text[1]
  for (i in seq_along(tags)) {
    tg <- tags[i]
    name <- tolower(sub("^</?([A-Za-z][A-Za-z0-9]*).*$", "\\1", tg))
    closing <- startsWith(tg, "</")
    selfclosed <- grepl("/>$", tg)
    if (closing) {
      # a closer only for a tag we opened; stray closers are dropped
      if (length(stack)) {
        out <- paste0(out, stack[length(stack)])
        stack <- stack[-length(stack)]
      }
    } else if (!selfclosed && !name %in% c("br", "p", "div")) {
      m <- cz_md_markers(name, tg)
      out <- paste0(out, m[1])
      stack <- c(stack, m[2])
    }
    out <- paste0(out, text[i + 1])
  }
  out
}

# Opening and closing markdown for one HTML opening tag.
cz_md_markers <- function(name, tag) {
  has <- function(re) grepl(re, tag, ignore.case = TRUE, perl = TRUE)
  switch(name,
    i = ,
    em = c("*", "*"),
    b = ,
    strong = c("**", "**"),
    sub = c("~", "~"),
    sup = c("^", "^"),
    sc = c("[", "]{.smallcaps}"),
    span = if (has("\\bnocase\\b")) {
      c("[", "]{.nocase}")
    } else if (has("font-variant\\s*:\\s*small-caps")) {
      c("[", "]{.smallcaps}")
    } else if (has("font-style\\s*:\\s*italic")) {
      c("*", "*")
    } else if (has("font-weight\\s*:\\s*bold")) {
      c("**", "**")
    } else {
      c("", "")
    },
    c("", "")
  )
}

# Apply `cz_html_to_markdown()` to every string in a CSL item, except the
# fields where `<` or markup would be wrong (links, ids).
cz_item_html_to_markdown <- function(x, name = "") {
  skip <- c("URL", "DOI", "id", "citation-key", "ISBN", "ISSN", "PMID")
  if (is.list(x)) {
    nms <- names(x)
    for (j in seq_along(x)) {
      nm <- if (is.null(nms) || !nzchar(nms[j])) name else nms[j]
      x[[j]] <- cz_item_html_to_markdown(x[[j]], nm)
    }
    x
  } else if (name %in% skip) {
    x
  } else {
    cz_html_to_markdown(x)
  }
}
