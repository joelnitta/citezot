test_that("cz_auth reads env vars", {
  withr::local_envvar(ZOTERO_LIBRARY_ID = "123", ZOTERO_USER_ID = "", ZOTERO_API_KEY = "secret")
  a <- cz_auth()
  expect_s3_class(a, "cz_auth")
  expect_equal(a$library_id, "123")
  expect_equal(a$library_type, "user")
})

test_that("ZOTERO_USER_ID is a fallback for user libraries only", {
  withr::local_envvar(ZOTERO_LIBRARY_ID = "", ZOTERO_USER_ID = "55", ZOTERO_API_KEY = "k")
  expect_equal(cz_auth()$library_id, "55")
  expect_error(cz_auth(library_type = "group"), "credentials not found")
  withr::local_envvar(ZOTERO_LIBRARY_ID = "77")
  expect_equal(cz_auth()$library_id, "77")
})

test_that("cz_auth accepts a numeric library id", {
  expect_equal(cz_auth(123, "k")$library_id, "123")
})

test_that("cz_auth errors helpfully when credentials are missing", {
  withr::local_envvar(ZOTERO_LIBRARY_ID = "", ZOTERO_USER_ID = "", ZOTERO_API_KEY = "")
  expect_error(cz_auth(), "credentials not found")
  expect_error(cz_auth("123", ""), "credentials not found")
})

test_that("cz_auth rejects an unknown library type", {
  expect_error(cz_auth("1", "k", library_type = "team"))
})

test_that("printing never shows the API key", {
  a <- cz_auth("123", "super-secret-key")
  msg <- testthat::capture_messages(print(a))
  expect_match(paste(msg, collapse = ""), "123")
  expect_no_match(paste(msg, collapse = ""), "super-secret-key")
})
