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

# CSL-YAML counterpart of `cz_html_to_latex()`. Pandoc reads every string of a
# YAML bibliography as markdown (in CSL-JSON it reads the HTML-ish markup
# itself), so `<i>` would become raw HTML, which the Typst and docx writers
# drop, and a literal `*`, `_`, `$`, `[` or `<` would be read as markup. So
# the tags Zotero uses become Pandoc markdown (`<i>x</i>` -> `*x*`), block
# tags (`<p>`, `<br>`, headings) become a space, other known tags are dropped
# with their text kept, and all other text is escaped so it reaches the output
# as written. Anything that only looks like a tag (`a<b and c>d`) is text.
# `tags = FALSE` only escapes (for links and identifiers).
cz_html_to_markdown <- function(x, tags = TRUE) {
  if (!is.character(x)) {
    return(x)
  }
  vapply(x, cz_html_to_markdown1, character(1),
    tags = tags, USE.NAMES = FALSE
  )
}

# Known tags only, with quoted attributes; groups: closing slash, name,
# attributes, self-closing slash.
cz_md_tag_re <- paste0(
  "(?i)<(/?)",
  "((?:jats|mml):[a-z][a-z0-9-]*|h[1-6]|i|em|b|strong|sub|sup|sc|span|u|",
  "p|br|div|hr|a)\\b",
  "((?:\\s+[a-z_:][-a-z0-9_:.]*\\s*=\\s*(?:\"[^\"]*\"|'[^']*'))*)",
  "\\s*(/?)>"
)

# Backslash-escape the characters Pandoc's markdown would read as markup.
# Autolinks (`<https://...>`) are kept: Pandoc reads them as links, and a
# backslash inside one would end up in the URL.
cz_md_escape <- function(s) {
  gsub(
    "<(?:https?|ftp)://[^\\s<>]+>(*SKIP)(*FAIL)|([\\\\`*_\\[\\]~^$<])",
    "\\\\\\1", s,
    perl = TRUE
  )
}

# The tags are walked in order with a stack of open runs. `st$out` is the
# markdown so far, `st$stack` the open runs (tag name, markers, where the run
# starts in `out`), `st$last` the run closed last (to merge `<i>a</i><i>b</i>`
# into `*ab*`, as `*a**b*` does not parse), `st$gap` a pending block break.
cz_html_to_markdown1 <- function(s, tags = TRUE) {
  if (is.na(s)) {
    return(NA_character_)
  }
  pos <- if (tags) gregexpr(cz_md_tag_re, s, perl = TRUE)[[1]] else -1
  if (pos[1] == -1) {
    return(cz_md_escape(s))
  }
  found <- regmatches(s, list(pos))[[1]]
  text <- cz_md_escape(regmatches(s, list(pos), invert = TRUE)[[1]])
  st <- list(out = "", stack = list(), last = NULL, gap = FALSE)
  st <- cz_md_text(st, text[1])
  for (i in seq_along(found)) {
    st <- cz_md_tag(st, found[i])
    st <- cz_md_text(st, text[i + 1])
  }
  # unclosed tags are closed at the end, so markers always balance
  while (length(st$stack)) st <- cz_md_close(st)
  st$out
}

cz_md_text <- function(st, txt) {
  if (!nzchar(txt)) {
    return(st)
  }
  spaced <- grepl("\\s$", st$out, perl = TRUE) ||
    grepl("^\\s", txt, perl = TRUE)
  if (st$gap && nzchar(st$out) && !spaced) {
    txt <- paste0(" ", txt)
  }
  st$gap <- FALSE
  # Pandoc's sub- and superscripts cannot hold a bare space
  opens <- vapply(st$stack, function(f) f$m[1], "")
  if (any(opens %in% c("~", "^"))) {
    txt <- gsub("\\s", "\\\\ ", txt, perl = TRUE)
  }
  st$out <- paste0(st$out, txt)
  st
}

