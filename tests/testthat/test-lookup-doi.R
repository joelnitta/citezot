valid <- c(
  "itemType",
  "title",
  "creators",
  "abstractNote",
  "date",
  "DOI",
  "url",
  "language",
  "libraryCatalog",
  "accessDate",
  "publicationTitle",
  "volume",
  "issue",
  "pages",
  "ISSN", "publisher", "place", "ISBN", "bookTitle", "repository", "university"
)
t0 <- as.POSIXct("2026-01-02 03:04:05", tz = "UTC")

article <- list(
  type = "journal-article", DOI = "10.1234/abc",
  title = list(
    paste0(
      "A <i>taxonomic</i> revision of ",
      "<jats:italic>Ferns</jats:italic> &amp; allies"
    )
  ),
  subtitle = list("with notes"),
  `container-title` = list(
    "Blumea"
  ), volume = "51", issue = "2", page = "221-280",
  ISSN = list("0006-5196", "0006-5196", "1234-5678"),
  issued = list(`date-parts` = list(list(2006, 7, 27))),
  publisher = "Naturalis", language = "en",
  abstract = paste0(
    "<jats:title>Abstract</jats:title><jats:p>We ",
    "<jats:italic>revise</jats:italic> it &amp; more.</jats:p>"
  ),
  author = list(
    list(given = "Atsushi", family = "Ebihara", sequence = "first"),
    list(name = "Some Consortium", sequence = "additional")
  ),
  editor = list(list(given = "E", family = "Editor"))
)

test_that("Crossref types map to Zotero item types, with a safe fallback", {
  expect_identical(cz_crossref_type("journal-article"), "journalArticle")
  expect_identical(cz_crossref_type("book-chapter"), "bookSection")
  expect_identical(cz_crossref_type("proceedings-article"), "conferencePaper")
  expect_identical(cz_crossref_type("posted-content"), "preprint")
  expect_identical(cz_crossref_type("peer-review"), "document")
  expect_identical(cz_crossref_type("something-new"), "document")
})

test_that("markup is stripped except the tags Zotero renders", {
  expect_identical(
    cz_strip_markup(
      "A <i>b</i> <jats:italic>c</jats:italic> &amp; d &lt;e&gt; <sub>2</sub>"
    ),
    "A <i>b</i> c & d <e> <sub>2</sub>"
  )
  expect_identical(
    cz_strip_markup("<p>x <i>y</i></p>", keep = character()),
    "x y"
  )
  expect_true(is.na(cz_strip_markup(NA_character_)))
})

test_that("dates keep the precision Crossref gives", {
  d <- function(...) {
    cz_crossref_date(
      list(issued = list(`date-parts` = list(list(...))))
    )
  }
  expect_identical(d(2006, 7, 27), "2006-07-27")
  expect_identical(d(2006, 7), "2006-07")
  expect_identical(d(2006), "2006")
  expect_identical(
    cz_crossref_date(list(published = list(`date-parts` = list(list(1999))))),
    "1999"
  )
  expect_true(is.na(cz_crossref_date(list())))
})

test_that("a journal article maps onto Zotero fields", {
  res <- cz_crossref_to_item(article, "journalArticle", valid, accessed = t0)
  it <- res$item
  expect_identical(it$itemType, "journalArticle")
  expect_identical(
    it$title,
    "A <i>taxonomic</i> revision of Ferns & allies: with notes"
  )
  expect_identical(it$publicationTitle, "Blumea")
  expect_identical(
    it[c("volume", "issue", "pages", "date")],
    list(volume = "51", issue = "2", pages = "221-280", date = "2006-07-27")
  )
  expect_identical(it$ISSN, "0006-5196, 1234-5678") # duplicates removed
  expect_identical(it$url, "https://doi.org/10.1234/abc")
  expect_identical(it$abstractNote, "We revise it & more.")
  expect_identical(it$libraryCatalog, "Crossref")
  expect_identical(it$accessDate, "2026-01-02T03:04:05Z")
  expect_length(res$dropped, 0)
})

test_that("creators: people, organisations and editors", {
  cr <- cz_crossref_to_item(article, "journalArticle", valid)$item$creators
  expect_identical(
    cr[[1]],
    list(creatorType = "author", firstName = "Atsushi", lastName = "Ebihara")
  )
  expect_identical(
    cr[[2]],
    list(creatorType = "author", name = "Some Consortium")
  )
  expect_identical(cr[[3]]$creatorType, "editor")
})

test_that("fields not valid for the type are dropped and reported, not sent", {
  res <- cz_crossref_to_item(
    article,
    "journalArticle",
    setdiff(valid, c("ISSN", "volume"))
  )
  expect_null(res$item$ISSN)
  expect_null(res$item$volume)
  expect_setequal(res$dropped, c("ISSN", "volume"))
})

