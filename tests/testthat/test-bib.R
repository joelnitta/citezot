# Mock Zotero: /items/top serves CSL items; /items?itemKey=..&format=biblatex
# serves BibLaTeX (in reverse order, like the real API). `env$reqs` logs
# requests.
lib_items <- function() {
  mk <- function(id, key, title, note = NULL) {
    x <- list(
      id = file.path("1", id),
      type = "article-journal",
      title = title,
      `citation-key` = key
    )
    x$note <- note
    x
  }
  list(
    mk("ID1", "Kent2002", "BLAT", note = "Citation Key: Kent2002\nkeep me"),
    mk("ID2", "Ebihara2006", "Revision"),
    mk("ID3", "Weiß2015", "Unicode"),
    mk("ID4", "Other2000", "Not cited")
  )
}

mock_zotero <- function(env, items = lib_items()) {
  by_id <- setNames(items, vapply(items, function(i) sub("^.*/", "", i$id), ""))
  function(req) {
    env$reqs <- c(env$reqs, list(req))
    u <- httr2::url_parse(req$url)
    if (grepl("/items/top$", u$path)) {
      return(httr2::response_json(
        headers = list(`Total-Results` = as.character(length(items))),
        body = list(items = items)
      ))
    }
    ids <- rev(strsplit(u$query$itemKey, ",", fixed = TRUE)[[1]])
    txt <- vapply(ids, function(id) {
      sprintf(
        "@article{%s,\n\ttitle = {%s},\n}\n",
        by_id[[id]]$`citation-key`,
        by_id[[id]]$title
      )
    }, "")
    httr2::response(body = charToRaw(enc2utf8(paste(txt, collapse = "\n"))))
  }
}

auth_t <- cz_auth("1", "k")
qmd_file <- function(dir, body, front = NULL, name = "doc.qmd") {
  f <- file.path(dir, name)
  writeLines(c(if (!is.null(front)) c("---", front, "---"), body), f)
  f
}
read_all <- function(f) paste(readLines(f, encoding = "UTF-8"), collapse = "\n")
bytes <- function(f) readBin(f, "raw", file.size(f))

test_that("writes a sorted .bib containing only cited items", {
  d <- withr::local_tempdir()
  env <- new.env()
  httr2::local_mocked_responses(mock_zotero(env))
  q <- qmd_file(d, "Cites @Kent2002 and @Weiß2015, plus @Ebihara2006.")
  out <- file.path(d, "refs.bib")
  res <- cz_update_bib(q, out = out, auth = auth_t, quiet = TRUE)
  expect_identical(res, out)
  txt <- read_all(out)
  keys <- regmatches(
    txt,
    gregexpr("(?<=@article\\{)[^,]+", txt, perl = TRUE)
  )[[1]]
  expect_identical(keys, c("Ebihara2006", "Kent2002", "Weiß2015"))
  expect_no_match(txt, "Other2000")
})

test_that("writes CSL-YAML with id = citation-key and the key line stripped", {
  d <- withr::local_tempdir()
  env <- new.env()
  httr2::local_mocked_responses(mock_zotero(env))
  q <- qmd_file(d, "@Kent2002 @Ebihara2006")
  out <- file.path(d, "refs.yaml")
  cz_update_bib(q, out = out, auth = auth_t, quiet = TRUE)
  lines <- readLines(out)
  expect_identical(lines[1], "---")
  y <- yaml::read_yaml(out)
  expect_identical(
    vapply(y$references, function(r) r$id, ""),
    c("Ebihara2006", "Kent2002")
  )
  expect_identical(
    vapply(y$references, function(r) r$`citation-key`, ""),
    c("Ebihara2006", "Kent2002")
  )
  kent <- y$references[[2]]
  expect_identical(kent$note, "keep me")
})

test_that("a missing cited key errors and leaves the file untouched", {
  d <- withr::local_tempdir()
  env <- new.env()
  httr2::local_mocked_responses(mock_zotero(env))
  out <- file.path(d, "refs.bib")
  writeLines("previous good bibliography", out)
  before <- bytes(out)
  q <- qmd_file(d, "@Kent2002 and @Nope1999")
  expect_error(
    cz_update_bib(q, out = out, auth = auth_t, quiet = TRUE),
    "Nope1999"
  )
  expect_identical(bytes(out), before)
  # and no export request was made for the incomplete bibliography
  urls <- vapply(env$reqs, function(r) r$url, "")
  expect_false(any(grepl("biblatex", urls, fixed = TRUE)))
})

test_that("allow_incomplete = TRUE writes what was found, with a warning", {
  d <- withr::local_tempdir()
  env <- new.env()
  httr2::local_mocked_responses(mock_zotero(env))
  q <- qmd_file(d, "@Kent2002 and @Nope1999")
  out <- file.path(d, "refs.bib")
  expect_warning(
    cz_update_bib(
      q,
      out = out,
      allow_incomplete = TRUE,
      auth = auth_t,
      quiet = TRUE
    ),
    "Nope1999"
  )
  expect_match(read_all(out), "Kent2002")
})

