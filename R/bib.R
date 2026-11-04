#' Write a bibliography file from the references cited in your documents
#'
#' Scans Quarto / R Markdown documents for `@key` citations, looks the keys up
#' among the pinned citekeys in your Zotero library, and writes a bibliography
#' file containing only the cited items. Zotero is the source of truth for the
#' content of each reference; the documents decide which references are needed.
#'
#' Safety: if a key cited in a document is not found in Zotero, the function
#' stops and leaves the existing output file untouched (a bibliography that
#' silently loses entries breaks the render). Set `allow_incomplete = TRUE` to
#' write what was found anyway. Keys found only in `bare` files, and
#' duplicate citekeys in Zotero (the first match is used), give warnings. The
#' file is only rewritten when its content would change, so unchanged
#' bibliographies keep their modification time.
#'
#' @section Output formats:
#' `"bib"` (default) writes BibLaTeX using Zotero's own exporter, with each
#' entry keyed by its pinned citekey; it works with every Quarto output format,
#' including Typst. `"yaml"` writes CSL-YAML (a `references:` list with `id`
#' and `citation-key` set to the citekey). The format is inferred from the
#' extension of `out` (`.bib` or `.yaml`/`.yml`).
#'
#' @param qmd Documents to scan for `@key` citations. Defaults to every
#'   `.qmd` and `.Rmd` file under the working directory, skipping hidden and
#'   underscore-prefixed directories, `renv`, `packrat` and `node_modules`.
#' @param out Bibliography file to write. Defaults to the file named by
#'   `bibliography:` in the documents' YAML front matter (or the project's
#'   `_quarto.yml`), else `references.bib`. If the documents name different
#'   files, `out` must be given.
#' @param format `"bib"` or `"yaml"`; inferred from `out` if `NULL`.
#' @param bare Optional files (e.g. CSVs) scanned for bare citekey-shaped
#'   tokens such as `Ebihara2006`. Missing ones only warn.
#' @param allow_incomplete Write the file even if keys cited in `qmd` are not
#'   found in Zotero.
#' @param auth Credentials from [cz_auth()].
#' @param cache Passed to [cz_fetch_items()]: keep a local copy of the library
#'   so repeat runs are fast. Defaults to `getOption("citezot.cache", FALSE)`.
#' @param quiet Suppress the summary message.
#'
#' @return `out`, invisibly (handy for `targets::tar_target(format = "file")`).
#' @export
#' @examples
#' \dontrun{
#' # reads ZOTERO_LIBRARY_ID / ZOTERO_API_KEY from the environment
#' cz_update_bib("manuscript.qmd")
#' cz_update_bib("manuscript.qmd", out = "references.yaml")
#' }
cz_update_bib <- function(
  qmd = NULL,
  out = NULL,
  format = NULL,
  bare = NULL,
  allow_incomplete = FALSE,
  auth = cz_auth(),
  cache = getOption("citezot.cache", FALSE),
  quiet = FALSE
) {
  force(auth)
  rlang::check_bool(allow_incomplete)
  rlang::check_bool(quiet)
  if (!is.null(out)) rlang::check_string(out)
  if (!is.null(format)) format <- rlang::arg_match(format, c("bib", "yaml"))

  if (is.null(qmd)) qmd <- cz_project_qmds()
  if (!length(qmd)) {
    cli::cli_abort("No {.file .qmd} or {.file .Rmd} files found. Pass them with {.arg qmd}.")
  }
  not_found <- c(qmd, bare)[!file.exists(c(qmd, bare))]
  if (length(not_found)) {
    cli::cli_abort("File{?s} not found: {.file {not_found}}.")
  }

  out <- cz_resolve_out(qmd, out, quiet)
  format <- cz_resolve_format(out, format)
  out_show <- cz_rel_path(out)

  qmd_keys <- cz_collect_keys(qmd, cz_qmd_keys)
  bare_keys <- cz_collect_keys(bare, cz_bare_keys)
  # a key the documents need still counts as required if a bare file mentions it too
  bare_only <- setdiff(bare_keys, qmd_keys)
  cited <- cz_collect_keys(c(qmd_keys, bare_only), identity)

  items <- cz_fetch_items(auth, cache = cache)
  citekeys <- vapply(items, cz_item_key, character(1))
  dupes <- unique(citekeys[duplicated(citekeys) & !is.na(citekeys)])
  dupes <- intersect(dupes, cited)
  if (length(dupes)) {
    cli::cli_warn("Several Zotero items have the same citekey (using the first): {.val {dupes}}.")
  }

  matched <- match(cited, citekeys)
  found <- cited[!is.na(matched)]
  missing <- cited[is.na(matched)]
  missing_qmd <- intersect(missing, qmd_keys)
  missing_bare <- setdiff(missing, qmd_keys)

  if (length(missing_qmd)) {
    if (!allow_incomplete) {
      cli::cli_abort(c(
        "Cited in the documents but not found in Zotero: {.val {missing_qmd}}.",
        "x" = "{.file {out_show}} was NOT touched, because an incomplete bibliography would break the render.",
        "i" = "Pin the citekey in Zotero (see {.fn cz_pin_key}), check the spelling, or use {.code allow_incomplete = TRUE} to write what was found."
      ))
    }
    cli::cli_warn("Cited in the documents but not found in Zotero: {.val {missing_qmd}}. Writing an incomplete bibliography (allow_incomplete = TRUE).")
  }
  if (length(missing_bare)) {
    cli::cli_warn("Mentioned in {.file {bare}} but not found in Zotero: {.val {missing_bare}}.")
  }

  hit <- matched[!is.na(matched)] # item index for each entry of `found`
  text <- if (format == "yaml") {
    cz_render_yaml(items[hit], found)
  } else {
    ids <- vapply(items[hit], function(i) sub("^.*/", "", i$id), character(1))
    paste(cz_export_bib(auth, ids, found), collapse = "\n\n")
  }
  written <- cz_write_if_changed(out, text)

  if (!quiet) {
    cli::cli_inform(c(
      "v" = "{length(found)}/{length(cited)} cited key{?s} found; {.file {out_show}} {if (written) 'updated' else 'already up to date'}.",
      "i" = "{length(qmd_keys)} from {length(qmd)} document{?s}, {length(bare_only)} only in other files."
    ))
  }
  invisible(out)
}

