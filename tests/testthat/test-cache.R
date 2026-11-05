# A stateful fake Zotero library. `env` holds:
#   items   named list key -> list(version, title)
#   version library version
#   trash   keys in the trash; deleted  keys permanently deleted
#   log     every request URL seen
fake_library <- function(env) {
  function(req) {
    env$log <- c(env$log, req$url)
    u <- httr2::url_parse(req$url)
    q <- u$query
    hdrs <- list(`Last-Modified-Version` = as.character(env$version))

    if (grepl("/deleted$", u$path)) {
      return(httr2::response_json(headers = hdrs, body = list(items = as.list(env$deleted))))
    }
    if (grepl("/items/trash$", u$path)) {
      # like Zotero, an empty trash gives an empty body
      body <- if (length(env$trash)) charToRaw(paste(env$trash, collapse = "\n")) else raw()
      return(httr2::response(headers = c(hdrs, list(`Content-Type` = "text/plain")), body = body))
    }

    since <- if (is.null(q$since)) 0 else as.integer(q$since)
    cond <- req$headers[["If-Modified-Since-Version"]]
    if (!is.null(cond) && as.integer(cond) == env$version) {
      return(httr2::response(status_code = 304, headers = hdrs))
    }
    keep <- vapply(names(env$items), function(k) {
      env$items[[k]]$version > since && !k %in% c(env$trash, env$deleted)
    }, logical(1))
    live <- env$items[keep]
    start <- as.integer(q$start)
    idx <- seq_along(live)[seq_along(live) > start & seq_along(live) <= start + as.integer(q$limit)]
    csl <- lapply(names(live)[idx], function(k) {
      list(id = paste0("1/", k), title = live[[k]]$title, `citation-key` = k)
    })
    httr2::response_json(
      headers = c(hdrs, list(`Total-Results` = as.character(length(live)))),
      body = list(items = csl)
    )
  }
}

new_fake <- function(n = 3) {
  env <- new.env()
  env$items <- setNames(
    lapply(seq_len(n), function(i) list(version = i, title = paste("Title", i))),
    paste0("K", seq_len(n))
  )
  env$version <- n
  env$trash <- character()
  env$deleted <- character()
  env$log <- character()
  env
}

keys_of <- function(items) sort(vapply(items, function(i) i$`citation-key`, ""), method = "radix")
auth <- cz_auth("1", "secret-api-key")
n_requests <- function(env) length(env$log)

setup_cache <- function(env = parent.frame()) {
  withr::local_options(citezot.cache_dir = withr::local_tempdir(.local_envir = env), .local_envir = env)
}

test_that("nothing is written to disk unless caching is enabled", {
  setup_cache()
  env <- new_fake()
  httr2::local_mocked_responses(fake_library(env))
  cz_fetch_items(auth)
  expect_length(list.files(cz_cache_dir()), 0)
})

test_that("first cached fetch is a full download and writes the cache", {
  setup_cache()
  env <- new_fake()
  httr2::local_mocked_responses(fake_library(env))
  items <- cz_fetch_items(auth, cache = TRUE)
  expect_equal(keys_of(items), c("K1", "K2", "K3"))
  expect_true(file.exists(cz_cache_file(auth)))
  expect_false(any(grepl("since=", env$log)))
})

test_that("an unchanged library costs a single request", {
  setup_cache()
  env <- new_fake()
  httr2::local_mocked_responses(fake_library(env))
  cz_fetch_items(auth, cache = TRUE)
  env$log <- character()
  items <- cz_fetch_items(auth, cache = TRUE)
  expect_equal(keys_of(items), c("K1", "K2", "K3"))
  expect_equal(n_requests(env), 1)
})

