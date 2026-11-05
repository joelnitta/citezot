entry <- function(key, title = "T") {
  sprintf("@article{%s,\n\ttitle = {%s},\n\tdate = {2020},\n}\n", key, title)
}

entry_keys <- function(x) {
  sub(
    "(?s)^@article\\{([^,]*),.*$",
    "\\1",
    x,
    perl = TRUE
  )
}

test_that("cz_split_bib splits entries and names them by key", {
  txt <- paste0(entry("A2020", "One"), "\n", entry("Weiß2015", "Two"), "\n")
  x <- cz_split_bib(txt)
  expect_named(x, c("A2020", "Weiß2015"))
  expect_match(x[["A2020"]], "^@article\\{A2020,")
  expect_match(x[["A2020"]], "One")
  expect_no_match(x[["A2020"]], "Two")
  expect_identical(cz_split_bib(""), setNames(character(0), character(0)))
})

test_that("cz_set_bib_key rewrites only the key", {
  e <- "@article{zotero_generated_2020,\n\ttitle = {a, b {c}},\n}"
  expect_identical(
    cz_set_bib_key(e, "Mine2020"),
    "@article{Mine2020,\n\ttitle = {a, b {c}},\n}"
  )
})

# Mock the export endpoint. `bib` maps Zotero item key -> key Zotero will use
# in its export. Entries come back in reverse order, like the real API.
mock_export <- function(env, bib) {
  function(req) {
    env$reqs <- c(env$reqs, list(req))
    q <- httr2::url_parse(req$url)$query
    ids <- strsplit(q$itemKey, ",", fixed = TRUE)[[1]]
    stopifnot(q$format == "biblatex", length(ids) <= 50)
    txt <- paste(
      vapply(
        rev(ids),
        function(id) entry(bib[[id]], paste("Title of", id)),
        ""
      ),
      collapse = "\n"
    )
    httr2::response(
      headers = list(`Content-Type` = "application/x-bibtex"),
      body = charToRaw(enc2utf8(txt))
    )
  }
}

test_that("cz_export_bib matches entries by key, not position, and sorts", {
  env <- new.env()
  bib <- c(AAA = "Kent2002", BBB = "Weiß2015", CCC = "Ebihara2006")
  httr2::local_mocked_responses(mock_export(env, bib))
  out <- cz_export_bib(cz_auth("1", "k"), names(bib), unname(bib))
  expect_length(out, 3)
  expect_identical(entry_keys(out), c("Ebihara2006", "Kent2002", "Weiß2015"))
  expect_match(out[1], "Title of CCC") # Ebihara2006 is item CCC
  expect_length(env$reqs, 1)
})

test_that("cz_export_bib batches 50 items per request", {
  env <- new.env()
  ids <- sprintf("ID%03d", 1:120)
  bib <- setNames(sprintf("Key%03d", 1:120), ids)
  httr2::local_mocked_responses(mock_export(env, bib))
  out <- cz_export_bib(cz_auth("1", "k"), ids, unname(bib))
  expect_length(out, 120)
  expect_length(env$reqs, 3)
})

test_that("an entry exported under another key is re-fetched and rewritten", {
  env <- new.env()
  # item BBB was pinned only via Extra, so Zotero exports it under its own key
  bib <- c(AAA = "Kent2002", BBB = "zotero_made_up_2020")
  httr2::local_mocked_responses(mock_export(env, bib))
  out <- cz_export_bib(
    cz_auth("1", "k"),
    c("AAA", "BBB"),
    c("Kent2002", "Pinned2020")
  )
  expect_identical(entry_keys(out), c("Kent2002", "Pinned2020"))
  expect_match(out[2], "Title of BBB")
  expect_length(env$reqs, 2) # batch + one single-item retry
})

test_that("cz_export_bib errors if Zotero returns nothing for an item", {
  httr2::local_mocked_responses(function(req) httr2::response(body = raw()))
  expect_error(
    cz_export_bib(cz_auth("1", "k"), "AAA", "Kent2002"),
    "did not return a BibLaTeX entry"
  )
})

test_that("cz_html_to_latex converts every supported tag", {
  cases <- list(
    c("<i>x</i>", "\\emph{x}"),
    c("<em>x</em>", "\\emph{x}"),
    c("<b>x</b>", "\\textbf{x}"),
    c("<strong>x</strong>", "\\textbf{x}"),
    c("<sub>x</sub>", "\\textsubscript{x}"),
    c("<sup>x</sup>", "\\textsuperscript{x}"),
    c("<sc>x</sc>", "\\textsc{x}"),
    c("<u>x</u>", "\\underline{x}"),
    c("<code>x</code>", "\\texttt{x}"),
    c("<tt>x</tt>", "\\texttt{x}"),
    c('<span class="nocase">x</span>', "{x}"),
    c("<span class='nocase'>x</span>", "{x}"),
    c('<span class="nocase other">x</span>', "{x}"),
    c('<span style="font-variant:small-caps">x</span>', "\\textsc{x}"),
    c('<span style="font-variant: small-caps;">x</span>', "\\textsc{x}"),
    c('<span style="font-style:italic">x</span>', "\\emph{x}"),
    c('<span style="font-weight:bold">x</span>', "\\textbf{x}"),
    c('<span lang="la">x</span>', "{x}")
  )
  for (case in cases) {
    expect_identical(cz_html_to_latex(case[1]), case[2], info = case[1])
  }
})

