# The tests must not depend on the user's own citezot options. In particular,
# `options(citezot.cache = TRUE)` in an .Rprofile would make the mocked
# libraries be cached in the user's real cache directory, and later tests
# then read that cache instead of the mock. `R CMD check` does not read the
# .Rprofile, but `devtools::test()` does.
withr::local_options(
  citezot.cache = FALSE,
  citezot.cache_dir = withr::local_tempdir(
    .local_envir = testthat::teardown_env()
  ),
  citezot.base_url = NULL,
  citezot.key_format = NULL,
  citezot.mailto = NULL,
  citezot.max_active = NULL,
  citezot.zotero_profile = NULL,
  .local_envir = testthat::teardown_env()
)
