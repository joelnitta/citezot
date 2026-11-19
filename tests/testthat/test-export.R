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

test_that("cz_html_to_markdown converts tags to Pandoc markdown", {
  cases <- list(
    c("New <i>Trichomanes</i> X", "New *Trichomanes* X"),
    c("<em>A</em> and <strong>B</strong>", "*A* and **B**"),
    c("H<sub>2</sub>O, m<sup>2</sup>", "H~2~O, m^2^"),
    c("<sc>Smith</sc>", "[Smith]{.smallcaps}"),
    c("<span class=\"nocase\">DNA</span> data", "[DNA]{.nocase} data"),
    c("<span class='nocase'><i>Deparia</i></span>", "[*Deparia*]{.nocase}"),
    c("<span style=\"font-variant:small-caps;\">X</span>", "[X]{.smallcaps}"),
    c("<span style=\"font-style: italic\">X</span>", "*X*"),
    c("<span style=\"font-weight:bold\">X</span>", "**X**"),
    c("<u>X</u>", "[X]{.underline}"),
    c("<span lang=\"EN-GB\">plain</span>", "plain"),
    c("<a href=\"https://x.org\">link</a>", "link"),
    c("<I>A</I>", "*A*"),
    c("no tags", "no tags")
  )
  for (case in cases) {
    expect_identical(cz_html_to_markdown(case[1]), case[2], info = case[1])
  }
  expect_identical(cz_html_to_markdown(c("<i>a</i>", NA)), c("*a*", NA))
  expect_identical(cz_html_to_markdown(3), 3)
})

test_that("cz_html_to_markdown escapes text Pandoc would read as markup", {
  cases <- list(
    c("PAUP*: phylogenetic analysis", "PAUP\\*: phylogenetic analysis"),
    c("__init__ and _x_", "\\_\\_init\\_\\_ and \\_x\\_"),
    c("Costs $5 to $10", "Costs \\$5 to \\$10"),
    c("Sedges [in Japanese]", "Sedges \\[in Japanese\\]"),
    c("H~2~O and a^b", "H\\~2\\~O and a\\^b"),
    c("`code` and a\\b", "\\`code\\` and a\\\\b"),
    c("p < 0.05 and q > 1", "p \\< 0.05 and q > 1"),
    # looks like a tag, but is text
    c("a<b and c>d", "a\\<b and c>d"),
    c("x<y, z>w", "x\\<y, z>w"),
    c("<abbr>X</abbr>", "\\<abbr>X\\</abbr>"),
    # autolinks stay links
    c("GBIF (<https://www.gbif.org/a_b>)", "GBIF (<https://www.gbif.org/a_b>)"),
    c("<i>a*b</i>", "*a\\*b*")
  )
  for (case in cases) {
    expect_identical(cz_html_to_markdown(case[1]), case[2], info = case[1])
  }
  expect_identical(
    cz_html_to_markdown("https://x.org/<i>a_b</i>", tags = FALSE),
    "https://x.org/\\<i>a\\_b\\</i>"
  )
})

test_that("cz_html_to_markdown keeps markers balanced and parseable", {
  cases <- list(
    # nesting, mis-nesting, unclosed and stray tags
    c("<span class=\"nocase\"><i>A</i> b</span>", "[*A* b]{.nocase}"),
    c("<i>Foo<b>bar</i>baz</b>", "*Foo**bar***baz"),
    c("<i>Foo", "*Foo*"),
    c("<i>a<b>b", "*a**b***"),
    c("stray </i> closer", "stray  closer"),
    c("<i>a</b>b</i>", "*ab*"),
    # block tags do not close a run, and become a space
    c("<i>a<p>b</p>c</i>", "*a b c*"),
    c("First.</p><p>Second.", "First. Second."),
    c("line one<br/>line two", "line one line two"),
    c("<p>one</p>", "one"),
    c("<h2>Aims</h2>Text", "Aims Text"),
    c("a<hr/>b", "a b"),
    c("<jats:p>A <jats:italic>B</jats:italic></jats:p>", "A *B*"),
    # spaces move out of emphasis; empty runs vanish
    c("<i>Aster </i>(Asteraceae)", "*Aster* (Asteraceae)"),
    c("<i>P. </i>×<i>hizenense</i>", "*P.* ×*hizenense*"),
    c("a<i> b</i>", "a *b*"),
    c("<i></i>x", "x"),
    c("<i> </i>x", " x"),
    c("<i/>x", "x"),
    # adjacent runs of the same kind merge (`*a**b*` does not parse)
    c("<i>a</i><i>b</i>", "*ab*"),
    c("<i>a</i><em>b</em>", "*ab*"),
    c("<i>a</i><b>b</b>", "*a***b**"),
    c("<i>a</i> <i>b</i>", "*a* *b*"),
    # sub- and superscripts cannot hold a bare space
    c("10<sup>-3 mol</sup>", "10^-3\\ mol^"),
    c("<sup><i>a b</i></sup>", "^*a\\ b*^")
  )
  for (case in cases) {
    expect_identical(cz_html_to_markdown(case[1]), case[2], info = case[1])
  }
})

