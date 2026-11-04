test_that("a Backoff header pauses before the next request", {
  slept <- numeric()
  testthat::local_mocked_bindings(cz_sleep = function(seconds) slept <<- c(slept, seconds))
  .cz_state$backoff_until <- NULL
  calls <- 0
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1
    httr2::response_json(headers = if (calls == 1) list(Backoff = "5") else list(), body = list())
  })
  a <- cz_auth("1", "k")
  suppressMessages({
    cz_perform(cz_request(a, "items"))
    expect_length(slept, 0) # no pause before the request that triggered it
    cz_perform(cz_request(a, "items"))
  })
  expect_length(slept, 1)
  expect_gt(slept, 3)
  expect_lte(slept, 5)
  # and the pause is consumed: a third request does not wait again
  suppressMessages(cz_perform(cz_request(a, "items")))
  expect_length(slept, 1)
})

test_that("an absurd Backoff is capped", {
  testthat::local_mocked_bindings(cz_sleep = function(seconds) NULL)
  .cz_state$backoff_until <- NULL
  cz_note_backoff(httr2::response(headers = list(Backoff = "100000")))
  expect_lte(as.numeric(difftime(.cz_state$backoff_until, Sys.time(), units = "secs")), 300)
  .cz_state$backoff_until <- NULL
})

test_that("a response without Backoff sets no pause", {
  .cz_state$backoff_until <- NULL
  cz_note_backoff(httr2::response(headers = list()))
  expect_null(.cz_state$backoff_until)
})