cz_md_tag <- function(st, tag) {
  m <- regmatches(tag, regexec(cz_md_tag_re, tag, perl = TRUE))[[1]]
  name <- tolower(m[3])
  markers <- cz_md_markers(name, tag)
  if (is.null(markers)) {
    st$gap <- TRUE
    return(st)
  }
  if (nzchar(m[5])) {
    return(st)
  }
  if (!nzchar(m[2])) {
    return(cz_md_open(st, name, markers))
  }
  # a closer closes its own opener and any runs left open inside it; a closer
  # with no opener is dropped
  hit <- which(vapply(st$stack, function(f) f$name, "") == name)
  if (length(hit)) {
    while (length(st$stack) >= max(hit)) st <- cz_md_close(st)
  }
  st
}

cz_md_open <- function(st, name, m) {
  start <- nchar(st$out)
  last <- st$last
  adjacent <- !is.null(last) && identical(last$m, m) && last$end == start
  if (adjacent && m[1] %in% c("*", "**")) {
    st$out <- paste0(
      substr(st$out, 1, last$start),
      substr(st$out, last$start + nchar(m[1]) + 1, start - nchar(m[2]))
    )
    start <- last$start
  }
  st$stack <- c(st$stack, list(list(name = name, m = m, start = start)))
  st$last <- NULL
  st
}

cz_md_close <- function(st) {
  n <- length(st$stack)
  f <- st$stack[[n]]
  st$stack <- st$stack[-n]
  st$last <- NULL
  m <- f$m
  body <- substr(st$out, f$start + 1, nchar(st$out))
  if (!nzchar(m[1]) || !grepl("\\S", body, perl = TRUE)) {
    return(st)
  }
  before <- substr(st$out, 1, f$start)
  lead <- trail <- ""
  if (m[1] %in% c("*", "**")) {
    # `*Aster *(Asteraceae)`: keep the spaces outside the emphasis
    lead <- regmatches(body, regexpr("^\\s*", body, perl = TRUE))
    trail <- regmatches(body, regexpr("\\s*$", body, perl = TRUE))
    body <- substr(body, nchar(lead) + 1, nchar(body) - nchar(trail))
  }
  before <- paste0(before, lead)
  st$out <- paste0(before, m[1], body, m[2])
  st$last <- list(m = m, start = nchar(before), end = nchar(st$out))
  st$out <- paste0(st$out, trail)
  st
}

# Opening and closing markdown for one HTML opening tag; NULL for a block tag.
cz_md_markers <- function(name, tag) {
  has <- function(re) grepl(re, tag, ignore.case = TRUE, perl = TRUE)
  switch(name,
    i = ,
    em = ,
    `jats:italic` = c("*", "*"),
    b = ,
    strong = ,
    `jats:bold` = c("**", "**"),
    sub = ,
    `jats:sub` = c("~", "~"),
    sup = ,
    `jats:sup` = c("^", "^"),
    sc = ,
    `jats:sc` = c("[", "]{.smallcaps}"),
    u = ,
    `jats:underline` = c("[", "]{.underline}"),
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
    p = ,
    br = ,
    div = ,
    hr = ,
    `jats:p` = ,
    `jats:title` = ,
    `jats:sec` = NULL,
    if (grepl("^h[1-6]$", name)) NULL else c("", "")
  )
}

# Apply `cz_html_to_markdown()` to every string in a CSL item. `id` and
# `citation-key` are left alone; links and identifiers are only escaped.
cz_item_html_to_markdown <- function(item) {
  # Zotero cuts a short title at its first colon, which can split a tag such
  # as `font-variant:small-caps`. Such a fragment cannot be repaired; the
  # field is optional, so drop it (as `cz_html_to_latex()` drops
  # `shorttitle`).
  for (f in c("title-short", "shortTitle")) {
    if (any(grepl("(?i)<\\s*/?[a-z][^<>]*$", item[[f]], perl = TRUE))) {
      item[[f]] <- NULL
    }
  }
  cz_md_walk(item)
}

cz_md_walk <- function(x, name = "") {
  if (is.list(x)) {
    nms <- names(x) %||% rep("", length(x))
    for (j in seq_along(x)) {
      nm <- if (is.na(nms[j]) || !nzchar(nms[j])) name else nms[j]
      x[j] <- list(cz_md_walk(x[[j]], nm))
    }
    return(x)
  }
  if (name %in% c("id", "citation-key")) {
    return(x)
  }
  links <- c("URL", "DOI", "ISBN", "ISSN", "PMID", "PMCID")
  cz_html_to_markdown(x, tags = !name %in% links)
}
