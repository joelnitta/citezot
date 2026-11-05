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
