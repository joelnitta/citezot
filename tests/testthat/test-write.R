# Mock a single item: GET returns it, PATCH returns `patch_status`.
mock_item <- function(env, citation_key = "", patch_status = 204) {
  function(req) {
    env$reqs <- c(env$reqs, list(req))
    if (httr2::req_get_method(req) == "GET") {
      httr2::response_json(
        body = list(
          key = "ABCD2345",
          version = 7,
          data = list(citationKey = citation_key)
        )
      )
    } else {
      httr2::response(status_code = patch_status)
    }
  }
}

methods <- function(env) vapply(env$reqs, httr2::req_get_method, character(1))

test_that("cz_pin_key defaults to a dry run that only reads", {
  env <- new.env()
  httr2::local_mocked_responses(mock_item(env))
  expect_message(
    res <- cz_pin_key("ABCD2345", "Kent2002", auth = cz_auth("1", "k")),
    "Dry run"
  )
  expect_identical(methods(env), "GET")
  expect_false(res$written)
})

test_that("cz_pin_key writes with the version header, dropping the prefix", {
  env <- new.env()
  httr2::local_mocked_responses(mock_item(env))
  res <- suppressMessages(
    cz_pin_key(
      "1/ABCD2345",
      "Kent2002",
      dry_run = FALSE,
      auth = cz_auth("1", "k")
    )
  )
  expect_identical(methods(env), c("GET", "PATCH"))
  patch <- env$reqs[[2]]
  expect_match(patch$url, "/users/1/items/ABCD2345$")
  expect_identical(patch$headers[["If-Unmodified-Since-Version"]], "7")
  expect_identical(patch$body$data, list(citationKey = "Kent2002"))
  expect_true(res$written)
})

test_that("cz_pin_key refuses to replace a different pinned key unless asked", {
  env <- new.env()
  httr2::local_mocked_responses(mock_item(env, citation_key = "Old2000"))
  expect_error(
    cz_pin_key(
      "ABCD2345",
      "New2020",
      dry_run = FALSE,
      auth = cz_auth("1", "k")
    ),
    "already has the pinned key"
  )
  expect_identical(methods(env), "GET")

  suppressMessages(
    cz_pin_key(
      "ABCD2345",
      "New2020",
      dry_run = FALSE,
      overwrite = TRUE,
      auth = cz_auth("1", "k")
    )
  )
  expect_identical(methods(env), c("GET", "GET", "PATCH"))
})

test_that("cz_pin_key does nothing when the key is already pinned", {
  env <- new.env()
  httr2::local_mocked_responses(mock_item(env, citation_key = "Same2020"))
  expect_message(
    res <- cz_pin_key(
      "ABCD2345",
      "Same2020",
      dry_run = FALSE,
      auth = cz_auth("1", "k")
    ),
    "nothing to do"
  )
  expect_identical(methods(env), "GET") # no PATCH sent
  expect_false(res$written)
})

test_that("a 412 surfaces a clear error", {
  env <- new.env()
  httr2::local_mocked_responses(mock_item(env, patch_status = 412))
  expect_error(
    cz_pin_key(
      "ABCD2345",
      "Kent2002",
      dry_run = FALSE,
      auth = cz_auth("1", "k")
    ),
    "changed in Zotero"
  )
})

test_that("a 403 surfaces a clear error", {
  env <- new.env()
  httr2::local_mocked_responses(mock_item(env, patch_status = 403))
  expect_error(
    cz_pin_key(
      "ABCD2345",
      "Kent2002",
      dry_run = FALSE,
      auth = cz_auth("1", "k")
    ),
    "refused the request"
  )
})

test_that("cz_pin_key accepts a DOI, a citekey, or a cz_find() result", {
  lib <- list(list(
    id = "1/ABCD2345", type = "article-journal", title = "T", DOI = "10.1234/x",
    `citation-key` = "Old2000"
  ))
  env <- new.env()
  item_mock <- mock_item(env, citation_key = "Old2000")
  httr2::local_mocked_responses(function(req) {
    if (grepl("/items/top", req$url, fixed = TRUE)) {
      httr2::response_json(
        headers = list(`Total-Results` = "1"),
        body = list(items = lib)
      )
    } else {
      item_mock(req)
    }
  })
  a <- cz_auth("1", "k")
  for (item in list(
    "10.1234/x",
    "Old2000",
    cz_find(doi = "10.1234/x", items = lib)
  )) {
    env$reqs <- NULL
    suppressMessages(cz_pin_key(item, "New2020", overwrite = TRUE, auth = a))
    expect_match(env$reqs[[1]]$url, "/items/ABCD2345$")
  }
  expect_error(
    cz_pin_key("Nope1999", "X2020", auth = a),
    "No item in the library matches"
  )
})
