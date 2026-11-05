write_file <- function(path, lines) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, path)
  path
}

test_that("cz_front_matter reads YAML and tolerates its absence", {
  d <- withr::local_tempdir()
  f <- write_file(file.path(d, "a.qmd"), c("---", "title: T", "bibliography: refs.bib", "---", "Body"))
  expect_identical(cz_front_matter(f)$bibliography, "refs.bib")
  expect_identical(cz_front_matter(write_file(file.path(d, "b.qmd"), "no front matter")), list())
  expect_identical(cz_front_matter(write_file(file.path(d, "c.qmd"), c("---", "---", "x"))), list())
  expect_identical(cz_front_matter(write_file(file.path(d, "e.qmd"), c("---", "a: [unclosed", "---"))), list())
  expect_identical(cz_front_matter(write_file(file.path(d, "u.qmd"), c("---", "title: x", "x"))), list())
})

test_that("cz_bib_entries keeps only writable bibliography files", {
  expect_identical(cz_bib_entries("a.bib"), "a.bib")
  expect_identical(cz_bib_entries(list("a.bib", "style.csl", "b.yaml", "c.json")), c("a.bib", "b.yaml"))
  expect_identical(cz_bib_entries(NULL), character(0))
})

test_that("cz_doc_bib_paths prefers front matter, resolved from the document", {
  d <- withr::local_tempdir()
  f <- write_file(file.path(d, "sub", "a.qmd"), c("---", "bibliography: refs.bib", "---"))
  expect_identical(cz_doc_bib_paths(f), file.path(normalizePath(file.path(d, "sub")), "refs.bib"))
})

test_that("cz_doc_bib_paths falls back to _quarto.yml, relative to the project", {
  d <- withr::local_tempdir()
  write_file(file.path(d, "_quarto.yml"), c("project:", "  type: default", "bibliography: refs/all.bib"))
  f <- write_file(file.path(d, "chapters", "a.qmd"), c("---", "title: no bib here", "---"))
  expect_identical(cz_doc_bib_paths(f), file.path(normalizePath(d), "refs", "all.bib"))
})

test_that("cz_norm_path gives one spelling for equivalent paths", {
  d <- withr::local_tempdir()
  dir.create(file.path(d, "a"))
  expect_identical(
    cz_norm_path(file.path(d, "a", "..", "a", "x.bib")),
    cz_norm_path(file.path(d, "a", "x.bib"))
  )
})

test_that("cz_doc_bib_paths is empty when nothing declares a bibliography", {
  d <- withr::local_tempdir()
  f <- write_file(file.path(d, "a.qmd"), c("---", "title: x", "---"))
  expect_identical(cz_doc_bib_paths(f), character(0))
})

test_that("cz_project_qmds skips hidden, underscore and tooling directories", {
  d <- withr::local_tempdir()
  for (p in c("a.qmd", "sub/b.Rmd", "_site/c.qmd", ".quarto/d.qmd", "renv/e.qmd", "_partial.qmd", "notes.md")) {
    write_file(file.path(d, p), "x")
  }
  expect_identical(sort(cz_project_qmds(d)), sort(file.path(d, c("a.qmd", "sub/b.Rmd"))))
})
