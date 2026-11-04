write_tmp <- function(lines, ext = ".qmd") {
  f <- withr::local_tempfile(fileext = ext, .local_envir = parent.frame())
  writeLines(lines, f)
  f
}

test_that("cz_qmd_keys ignores code fences", {
  f <- write_tmp(c("Text @Real2020.", "```{r}", "x@slot <- @Fake2021", "```"))
  expect_equal(cz_qmd_keys(f), "Real2020")
})

test_that("cz_qmd_keys drops cross-refs, keeps periods inside keys", {
  f <- write_tmp("See @fig-a, @tbl-b and @eq-c; also @WatkinsJr.2012 and @Foo2020.")
  expect_equal(cz_qmd_keys(f), c("Foo2020", "WatkinsJr.2012"))
})

test_that("cz_qmd_keys ignores emails", {
  f <- write_tmp("Contact joel@example.com or cite @Ok2019.")
  expect_equal(cz_qmd_keys(f), "Ok2019")
})

test_that("cz_qmd_keys cross-ref prefixes are configurable", {
  f <- write_tmp("@fig-a @myref-b @Real2020")
  expect_equal(cz_qmd_keys(f, crossref_prefixes = "myref"), c("Real2020", "fig-a"))
})

test_that("cz_bare_keys matches key shapes only", {
  f <- write_tmp(
    "Ebihara2006, Boucheron-Dubuisson2024; Dubuisson2013a; Hsu7949; Ebihara 2006",
    ".csv"
  )
  expect_equal(
    cz_bare_keys(f),
    c("Boucheron-Dubuisson2024", "Dubuisson2013a", "Ebihara2006")
  )
})

test_that("cz_item_key prefers native field, falls back to note, else NA", {
  expect_equal(
    cz_item_key(list(`citation-key` = "Native2020", note = "Citation Key: Old2020")),
    "Native2020"
  )
  expect_equal(cz_item_key(list(note = "foo\nCitation Key: Old2020")), "Old2020")
  expect_true(is.na(cz_item_key(list(note = "just a note"))))
  expect_true(is.na(cz_item_key(list())))
})

test_that("cz_strip_key_line keeps other content, NULL when empty", {
  expect_equal(cz_strip_key_line("keep me\nCitation Key: A2020"), "keep me")
  expect_null(cz_strip_key_line("Citation Key: A2020"))
  expect_null(cz_strip_key_line(NULL))
})

test_that("keys with non-ASCII letters are kept whole", {
  f <- write_tmp("See @Weiß2015, @Tjørve2008; @Ramírez-Barahona2020 and @Øllgaard2015.")
  expect_equal(
    cz_qmd_keys(f),
    sort(c("Weiß2015", "Tjørve2008", "Ramírez-Barahona2020", "Øllgaard2015"), method = "radix")
  )
})

test_that("cz_bare_keys handles non-ASCII author names", {
  f <- write_tmp("defined in Weiß2015 and Sønstebø2010a", ".csv")
  expect_equal(cz_bare_keys(f), c("Sønstebø2010a", "Weiß2015"))
})