test_that("cz_item_html_to_markdown leaves ids, escapes links, walks lists", {
  item <- list(
    id = "a_b_",
    `citation-key` = "a_b_",
    title = "A <i>b</i> c",
    URL = "https://x.org/a_b/?q=<i>",
    DOI = "10.1641/0006(2001)051[0933:T]2.0.CO;2",
    author = list(list(family = "<i>X</i>", given = "Y_Z")),
    issued = list(`date-parts` = list(list(2020L)))
  )
  out <- cz_item_html_to_markdown(item)
  expect_identical(out$id, "a_b_")
  expect_identical(out$`citation-key`, "a_b_")
  expect_identical(out$title, "A *b* c")
  expect_identical(out$URL, "https://x.org/a\\_b/?q=\\<i>")
  expect_identical(out$DOI, "10.1641/0006(2001)051\\[0933:T\\]2.0.CO;2")
  expect_identical(out$author[[1]]$family, "*X*")
  expect_identical(out$author[[1]]$given, "Y\\_Z")
  expect_identical(out$issued, item$issued)
})

test_that("a short title with a tag cut in two is dropped", {
  # Zotero cuts short titles at the first colon, splitting
  # `font-variant:small-caps`
  item <- list(
    title = "Using <span style=\"font-variant:small-caps;\">eDNA</span>: x",
    `title-short` = "Using <span style=\"font-variant",
    shortTitle = "Using <span style=\"font-variant"
  )
  out <- cz_item_html_to_markdown(item)
  expect_identical(out$title, "Using [eDNA]{.smallcaps}: x")
  expect_null(out$`title-short`)
  expect_null(out$shortTitle)
  ok <- list(`title-short` = "<i>Ynesmexia</i>")
  expect_identical(cz_item_html_to_markdown(ok)$`title-short`, "*Ynesmexia*")
})

test_that("cz_render_yaml writes the converted markup as valid YAML", {
  items <- list(list(
    id = "1/ID1",
    type = "article-journal",
    title = "<i>Abc</i> d",
    `container-title` = "[Ecology] & PAUP*",
    `title-short` = "<span class=\"nocase\">X</span>",
    note = "Citation Key: Key2020\n_eprint: https://x.org/a_b"
  ))
  txt <- cz_render_yaml(items, "Key2020")
  ref <- yaml::yaml.load(txt)$references[[1]]
  expect_identical(ref$id, "Key2020")
  expect_identical(ref$`citation-key`, "Key2020")
  expect_identical(ref$title, "*Abc* d")
  expect_identical(ref$`container-title`, "\\[Ecology\\] & PAUP\\*")
  expect_identical(ref$`title-short`, "[X]{.nocase}")
  expect_identical(ref$note, "\\_eprint: https://x.org/a\\_b")
})

test_that("Pandoc renders the converted CSL-YAML as intended", {
  skip_on_cran()
  pandoc <- Sys.which("pandoc")
  skip_if(!nzchar(pandoc), "pandoc not found")
  d <- withr::local_tempdir()
  items <- list(list(
    id = "1/ID1",
    type = "article-journal",
    title = paste(
      "New <i>Trichomanes</i> <i>A</i><i>B</i> 10<sup>-3 mol</sup>",
      "PAUP* $5 to $10 a<b and c>d"
    ),
    DOI = "10.1/a_b_*c*"
  ))
  writeLines(cz_render_yaml(items, "Key2020"), file.path(d, "refs.yaml"))
  writeLines(
    c("---", "bibliography: refs.yaml", "nocite: '@*'", "---"),
    file.path(d, "doc.md")
  )
  out <- withr::with_dir(d, system2(
    pandoc, c("doc.md", "--citeproc", "-t", "html", "--wrap=none"),
    stdout = TRUE
  ))
  out <- paste(out, collapse = "\n")
  expect_match(out, "New <em>Trichomanes</em> <em>AB</em>", fixed = TRUE)
  expect_match(out, "10<sup>-3 mol</sup>", fixed = TRUE)
  expect_match(out, "PAUP* $5 to $10 a&lt;b and c&gt;d", fixed = TRUE)
  expect_match(out, "10.1/a_b_*c*", fixed = TRUE)
})
