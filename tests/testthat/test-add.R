tmpl_fields <- c(
  "itemType", "title", "creators", "abstractNote", "date", "DOI", "url", "language",
  "libraryCatalog", "accessDate", "publicationTitle", "volume", "issue", "pages",
  "ISSN", "collections", "tags", "relations", "citationKey"
)
crossref_msg <- list(
  type = "journal-article", DOI = "10.1234/new",
  title = list("A new paper"), `container-title` = list("Blumea"),
  volume = "5", issued = list(`date-parts` = list(list(2024, 3))),
  author = list(list(given = "Ann", family = "Author"))
)
lib_item <- list(id = "1/AAAAAA22", type = "article-journal", title = "Old",
                 DOI = "10.1234/old", `citation-key` = "Old2000")

# One fake serving Zotero + Crossref. `env` records requests (env$reqs) and
# can override pieces: env$post (response for POST), env$collections.
fake <- function(env) {
  env$reqs <- list()
  env$post <- env$post %||% list(successful = list(`0` = list(key = "NEWK2345", version = 9)))
  env$collections <- env$collections %||% list(
    list(key = "COLL2345", data = list(name = "Ferns")),
    list(key = "COLL6789", data = list(name = "Papers"))
  )
  function(req) {
    env$reqs <- c(env$reqs, list(req))
    url <- req$url
    if (grepl("^https://api.crossref.org", url)) {
      return(httr2::response_json(body = list(message = crossref_msg)))
    }
    if (grepl("/items/new", url)) {
      return(httr2::response_json(body = setNames(as.list(rep("", length(tmpl_fields))), tmpl_fields)))
    }
    if (grepl("/items/top", url)) {
      return(httr2::response_json(headers = list(`Total-Results` = "1"), body = list(items = list(lib_item))))
    }
    if (grepl("/collections", url)) {
      return(httr2::response_json(headers = list(`Total-Results` = as.character(length(env$collections))), body = env$collections))
    }
    if (httr2::req_get_method(req) == "POST") {
      if (is.numeric(env$post)) return(httr2::response(status_code = env$post))
      return(httr2::response_json(body = env$post))
    }
    stop("unexpected request: ", url)
  }
}
urls <- function(env) vapply(env$reqs, function(r) r$url, "")
a <- cz_auth("1", "k")
setup_add <- function(env = new.env(), .frame = parent.frame()) {
  .cz_state$templates <- list()
  httr2::local_mocked_responses(fake(env), env = .frame)
  env
}

test_that("non-DOI identifiers are rejected with a pointer to what is supported", {
  expect_error(cz_add("978-0-262-03384-8", auth = a), "doesn't look like a DOI")
  expect_error(cz_add("Kent2002", auth = a), "doesn't look like a DOI")
})

test_that("the default is a dry run: reads and looks up, but never POSTs", {
  env <- setup_add()
  msgs <- testthat::capture_messages(
    res <- cz_add("https://doi.org/10.1234/new", key = "Author2024", collection = "Ferns", auth = a)
  )
  expect_false(any(vapply(env$reqs, httr2::req_get_method, "") == "POST"))
  expect_false(res$written)
  expect_equal(res$item$itemType, "journalArticle")
  expect_equal(res$item$title, "A new paper")
  expect_equal(res$item$citationKey, "Author2024")
  expect_equal(res$item$collections, list("COLL2345"))
  expect_equal(res$item$creators[[1]]$lastName, "Author")
  txt <- paste(msgs, collapse = "")
  expect_match(txt, "Dry run")
  expect_match(txt, "A new paper")
  expect_match(txt, "Author2024")
})

test_that("an item already in the library is not added again, and Crossref is not asked", {
  env <- setup_add()
  msgs <- testthat::capture_messages(res <- cz_add("10.1234/OLD", dry_run = FALSE, auth = a))
  expect_match(paste(msgs, collapse = ""), "Already in your library")
  expect_equal(res$existing$citekey, "Old2000")
  expect_false(res$written)
  expect_false(any(grepl("crossref|POST", urls(env))))
  expect_false(any(vapply(env$reqs, httr2::req_get_method, "") == "POST"))
})

test_that("a citekey already in use is refused before any lookup", {
  env <- setup_add()
  expect_error(cz_add("10.1234/new", key = "Old2000", auth = a), "already used by item AAAAAA22")
  expect_false(any(grepl("crossref", urls(env))))
})