test_that("a key found only in a bare file warns but still writes", {
  d <- withr::local_tempdir()
  env <- new.env()
  httr2::local_mocked_responses(mock_zotero(env))
  q <- qmd_file(d, "@Kent2002")
  csv <- file.path(d, "data.csv")
  writeLines("note,defined in Ebihara2006 and Gone1999", csv)
  out <- file.path(d, "refs.bib")
  expect_warning(
    cz_update_bib(q, out = out, bare = csv, auth = auth_t, quiet = TRUE),
    "Gone1999"
  )
  txt <- read_all(out)
  expect_match(txt, "Kent2002")
  expect_match(txt, "Ebihara2006")
})

test_that("duplicate citekeys in Zotero warn and use the first", {
  d <- withr::local_tempdir()
  env <- new.env()
  items <- lib_items()
  items[[4]]$`citation-key` <- "Kent2002" # ID4 duplicates ID1
  httr2::local_mocked_responses(mock_zotero(env, items))
  q <- qmd_file(d, "@Kent2002")
  out <- file.path(d, "refs.yaml")
  expect_warning(
    cz_update_bib(q, out = out, auth = auth_t, quiet = TRUE),
    "same citekey"
  )
  expect_identical(yaml::read_yaml(out)$references[[1]]$title, "BLAT")
})

test_that("out and format come from front matter and extension", {
  d <- withr::local_tempdir()
  env <- new.env()
  httr2::local_mocked_responses(mock_zotero(env))
  q <- qmd_file(d, "@Kent2002", front = "bibliography: mine.bib")
  res <- cz_update_bib(q, auth = auth_t, quiet = TRUE)
  expect_identical(basename(res), "mine.bib")
  expect_true(file.exists(file.path(d, "mine.bib")))
})

test_that("documents naming different bibliographies need an explicit out", {
  d <- withr::local_tempdir()
  env <- new.env()
  httr2::local_mocked_responses(mock_zotero(env))
  a <- qmd_file(d, "@Kent2002", front = "bibliography: a.bib", name = "a.qmd")
  b <- qmd_file(d, "@Kent2002", front = "bibliography: b.bib", name = "b.qmd")
  expect_error(
    cz_update_bib(c(a, b), auth = auth_t, quiet = TRUE),
    "different bibliography files"
  )
  expect_no_error(cz_update_bib(
    c(a, b),
    out = file.path(d, "all.bib"),
    auth = auth_t,
    quiet = TRUE
  ))
})

test_that("with no bibliography declared it falls back to references.bib", {
  d <- withr::local_tempdir()
  env <- new.env()
  httr2::local_mocked_responses(mock_zotero(env))
  withr::local_dir(d)
  q <- qmd_file(d, "@Kent2002")
  msgs <- testthat::capture_messages(cz_update_bib(q, auth = auth_t))
  expect_match(
    paste(msgs, collapse = ""),
    "No bibliography: found|references.bib"
  )
  expect_true(file.exists(file.path(d, "references.bib")))
})

test_that("format is inferred from the extension and conflicts are rejected", {
  expect_identical(cz_resolve_format("a.bib", NULL), "bib")
  expect_identical(cz_resolve_format("a.yml", NULL), "yaml")
  expect_identical(cz_resolve_format("a.txt", "yaml"), "yaml")
  expect_error(cz_resolve_format("a.txt", NULL), "Can't tell")
  expect_error(cz_resolve_format("a.bib", "yaml"), "looks like")
})

test_that("an unchanged bibliography is not rewritten", {
  d <- withr::local_tempdir()
  env <- new.env()
  httr2::local_mocked_responses(mock_zotero(env))
  q <- qmd_file(d, "@Kent2002")
  out <- file.path(d, "refs.bib")
  cz_update_bib(q, out = out, auth = auth_t, quiet = TRUE)
  old <- as.POSIXct("2020-01-01", tz = "UTC")
  Sys.setFileTime(out, old)
  msgs <- testthat::capture_messages(cz_update_bib(q, out = out, auth = auth_t))
  expect_match(paste(msgs, collapse = ""), "already up to date")
  expect_identical(as.numeric(file.mtime(out)), as.numeric(old))
})

test_that("no citations writes an empty bibliography, no exporter call", {
  d <- withr::local_tempdir()
  env <- new.env()
  httr2::local_mocked_responses(mock_zotero(env))
  q <- qmd_file(d, "No citations here.")
  out <- file.path(d, "refs.bib")
  cz_update_bib(q, out = out, auth = auth_t, quiet = TRUE)
  expect_true(file.exists(out))
  urls <- vapply(env$reqs, function(r) r$url, "")
  expect_false(any(grepl("biblatex", urls, fixed = TRUE)))
})

test_that("missing input files or output directory are clear errors", {
  expect_error(
    cz_update_bib("nope.qmd", out = "x.bib", auth = auth_t),
    "not found"
  )
  d <- withr::local_tempdir()
  env <- new.env()
  httr2::local_mocked_responses(mock_zotero(env))
  q <- qmd_file(d, "@Kent2002")
  expect_error(
    cz_update_bib(
      q,
      out = file.path(d, "nodir", "x.bib"),
      auth = auth_t,
      quiet = TRUE
    ),
    "does not exist"
  )
})

test_that("cz_rel_path shortens paths inside the working directory only", {
  d <- withr::local_tempdir()
  withr::local_dir(d)
  expect_identical(
    cz_rel_path(file.path(normalizePath(d), "sub", "x.bib")),
    "sub/x.bib"
  )
  expect_identical(cz_rel_path("/elsewhere/x.bib"), "/elsewhere/x.bib")
})
