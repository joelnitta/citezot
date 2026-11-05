csl <- function(
  id,
  key,
  title,
  family = "Smith",
  doi = NULL,
  isbn = NULL,
  year = 2020,
  ct = "Journal",
  type = "article-journal"
) {
  x <- list(
    id = file.path("1", id), type = type, title = title, `citation-key` = key,
    author = lapply(family, function(f) list(family = f, given = "A.")),
    issued = list(`date-parts` = list(list(year))),
    `container-title` = ct
  )
  x$DOI <- doi
  x$ISBN <- isbn
  x
}
lib <- list(
  csl(
    "AAAAAA22",
    "Ebihara2006",
    "A taxonomic revision of Hymenophyllaceae",
    family = "Ebihara",
    doi = "10.3767/000651906X622210",
    year = 2006,
    ct = "Blumea"
  ),
  csl(
    "BBBBBB33",
    "Weiß2015",
    "Damage and decay kinetics of herbarium DNA",
    family = c("Weiß", "Burbano", "Krause"),
    doi = "10.1101/023135",
    year = 2015
  ),
  csl(
    "CCCCCC44",
    "iwatsuki2023",
    "Hymenophyllaceae of Japan",
    family = c("Iwatsuki", "Ebihara"),
    isbn = "978-4-8299-1234-5",
    year = 2023,
    type = "book"
  ),
  csl(
    "DDDDDD55",
    NA_character_,
    "Item without a pinned key",
    family = "Nobody",
    year = 1999
  )
)
lib[[4]]$`citation-key` <- NULL

test_that("cz_find requires at least one criterion", {
  expect_error(cz_find(items = lib), "at least one")
})

test_that("cz_find returns a tidy table", {
  out <- cz_find(citekey = "Ebihara2006", items = lib)
  expect_named(
    out,
    c("item", "citekey", "author", "year", "title", "doi", "type")
  )
  expect_identical(out$item, "AAAAAA22")
  expect_identical(out$author, "Ebihara")
  expect_identical(out$year, "2006")
})

test_that("DOI matching ignores case and prefixes", {
  for (d in c(
    "10.3767/000651906x622210",
    "https://doi.org/10.3767/000651906X622210",
    "doi:10.3767/000651906X622210"
  )) {
    expect_identical(cz_find(doi = d, items = lib)$citekey, "Ebihara2006")
  }
})

test_that("ISBN matching ignores hyphens", {
  expect_identical(
    cz_find(isbn = "9784829912345", items = lib)$citekey,
    "iwatsuki2023"
  )
})

test_that("free-text query needs every word, ignoring case", {
  expect_identical(
    cz_find("ebihara revision", items = lib)$citekey,
    "Ebihara2006"
  )
  # author of two items
  expect_identical(nrow(cz_find("ebihara", items = lib)), 2L)
  expect_identical(cz_find("blumea 2006", items = lib)$citekey, "Ebihara2006")
  # non-first author
  expect_identical(cz_find("krause", items = lib)$citekey, "Weiß2015")
  expect_identical(nrow(cz_find("ebihara zzzz", items = lib)), 0L)
})

test_that("criteria combine with AND; no match is an empty table", {
  expect_identical(
    nrow(cz_find("hymenophyllaceae", doi = "10.1101/023135", items = lib)),
    0L
  )
  out <- cz_find("nothing like this", items = lib)
  expect_identical(nrow(out), 0L)
  expect_identical(names(out)[1], "item")
})

test_that("authors are summarized", {
  expect_identical(
    cz_find(citekey = "Weiß2015", items = lib)$author,
    "Weiß et al."
  )
  expect_identical(
    cz_find(citekey = "iwatsuki2023", items = lib)$author,
    "Iwatsuki & Ebihara"
  )
})

test_that("items without a pinned key are findable but have NA citekey", {
  out <- cz_find("pinned key", items = lib)
  expect_identical(out$item, "DDDDDD55")
  expect_true(is.na(out$citekey))
})

test_that("cz_find fetches the library when items are not supplied", {
  httr2::local_mocked_responses(function(req) {
    httr2::response_json(
      headers = list(`Total-Results` = "4"),
      body = list(items = lib)
    )
  })
  expect_identical(
    cz_find(citekey = "Ebihara2006", auth = cz_auth("1", "k"))$item,
    "AAAAAA22"
  )
})

test_that("an empty library does not break cz_find", {
  expect_identical(nrow(cz_find("anything", items = list())), 0L)
})

# --- cz_resolve_item ---------------------------------------------------------
auth_f <- cz_auth("1", "k")
res <- function(x) cz_resolve_item(x, auth_f, items = lib)

test_that("Zotero item IDs pass straight through, with or without prefix", {
  expect_identical(res("Q62TD7I9"), "Q62TD7I9")
  expect_identical(res("6265773/Q62TD7I9"), "Q62TD7I9")
})

test_that("DOIs and citekeys resolve to an item ID", {
  expect_identical(res("10.1101/023135"), "BBBBBB33")
  expect_identical(res("https://doi.org/10.1101/023135"), "BBBBBB33")
  expect_identical(res("Ebihara2006"), "AAAAAA22")
})

test_that("a one-row cz_find() result resolves; other shapes are rejected", {
  expect_identical(res(cz_find(citekey = "Weiß2015", items = lib)), "BBBBBB33")
  expect_error(res(cz_find("ebihara", items = lib)), "exactly one row")
  expect_error(res(cz_find("zzzz", items = lib)), "exactly one row")
})

test_that("unknown or ambiguous identifiers give clear errors", {
  expect_error(res("NoSuchKey1999"), "No item in the library matches citekey")
  expect_error(res("10.9999/none"), "No item in the library matches DOI")
  lib2 <- c(
    lib,
    list(csl("EEEEEE66", "Ebihara2006", "Duplicate", family = "X"))
  )
  expect_error(
    cz_resolve_item("Ebihara2006", auth_f, items = lib2),
    "2 items match"
  )
})

test_that("lower-case look-alikes of item IDs are treated as citekeys", {
  # Zotero IDs are upper case without 0, 1, O, I-lookalikes; 'Kent2002' has 0
  expect_error(res("Kent2002"), "No item in the library matches citekey")
})