# `path` relative to the working directory when it lies inside it (for
# readable messages); otherwise unchanged.
cz_rel_path <- function(path) {
  wd <- normalizePath(getwd(), mustWork = FALSE)
  p <- cz_norm_path(path)
  prefix <- paste0(wd, "/")
  if (startsWith(p, prefix)) substring(p, nchar(prefix) + 1) else path
}

# Sorted unique keys from applying `fn` to each path (character(0) if none).
cz_collect_keys <- function(paths, fn) {
  keys <- as.character(unlist(lapply(paths, fn)))
  sort(unique(keys), method = "radix")
}

# Where to write: explicit `out`, else the single bibliography file the
# documents declare, else references.bib.
cz_resolve_out <- function(qmd, out, quiet = FALSE) {
  if (!is.null(out)) {
    return(out)
  }
  declared <- unique(unlist(lapply(qmd, cz_doc_bib_paths)))
  if (length(declared) > 1) {
    cli::cli_abort(c(
      "The documents declare different bibliography files: {.file {declared}}.",
      "i" = "Say which one to write with {.arg out}."
    ))
  }
  if (length(declared) == 1) {
    return(declared)
  }
  if (!quiet) {
    cli::cli_inform("No {.code bibliography:} found in the documents; writing {.file references.bib}.")
  }
  "references.bib"
}

cz_resolve_format <- function(out, format) {
  ext <- tolower(tools::file_ext(out))
  from_ext <- switch(ext, bib = , bibtex = "bib", yaml = , yml = "yaml", NA_character_)
  if (is.null(format)) {
    if (is.na(from_ext)) {
      cli::cli_abort(c(
        "Can't tell the output format from {.file {out}}.",
        "i" = "Use a {.code .bib}, {.code .yaml} or {.code .yml} file name, or set {.arg format}."
      ))
    }
    return(from_ext)
  }
  if (!is.na(from_ext) && from_ext != format) {
    cli::cli_abort("{.arg format} is {.val {format}} but {.file {out}} looks like {.val {from_ext}}.")
  }
  format
}

# CSL-YAML for the chosen items: the pinned key becomes both `id` and
# `citation-key`; the key line is dropped from the note (Extra) field.
cz_render_yaml <- function(items, keys) {
  items <- Map(function(item, key) {
    item$note <- cz_strip_key_line(item$note)
    item$id <- key
    item[["citation-key"]] <- key
    item
  }, items, keys)
  items <- unname(items[order(keys, method = "radix")])
  paste0("---\n", yaml::as.yaml(list(references = items), indent.mapping.sequence = TRUE))
}

# Write `text` (plus a final newline) to `path` as UTF-8, only if it differs
# from what is there. Writes to a temporary file and renames, so a failure
# never leaves a half-written bibliography. Returns TRUE if the file changed.
cz_write_if_changed <- function(path, text) {
  new <- charToRaw(enc2utf8(paste0(sub("\n+$", "", text), "\n")))
  if (file.exists(path)) {
    old <- readBin(path, "raw", file.size(path))
    if (identical(old, new)) {
      return(FALSE)
    }
  }
  if (!dir.exists(dirname(path))) {
    cli::cli_abort("Directory {.file {dirname(path)}} does not exist.")
  }
  tmp <- tempfile(pattern = ".citezot-", tmpdir = dirname(path))
  on.exit(unlink(tmp), add = TRUE)
  writeBin(new, tmp)
  file.rename(tmp, path)
  TRUE
}