test_that("changes, additions, deletions and trashing are applied incrementally", {
  setup_cache()
  env <- new_fake(5)
  httr2::local_mocked_responses(fake_library(env))
  cz_fetch_items(auth, cache = TRUE)

  env$version <- 10
  env$items$K1$title <- "Edited"
  env$items$K1$version <- 6 # edited
  env$items$K9 <- list(version = 7, title = "New") # added
  env$deleted <- "K2" # permanently deleted
  env$trash <- "K3" # moved to trash

  env$log <- character()
  items <- cz_fetch_items(auth, cache = TRUE)
  expect_equal(keys_of(items), c("K1", "K4", "K5", "K9"))
  titles <- setNames(vapply(items, function(i) i$title, ""), vapply(items, function(i) i$`citation-key`, ""))
  expect_equal(titles[["K1"]], "Edited")
  expect_equal(titles[["K4"]], "Title 4") # untouched item came from cache
  expect_equal(n_requests(env), 3) # changed items, deleted, trash

  # and the cache was updated: next call is a single 304
  env$log <- character()
  cz_fetch_items(auth, cache = TRUE)
  expect_equal(n_requests(env), 1)
})

test_that("an item restored from the trash reappears", {
  setup_cache()
  env <- new_fake(3)
  httr2::local_mocked_responses(fake_library(env))
  env$trash <- "K2"
  expect_equal(keys_of(cz_fetch_items(auth, cache = TRUE)), c("K1", "K3"))
  env$trash <- character()
  env$version <- 8
  env$items$K2$version <- 8
  expect_equal(keys_of(cz_fetch_items(auth, cache = TRUE)), c("K1", "K2", "K3"))
})

test_that("refresh = TRUE ignores the cache", {
  setup_cache()
  env <- new_fake()
  httr2::local_mocked_responses(fake_library(env))
  cz_fetch_items(auth, cache = TRUE)
  env$log <- character()
  cz_fetch_items(auth, cache = TRUE, refresh = TRUE)
  expect_false(any(grepl("since=", env$log)))
})

test_that("a corrupt or foreign cache falls back to a full fetch", {
  setup_cache()
  env <- new_fake()
  httr2::local_mocked_responses(fake_library(env))
  dir.create(cz_cache_dir(), recursive = TRUE, showWarnings = FALSE)
  writeLines("not an rds file", cz_cache_file(auth))
  expect_equal(keys_of(cz_fetch_items(auth, cache = TRUE)), c("K1", "K2", "K3"))

  # valid structure but for a different library -> ignored
  other <- cz_auth("2", "k")
  saveRDS(
    list(schema = 1L, library_id = "999", library_type = "user", version = 1L, items = list()),
    cz_cache_file(other)
  )
  expect_null(cz_cache_read(other))
})

test_that("the cache never contains the API key", {
  setup_cache()
  env <- new_fake()
  httr2::local_mocked_responses(fake_library(env))
  cz_fetch_items(auth, cache = TRUE)
  txt <- rawToChar(serialize(readRDS(cz_cache_file(auth)), NULL, ascii = TRUE))
  expect_false(grepl("secret-api-key", txt, fixed = TRUE))
})

test_that("cz_clear_cache removes only citezot cache files", {
  setup_cache()
  env <- new_fake()
  httr2::local_mocked_responses(fake_library(env))
  cz_fetch_items(auth, cache = TRUE)
  writeLines("keep me", file.path(cz_cache_dir(), "notes.txt"))
  expect_equal(cz_clear_cache(auth), 1)
  expect_false(file.exists(cz_cache_file(auth)))
  cz_fetch_items(auth, cache = TRUE)
  expect_equal(cz_clear_cache(), 1)
  expect_true(file.exists(file.path(cz_cache_dir(), "notes.txt")))
})

test_that("caching can be enabled with an option", {
  setup_cache()
  withr::local_options(citezot.cache = TRUE)
  env <- new_fake()
  httr2::local_mocked_responses(fake_library(env))
  cz_fetch_items(auth)
  expect_true(file.exists(cz_cache_file(auth)))
})