test_that("cz_html_to_latex handles case, escaping, nesting and context", {
  f <- cz_html_to_latex
  expect_identical(f("<I>x</I> <SUB>2</SUB>"), "\\emph{x} \\textsubscript{2}")
  expect_identical(f("<i >x</i >"), "\\emph{x}")
  # escaped angle brackets, as a BibTeX exporter may emit them
  expect_identical(
    f("\\textless{}i\\textgreater{}x\\textless{}/i\\textgreater{}"),
    "\\emph{x}"
  )
  expect_identical(
    f(paste0(
      "\\textless{}span class=\"nocase\"\\textgreater{}x",
      "\\textless{}/span\\textgreater{}"
    )),
    "{x}"
  )
  # nesting and several tags in one field
  expect_identical(
    f('<span class="nocase"><i>Azolla</i> in H<sub>2</sub>O</span>'),
    "{\\emph{Azolla} in H\\textsubscript{2}O}"
  )
  expect_identical(
    f("<b><i>x</i></b>"),
    "\\textbf{\\emph{x}}"
  )
  # a whole entry: only the markup changes
  entry <- paste0(
    "@article{Key2020,\n\ttitle = {<i>A</i> and <b>B</b>},\n",
    "\tauthor = {Doe, Jane},\n\tdate = {2020},\n}"
  )
  expect_identical(
    f(entry),
    paste0(
      "@article{Key2020,\n\ttitle = {\\emph{A} and \\textbf{B}},\n",
      "\tauthor = {Doe, Jane},\n\tdate = {2020},\n}"
    )
  )
})

test_that("cz_html_to_latex handles Zotero's escaped export forms", {
  f <- cz_html_to_latex
  lt <- "{\\textless}"
  gt <- "{\\textgreater}"
  esc <- function(x) gsub(">", gt, gsub("<", lt, x, fixed = TRUE), fixed = TRUE)
  # taken from real exports: Zotero leaves these tags (escaped) in titles
  expect_identical(
    f(esc('<span class="nocase">x</span>')),
    "{x}"
  )
  expect_identical(
    f(esc('<span style="font-variant:small-caps;">C</span> olumba')),
    "\\textsc{C} olumba"
  )
  expect_identical(
    f(esc('<span lang="{EN}-{GB}">x</span>')),
    "{x}"
  )
  expect_identical(
    f(esc("<p><strong><em>A</em></strong> b</p>")),
    "\\textbf{\\emph{A}} b"
  )
  expect_identical(f(esc("x <sup/>")), "x ")
  expect_identical(
    f(paste0("\\textit{", esc('<span style="font-variant:small-caps;">'), "C")),
    "\\textit{\\textsc{C"
  )
})

test_that("cz_html_to_latex drops a shorttitle with a split tag", {
  entry <- paste0(
    "@article{K,\n\ttitle = {a {\\textless}span style=\"font-variant:",
    "small-caps;\"{\\textgreater}B{\\textless}/span{\\textgreater}: c},\n",
    "\tshorttitle = {a {\\textless}span style=\"font-variant},\n",
    "\tjournaltitle = {J},\n}"
  )
  out <- cz_html_to_latex(entry)
  expect_false(grepl("shorttitle", out, fixed = TRUE))
  expect_match(out, "title = {a \\textsc{B}: c},\n\tjournaltitle", fixed = TRUE)
  # a clean shorttitle stays
  ok <- "@article{K,\n\tshorttitle = {Short},\n}"
  expect_identical(cz_html_to_latex(ok), ok)
})

test_that("cz_html_to_latex leaves text without markup alone", {
  f <- cz_html_to_latex
  for (x in c(
    "plain {title}", "a < b and c > d", "x \\emph{y}", "{\\textsc{x}}",
    "3 <5, 6> 4", "", "Smith & Jones"
  )) {
    expect_identical(f(x), x, info = x)
  }
  expect_identical(f(c("<i>a</i>", "b")), c("\\emph{a}", "b"))
})

test_that("cz_export_bib converts markup in exported entries", {
  testthat::local_mocked_bindings(
    cz_bib_requests = function(auth, ids) list(NULL),
    cz_perform = function(req) NULL,
    cz_bib_text = function(resp) {
      entry("Key2020", '<span class=\"nocase\">An <i>open</i> tree</span>')
    }
  )
  out <- cz_export_bib(NULL, "ABC123", "Key2020")
  expect_match(out, "title = {{An \\emph{open} tree}}", fixed = TRUE)
  expect_no_match(out, "<")
})