test_that("empty and missing values are omitted", {
  res <- cz_crossref_to_item(
    list(type = "journal-article", DOI = "10.1234/x", title = list("T")),
    "journalArticle",
    valid
  )
  expect_setequal(
    names(res$item),
    c("itemType", "title", "DOI", "url", "libraryCatalog", "accessDate")
  )
})

test_that("book chapters use the container as the book title", {
  ch <- modifyList(
    article,
    list(
      type = "book-chapter",
      ISBN = list("978-1-23456-789-7"),
      `publisher-location` = "Berlin"
    )
  )
  it <- cz_crossref_to_item(ch, "bookSection", valid)$item
  expect_identical(it$bookTitle, "Blumea")
  expect_identical(it$place, "Berlin")
  expect_identical(it$ISBN, "978-1-23456-789-7")
  expect_null(it$publicationTitle)
})

test_that("preprints and theses take their repository / institution", {
  pp <- list(
    type = "posted-content",
    DOI = "10.1101/1",
    title = list("P"),
    institution = list(list(name = "bioRxiv"))
  )
  expect_identical(
    cz_crossref_to_item(pp, "preprint", valid)$item$repository,
    "bioRxiv"
  )
  th <- list(
    type = "dissertation",
    DOI = "10.1/x",
    title = list("T"),
    publisher = "Uni X"
  )
  expect_identical(
    cz_crossref_to_item(th, "thesis", valid)$item$university,
    "Uni X"
  )
})

test_that("cz_crossref_fetch returns the message; unknown DOIs error clearly", {
  httr2::local_mocked_responses(function(req) {
    if (grepl("10.1234/abc", req$url, fixed = TRUE)) {
      httr2::response_json(body = list(
        status = "ok",
        message = list(DOI = "10.1234/abc", type = "journal-article")
      ))
    } else {
      httr2::response(status_code = 404)
    }
  })
  expect_identical(cz_crossref_fetch("10.1234/abc")$type, "journal-article")
  expect_error(cz_crossref_fetch("10.9999/missing"), "no record of the DOI")
})

test_that("the polite-pool address is only sent when the user sets it", {
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req$url
    httr2::response_json(body = list(message = list()))
  })
  cz_crossref_fetch("10.1234/abc")
  expect_no_match(seen, "mailto")
  withr::local_options(citezot.mailto = "me@example.org")
  cz_crossref_fetch("10.1234/abc")
  expect_match(seen, "mailto=me%40example.org|mailto=me@example.org")
})

test_that("DOIs with unusual characters are passed to Crossref intact", {
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req$url
    httr2::response_json(body = list(message = list()))
  })
  cz_crossref_fetch(
    "10.1002/(SICI)1097-0258(19980815/30)17:15/16<1661::AID-SIM968>3.0.CO;2-2"
  )
  expect_match(seen, "^https://api.crossref.org/works/10.1002/")
  expect_match(seen, "1661")
})

test_that("empty arrays from Crossref don't break the mapping", {
  # Crossref sends [] (an empty list) for absent values such as subtitle
  msg <- list(
    type = "journal-article", DOI = "10.1234/x",
    title = list("T"), subtitle = list(), `container-title` = list(),
    ISSN = list(), author = list(), institution = list(), page = NULL
  )
  res <- cz_crossref_to_item(msg, "journalArticle", valid)
  expect_identical(res$item$title, "T")
  expect_null(res$item$publicationTitle)
  expect_null(res$item$creators)
  # and for types that read institution / event
  for (ty in c("preprint", "thesis", "report", "conferencePaper")) {
    expect_no_error(cz_crossref_to_item(msg, ty, valid))
  }
  # title missing entirely
  expect_no_error(cz_crossref_to_item(
    list(type = "dataset", DOI = "10.1234/x"),
    "dataset",
    valid
  ))
})

test_that("only fully upper-case names are re-cased", {
  expect_identical(cz_fix_caps("WATSON"), "Watson")
  expect_identical(cz_fix_caps("SMITH-JONES"), "Smith-Jones")
  expect_identical(cz_fix_caps("VAN DER BERG"), "Van Der Berg")
  expect_identical(cz_fix_caps("J. D."), "J. D.") # initials untouched
  expect_identical(cz_fix_caps("J"), "J")
  expect_identical(cz_fix_caps("McDonald"), "McDonald") # mixed case untouched
  expect_identical(cz_fix_caps("Ebihara"), "Ebihara")
  expect_identical(cz_fix_caps(""), "")
  expect_identical(cz_fix_caps("MÜLLER"), "Müller")
  msg <- list(author = list(list(given = "J. D.", family = "WATSON")))
  expect_identical(
    cz_crossref_creators(msg)[[1]],
    list(creatorType = "author", firstName = "J. D.", lastName = "Watson")
  )
})
