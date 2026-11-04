# Mock the Zotero API: serves `total` fake CSL items, `limit` per page, and
# records every request in `env$reqs`.
mock_library <- function(total, env) {
  function(req) {
    env$reqs <- c(env$reqs, list(req))
    q <- httr2::url_parse(req$url)$query
    start <- as.integer(q$start)
    n <- max(min(as.integer(q$limit), total - start), 0)
    items <- lapply(seq_len(n), function(i) list(id = paste0("1/K", start + i)))
    httr2::response_json(
      headers = list(`Total-Results` = as.character(total)),
      body = list(items = items)
    )
  }
}

test_that("cz_fetch_items pages through a 250-item library in 3 requests", {
  env <- new.env()
  httr2::local_mocked_responses(mock_library(250, env))
  items <- cz_fetch_items(cz_auth("123", "k"))
  expect_length(env$reqs, 3)
  expect_length(items, 250)
  expect_equal(items[[250]]$id, "1/K250")
})

test_that("cz_fetch_items makes one request for small libraries", {
  for (total in c(0, 1, 50, 100)) {
    env <- new.env()
    httr2::local_mocked_responses(mock_library(total, env))
    expect_length(cz_fetch_items(cz_auth("123", "k")), total)
    expect_length(env$reqs, 1)
  }
})

test_that("cz_fetch_items builds the right request", {
  env <- new.env()
  httr2::local_mocked_responses(mock_library(1, env))
  cz_fetch_items(cz_auth("123", "k"))
  req <- env$reqs[[1]]
  expect_match(req$url, "^https://api.zotero.org/users/123/items/top\\?")
  expect_match(req$url, "format=csljson")
  expect_equal(req$headers[["Zotero-API-Version"]], "3")

  env <- new.env()
  httr2::local_mocked_responses(mock_library(1, env))
  cz_fetch_items(cz_auth("9", "k", library_type = "group"))
  expect_match(env$reqs[[1]]$url, "/groups/9/items/top")
})

test_that("cz_fetch_items validates page_size", {
  expect_error(cz_fetch_items(cz_auth("1", "k"), page_size = 101))
})

test_that("Retry-After / Backoff headers set the retry delay", {
  resp <- function(h) httr2::response(headers = h)
  expect_equal(cz_retry_after(resp(list(`Retry-After` = "5"))), 5)
  expect_equal(cz_retry_after(resp(list(Backoff = "12"))), 12)
  expect_true(is.na(cz_retry_after(resp(list()))))
})