test_that("keys that pandoc can't cite are refused before any request", {
  env <- setup_add()
  for (bad in c("??llgaard2016", "has space", "-lead", "trail.", "")) {
    expect_error(cz_add("10.1234/new", key = bad, auth = a))
  }
  expect_length(env$reqs, 0)
  # accents and internal punctuation are fine
  expect_no_error(suppressMessages(cz_add("10.1234/new", key = "Weiß:2015.a", auth = a)))
})

test_that("a live add POSTs one item with a write token and returns the new key", {
  env <- setup_add()
  res <- suppressMessages(cz_add("10.1234/new", key = "Author2024", dry_run = FALSE, auth = a))
  post <- Filter(function(r) httr2::req_get_method(r) == "POST", env$reqs)
  expect_length(post, 1)
  expect_match(post[[1]]$url, "/users/1/items$")
  tok <- post[[1]]$headers[["Zotero-Write-Token"]]
  expect_match(tok, "^[0-9a-f]{32}$")
  expect_null(post[[1]]$headers[["If-Unmodified-Since-Version"]])
  body <- post[[1]]$body$data
  expect_length(body, 1)                      # an array of one item
  expect_equal(body[[1]]$citationKey, "Author2024") # pinned in the same request
  expect_equal(res$key, "NEWK2345")
  expect_true(res$written)
})

test_that("the write token is unique per call even if the user set a seed", {
  toks <- character()
  for (i in 1:3) {
    env <- setup_add()
    set.seed(1)
    suppressMessages(cz_add("10.1234/new", dry_run = FALSE, auth = a))
    post <- Filter(function(r) httr2::req_get_method(r) == "POST", env$reqs)
    toks <- c(toks, post[[1]]$headers[["Zotero-Write-Token"]])
  }
  expect_length(unique(toks), 3)
})

test_that("both documented success shapes are understood", {
  env <- new.env(); env$post <- list(success = list(`0` = "ABCD2345"))
  setup_add(env)
  res <- suppressMessages(cz_add("10.1234/new", dry_run = FALSE, auth = a))
  expect_equal(res$key, "ABCD2345")
})

test_that("a failed creation is reported with Zotero's message", {
  env <- new.env(); env$post <- list(failed = list(`0` = list(code = 400, message = "'foo' is not a valid field")))
  setup_add(env)
  expect_error(cz_add("10.1234/new", dry_run = FALSE, auth = a), "not a valid field")
})

test_that("a reused write token (412) is explained as probably already done", {
  env <- new.env(); env$post <- 412
  setup_add(env)
  expect_error(cz_add("10.1234/new", dry_run = FALSE, auth = a), "already processed")
})

test_that("collections resolve by key or exact name; unknown or ambiguous ones error", {
  env <- setup_add()
  expect_equal(cz_resolve_collection(a, "COLL6789"), "COLL6789")
  expect_equal(cz_resolve_collection(a, "Papers"), "COLL6789")
  expect_error(cz_resolve_collection(a, "papers"), "No collection")
  env$collections <- list(list(key = "AAAA2222", data = list(name = "Dup")), list(key = "BBBB3333", data = list(name = "Dup")))
  expect_error(cz_resolve_collection(a, "Dup"), "2 collections are named")
})

test_that("an unknown collection stops before Crossref is queried", {
  env <- setup_add()
  expect_error(cz_add("10.1234/new", collection = "Nope", auth = a), "No collection")
  expect_false(any(grepl("crossref", urls(env))))
})

test_that("the item template is fetched once per type per session", {
  env <- setup_add()
  suppressMessages(cz_add("10.1234/new", auth = a))
  suppressMessages(cz_add("10.1234/new", auth = a))
  expect_equal(sum(grepl("/items/new", urls(env))), 1)
})

test_that("a Crossref type with no Zotero equivalent becomes a generic document", {
  .cz_state$templates <- list()
  crossref_msg$type <- "peer-review"
  env <- new.env()
  httr2::local_mocked_responses(function(req) {
    if (grepl("crossref", req$url)) return(httr2::response_json(body = list(message = crossref_msg)))
    fake(env)(req)
  })
  res <- suppressMessages(cz_add("10.1234/new", auth = a))
  expect_equal(res$item$itemType, "document")
})

test_that("no contact address is sent to Crossref unless the user sets one", {
  env <- setup_add()
  suppressMessages(cz_add("10.1234/new", auth = a))
  expect_false(any(grepl("mailto", urls(env))))
})
