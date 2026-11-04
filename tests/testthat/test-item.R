native_item <- function(...) {
  data <- list(
    key = "ABCD2345", version = 7, itemType = "journalArticle",
    title = "A {braced} title", date = "2020", DOI = "10.1234/abc", extra = "",
    citationKey = "Kent2002",
    creators = list(list(creatorType = "author", firstName = "W", lastName = "Kent")),
    tags = list(list(tag = "fern")), collections = list(), relations = setNames(list(), character(0))
  )
  mods <- list(...)
  data[names(mods)] <- mods
  list(key = "ABCD2345", version = 7, data = data)
}

mock_native <- function(env, item = native_item(), patch_status = 204) {
  function(req) {
    env$reqs <- c(env$reqs, list(req))
    if (httr2::req_get_method(req) == "GET") {
      httr2::response_json(body = item)
    } else {
      httr2::response(status_code = patch_status)
    }
  }
}
a <- cz_auth("1", "k")
meths <- function(env) vapply(env$reqs, httr2::req_get_method, character(1))
patch_body <- function(env) env$reqs[[length(env$reqs)]]$body$data

test_that("cz_get_item returns the native item with its version", {
  env <- new.env(); httr2::local_mocked_responses(mock_native(env))
  it <- cz_get_item("ABCD2345", auth = a)
  expect_equal(it$version, 7)
  expect_equal(it$data$DOI, "10.1234/abc")
})

test_that("cz_update_item is a dry run by default and writes nothing", {
  env <- new.env(); httr2::local_mocked_responses(mock_native(env))
  msgs <- testthat::capture_messages(
    res <- cz_update_item("ABCD2345", list(date = "in press"), auth = a)
  )
  expect_equal(meths(env), "GET")
  expect_false(res$written)
  expect_equal(res$changes$date, list(before = "2020", after = "in press"))
  txt <- paste(msgs, collapse = "")
  expect_match(txt, "Dry run")
  expect_match(txt, "2020")
  expect_match(txt, "in press")
  expect_match(txt, "{braced}", fixed = TRUE) # braces in titles don't break cli
})

test_that("a live update sends only changed fields with the version header", {
  env <- new.env(); httr2::local_mocked_responses(mock_native(env))
  res <- suppressMessages(cz_update_item(
    "ABCD2345", list(date = "in press", DOI = "10.1234/abc", title = "New"),
    dry_run = FALSE, auth = a
  ))
  expect_equal(meths(env), c("GET", "PATCH"))
  patch <- env$reqs[[2]]
  expect_equal(patch$headers[["If-Unmodified-Since-Version"]], "7")
  expect_equal(patch_body(env), list(date = "in press", title = "New")) # DOI unchanged -> not sent
  expect_true(res$written)
})

test_that("nothing is sent when no value changes", {
  env <- new.env(); httr2::local_mocked_responses(mock_native(env))
  expect_message(
    res <- cz_update_item("ABCD2345", list(date = "2020"), dry_run = FALSE, auth = a),
    "nothing to change"
  )
  expect_equal(meths(env), "GET")
  expect_false(res$written)
})

test_that("array fields are replaced as a whole", {
  env <- new.env(); httr2::local_mocked_responses(mock_native(env))
  suppressMessages(cz_update_item(
    "ABCD2345", list(tags = list(list(tag = "fern"), list(tag = "new"))),
    dry_run = FALSE, auth = a
  ))
  expect_equal(patch_body(env)$tags, list(list(tag = "fern"), list(tag = "new")))
  # same tags in a different element order do not count as a change
  env$reqs <- NULL
  res <- suppressMessages(cz_update_item("ABCD2345", list(tags = list(list(tag = "fern"))), dry_run = FALSE, auth = a))
  expect_false(res$written)
})

test_that("protected and unknown fields are rejected with guidance, before any write", {
  env <- new.env(); httr2::local_mocked_responses(mock_native(env))
  expect_error(cz_update_item("ABCD2345", list(citationKey = "X"), auth = a), "cz_pin_key")
  expect_error(cz_update_item("ABCD2345", list(version = 9), auth = a), "version")
  expect_error(cz_update_item("ABCD2345", list(itemType = "book"), auth = a), "itemType")
  expect_error(cz_update_item("ABCD2345", list(ISBN = "123"), dry_run = FALSE, auth = a), "Not a field")
  expect_false("PATCH" %in% meths(env))
})

test_that("bad field values are rejected before any request", {
  env <- new.env(); httr2::local_mocked_responses(mock_native(env))
  expect_error(cz_update_item("ABCD2345", list(date = NULL), auth = a), "single string")
  expect_error(cz_update_item("ABCD2345", list(date = c("a", "b")), auth = a), "single string")
  expect_error(cz_update_item("ABCD2345", list(date = NA_character_), auth = a), "single string")
  expect_error(cz_update_item("ABCD2345", list(tags = "fern"), auth = a), "must be a list")
  expect_error(cz_update_item("ABCD2345", list("x"), auth = a), "named list")
  expect_error(cz_update_item("ABCD2345", list(), auth = a), "named list")
  expect_error(cz_update_item("ABCD2345", list(date = "a", date = "b"), auth = a), "duplicated")
  expect_length(env$reqs, 0)
})

test_that("numbers are sent as strings and fields can be cleared with an empty string", {
  env <- new.env(); httr2::local_mocked_responses(mock_native(env))
  suppressMessages(cz_update_item("ABCD2345", list(date = 2021, DOI = ""), dry_run = FALSE, auth = a))
  expect_equal(patch_body(env), list(date = "2021", DOI = ""))
})

test_that("a version conflict surfaces a clear error", {
  env <- new.env(); httr2::local_mocked_responses(mock_native(env, patch_status = 412))
  expect_error(
    cz_update_item("ABCD2345", list(date = "x"), dry_run = FALSE, auth = a),
    "changed in Zotero"
  )
})
