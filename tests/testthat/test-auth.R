test_that("cz_auth reads env vars", {
  withr::local_envvar(
    ZOTERO_LIBRARY_ID = "123",
    ZOTERO_API_KEY = "secret"
  )
  a <- cz_auth()
  expect_s3_class(a, "cz_auth")
  expect_identical(a$library_id, "123")
  expect_identical(a$library_type, "user")
})

test_that("cz_auth reads a group library id from the same variable", {
  withr::local_envvar(ZOTERO_LIBRARY_ID = "77", ZOTERO_API_KEY = "k")
  a <- cz_auth(library_type = "group")
  expect_identical(a$library_id, "77")
  expect_identical(a$library_type, "group")
})

test_that("cz_auth accepts a numeric library id", {
  expect_identical(cz_auth(123, "k")$library_id, "123")
})

test_that("cz_auth errors helpfully when credentials are missing", {
  withr::local_envvar(
    ZOTERO_LIBRARY_ID = "",
    ZOTERO_API_KEY = ""
  )
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

# cz_set_auth() ---------------------------------------------------------------

local_set_auth <- function(
  answers,
  yes = TRUE,
  file = withr::local_tempfile(),
  .env = parent.frame()
) {
  withr::local_envvar(
    R_ENVIRON_USER = file,
    ZOTERO_LIBRARY_ID = "",
    ZOTERO_API_KEY = "",
    .local_envir = .env
  )
  queue <- rlang::env(answers = answers)
  testthat::local_mocked_bindings(
    is_interactive = function() TRUE,
    prompt_line = function(prompt) {
      out <- queue$answers[[1]]
      queue$answers <- queue$answers[-1]
      out
    },
    ask_yes_no = function(msg) yes,
    .env = .env
  )
  file
}

test_that("cz_set_auth creates the file and sets the session", {
  file <- local_set_auth(list("123", "secret-key"))
  expect_message(path <- cz_set_auth(), "Saved Zotero library 123")
  expect_identical(path, file)
  expect_setequal(
    readLines(file),
    c("ZOTERO_LIBRARY_ID=123", "ZOTERO_API_KEY=secret-key")
  )
  expect_identical(cz_auth()$library_id, "123")
})

test_that("cz_set_auth appends and keeps other lines", {
  file <- withr::local_tempfile(lines = c("GITHUB_PAT=abc", "FOO=bar"))
  local_set_auth(list("1", "k"), file = file)
  suppressMessages(cz_set_auth())
  expect_identical(
    readLines(file),
    c("GITHUB_PAT=abc", "FOO=bar", "ZOTERO_LIBRARY_ID=1", "ZOTERO_API_KEY=k")
  )
})

test_that("cz_set_auth replaces existing values only when confirmed", {
  old <- c("ZOTERO_API_KEY=old", "ZOTERO_LIBRARY_ID=9", "FOO=bar")
  file <- withr::local_tempfile(lines = old)
  local_set_auth(list("1", "new"), yes = FALSE, file = file)
  expect_error(cz_set_auth(), "unchanged")
  expect_identical(readLines(file), old)

  local_set_auth(list("1", "new"), yes = TRUE, file = file)
  suppressMessages(cz_set_auth())
  expect_identical(
    readLines(file),
    c("ZOTERO_API_KEY=new", "ZOTERO_LIBRARY_ID=1", "FOO=bar")
  )
})

test_that("cz_set_auth validates input and needs an interactive session", {
  local_set_auth(list("abc", "k"))
  expect_error(cz_set_auth(), "must be a number")
  local_set_auth(list("1", "has space"))
  expect_error(cz_set_auth(), "no spaces")
  testthat::local_mocked_bindings(is_interactive = function() FALSE)
  expect_error(cz_set_auth(), "interactive")
})

test_that("cz_set_auth never prints the key", {
  local_set_auth(list("1", "super-secret-key"))
  msg <- paste(testthat::capture_messages(cz_set_auth()), collapse = "")
  expect_no_match(msg, "super-secret-key")
})

test_that("project scope needs .Renviron in .gitignore", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  local_set_auth(list("1", "k"))
  expect_error(cz_set_auth("project"), "not listed")
  writeLines(c("*.log", ".Renviron"), ".gitignore")
  expect_message(cz_set_auth("project"), "only this")
  expect_true(file.exists(file.path(dir, ".Renviron")))
})
