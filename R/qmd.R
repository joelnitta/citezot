# Helpers for finding Quarto / R Markdown documents and the bibliography file
# they point to. All internal.

# YAML front matter of a qmd/Rmd as a list (empty list if none/unparseable).
cz_front_matter <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  if (!length(lines) || !grepl("^---\\s*$", lines[1])) {
    return(list())
  }
  close <- which(grepl("^(---|\\.\\.\\.)\\s*$", lines[-1]))[1] + 1
  if (is.na(close) || close == 2) {
    return(list())
  }
  meta <- tryCatch(
    yaml::yaml.load(paste(lines[2:(close - 1)], collapse = "\n")),
    error = function(e) NULL
  )
  if (is.list(meta)) meta else list()
}

# The bibliography files in a `bibliography:` field that citezot can write
# (.bib/.bibtex/.yaml/.yml), whether given as a string or a list.
cz_bib_entries <- function(x) {
  x <- as.character(unlist(x))
  x[grepl("\\.(bib|bibtex|ya?ml)$", x, ignore.case = TRUE)]
}

# Nearest _quarto.yml (or .yaml) in `dir` or one of its parents, or NULL.
cz_quarto_yml <- function(dir) {
  dir <- normalizePath(dir, mustWork = FALSE)
  for (i in 1:10) {
    for (nm in c("_quarto.yml", "_quarto.yaml")) {
      f <- file.path(dir, nm)
      if (file.exists(f)) {
        return(f)
      }
    }
    parent <- dirname(dir)
    if (identical(parent, dir)) break
    dir <- parent
  }
  NULL
}

# Path(s) of the bibliography file a document declares: its own front matter
# first, else the project's _quarto.yml (resolved relative to that file's
# directory, as Quarto does). character(0) if none.
cz_doc_bib_paths <- function(qmd) {
  paths <- cz_bib_entries(cz_front_matter(qmd)$bibliography)
  base <- dirname(qmd)
  if (!length(paths)) {
    qy <- cz_quarto_yml(dirname(qmd))
    if (!is.null(qy)) {
      meta <- tryCatch(yaml::read_yaml(qy), error = function(e) list())
      paths <- cz_bib_entries(meta$bibliography)
      base <- dirname(qy)
    }
  }
  if (!length(paths)) {
    return(character(0))
  }
  absolute <- grepl("^(/|~|[A-Za-z]:)", paths)
  paths[!absolute] <- file.path(base, paths[!absolute])
  cz_norm_path(paths)
}

# Canonical spelling of a (possibly not yet existing) file path: resolve the
# directory, which normalizePath() does consistently, and keep the file name.
cz_norm_path <- function(path) {
  file.path(normalizePath(dirname(path), mustWork = FALSE), basename(path))
}

# All .qmd/.Rmd files under `dir`, skipping hidden or underscore-prefixed
# directories (_site, _freeze, .quarto, ...) and renv/packrat/node_modules.
cz_project_qmds <- function(dir = ".") {
  rel <- list.files(dir, pattern = "\\.(qmd|Rmd)$", recursive = TRUE)
  skip_dir <- function(p) {
    parts <- strsplit(p, "/", fixed = TRUE)[[1]]
    dirs <- parts[-length(parts)]
    any(grepl("^[._]", dirs) | dirs %in% c("renv", "packrat", "node_modules"))
  }
  rel <- rel[!vapply(rel, skip_dir, logical(1))]
  # files that start with "_" are Quarto partials, not documents
  rel <- rel[!grepl("^_", basename(rel))]
  if (identical(dir, ".")) rel else file.path(dir, rel)
}
