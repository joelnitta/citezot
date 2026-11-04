# Mock a single item: GET returns it, PATCH returns `patch_status`.
mock_item <- function(env, citation_key = "", patch_status = 204) {
  function(req) {
    env$reqs <- c(env$reqs, list(req))
    if (httr2::req_get_method(req) == "GET") {
      httr2::response_json(
        body = list(key = "ABC12345", version = 7, data = list(citationKey = citation_key))
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
    res <- cz_pin_key("ABC12345", "Kent2002", auth = cz_auth("1", "k")),
    "Dry run"
  )
  expect_equal(methods(env), "GET")
  expect_false(res$written)
})

test_that("cz_pin_key writes with the version header and strips library prefix", {
  env <- new.env()
  httr2::local_mocked_responses(mock_item(env))
  res <- suppressMessages(
    cz_pin_key("1/ABC12345", "Kent2002", dry_run = FALSE, auth = cz_auth("1", "k"))
  )
  expect_equal(methods(env), c("GET", "PATCH"))
  patch <- env$reqs[[2]]
  expect_match(patch$url, "/users/1/items/ABC12345$")
  expect_equal(patch$headers[["If-Unmodified-Since-Version"]], "7")
  expect_equal(patch$body$data, list(citationKey = "Kent2002"))
  expect_true(res$written)
})

test_that("cz_pin_key refuses to replace a different pinned key unless asked", {
  env <- new.env()
  httr2::local_mocked_responses(mock_item(env, citation_key = "Old2000"))
  expect_error(
    cz_pin_key("ABC12345", "New2020", dry_run = FALSE, auth = cz_auth("1", "k")),
    "already has the pinned key"
  )
  expect_equal(methods(env), "GET")

  suppressMessages(
    cz_pin_key("ABC12345", "New2020", dry_run = FALSE, overwrite = TRUE, auth = cz_auth("1", "k"))
  )
  expect_equal(methods(env), c("GET", "GET", "PATCH"))
})

test_that("cz_pin_key re-pinning the same key is allowed", {
  env <- new.env()
  httr2::local_mocked_responses(mock_item(env, citation_key = "Same2020"))
  expect_no_error(suppressMessages(
    cz_pin_key("ABC12345", "Same2020", auth = cz_auth("1", "k"))
  ))
})

test_that("a 412 surfaces a clear error", {
  env <- new.env()
  httr2::local_mocked_responses(mock_item(env, patch_status = 412))
  expect_error(
    cz_pin_key("ABC12345", "Kent2002", dry_run = FALSE, auth = cz_auth("1", "k")),
    "changed in Zotero"
  )
})

test_that("a 403 surfaces a clear error", {
  env <- new.env()
  httr2::local_mocked_responses(mock_item(env, patch_status = 403))
  expect_error(
    cz_pin_key("ABC12345", "Kent2002", dry_run = FALSE, auth = cz_auth("1", "k")),
    "refused the request"
  )
})
