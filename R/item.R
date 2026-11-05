# One item in Zotero's native JSON: list(key, version, library, links, meta, data)
cz_get_native <- function(auth, id) {
  cz_request(auth, "items", id) |>
    cz_perform() |>
    httr2::resp_body_json(simplifyVector = FALSE)
}

#' Get one item in Zotero's native JSON
#'
#' Returns the item as Zotero stores it (not CSL-JSON): writable fields are in
#' `$data`, and `$version` is the item version used for safe updates.
#'
#' @param item The item: a DOI, Zotero item ID, citekey, or one-row result of
#'   [cz_find()] (see [cz_pin_key()]).
#' @inheritParams cz_fetch_items
#' @param cache Passed to [cz_fetch_items()] when `item` has to be looked up.
#'
#' @return A list with `key`, `version`, `data` and other API fields.
#' @export
#' @examples
#' \dontrun{
#' item <- cz_get_item("Darwin1859")
#' item$data$title
#' item$version
#' }
cz_get_item <- function(item, auth = cz_auth(), cache = getOption("citezot.cache", FALSE)) {
  cz_get_native(auth, cz_resolve_item(item, auth, cache = cache))
}

# Fields that cz_update_item() refuses to touch, with the reason.
cz_protected_fields <- c(
  key = "is the item's identity",
  version = "is managed by Zotero",
  itemType = "can't be changed in place",
  dateAdded = "is managed by Zotero",
  dateModified = "is managed by Zotero",
  deleted = "(trash) is not supported",
  parentItem = "is not supported",
  citationKey = "should be changed with cz_pin_key(), which protects pinned keys"
)

# Fields whose value is a list. Zotero replaces these wholesale on update.
cz_array_fields <- c("creators", "tags", "collections", "relations")

# Recursively sort names so equal lists compare equal whatever their order.
cz_canon <- function(x) {
  if (is.list(x)) {
    x <- lapply(x, cz_canon)
    if (!is.null(names(x))) x <- x[order(names(x), method = "radix")]
  }
  x
}

# Short human-readable form of a field value for the before/after display.
cz_show_value <- function(x, width = 70) {
  txt <- if (is.list(x)) {
    if (length(x)) {
      parts <- lapply(x, function(e) paste(unlist(e), collapse = " "))
      paste(unlist(parts), collapse = "; ")
    } else {
      ""
    }
  } else {
    as.character(x)
  }
  txt <- gsub("\\s+", " ", txt)
  if (nchar(txt) > width) paste0(substr(txt, 1, width - 1), "\u2026") else txt
}

# Escape braces so cli does not treat user text as glue
cz_cli_escape <- function(x) {
  gsub("}", "}}", gsub("{", "{{", x, fixed = TRUE), fixed = TRUE)
}

#' Update fields of a Zotero item
#'
#' Changes selected fields of one item and shows exactly what will change. The
#' default is a dry run: the item is read and a before/after diff is shown, but
#' nothing is written. Use `dry_run = FALSE` to write.
#'
#' Only fields whose value actually changes are sent (a PATCH), together with
#' `If-Unmodified-Since-Version`: if the item was edited elsewhere since it was
#' read, Zotero rejects the write (HTTP 412) and nothing is overwritten.
#'
#' Plain fields take a single string (use `""` to clear one). `creators`,
#' `tags`, `collections` and `relations` take lists and are **replaced as a
#' whole**, so to add one tag pass the full list of tags. Identity and
#' bookkeeping fields (`key`, `version`, `itemType`, dates, `parentItem`,
#' `deleted`) can't be changed, and the citekey is changed with [cz_pin_key()].
#'
#' @param item The item: a DOI, Zotero item ID, citekey, or one-row result of
#'   [cz_find()].
#' @param fields A named list of new values, e.g.
#'   `list(date = "in press", DOI = "10.1234/abc")`. Names must be fields that
#'   exist for the item's type; see `names(cz_get_item(item)$data)`.
#' @param dry_run If `TRUE` (default), show the diff and write nothing.
#' @inheritParams cz_add
#' @param cache Passed to [cz_fetch_items()] when `item` has to be looked up.
#'
#' @return Invisibly, a list with `item`, `changes` (for each changed field,
#'   its `before` and `after`) and `written`.
#' @export
#' @examples
#' \dontrun{
#' cz_update_item("Regnier2024", list(date = "in press")) # preview
#' cz_update_item("Regnier2024", list(date = "in press"), dry_run = FALSE) # write
#' }
cz_update_item <- function(
  item,
  fields,
  dry_run = TRUE,
  auth = cz_auth(),
  cache = getOption("citezot.cache", FALSE)
) {
  rlang::check_bool(dry_run)
  if (!is.list(fields) || !length(fields) || is.null(names(fields)) || !all(nzchar(names(fields)))) {
    cli::cli_abort("{.arg fields} must be a non-empty named list, e.g. {.code list(date = \"in press\")}.")
  }
  if (anyDuplicated(names(fields))) {
    cli::cli_abort("{.arg fields} has duplicated names.")
  }
  bad <- intersect(names(fields), names(cz_protected_fields))
  if (length(bad)) {
    cli::cli_abort(c(
      "Can't update {.field {bad}} here.",
      stats::setNames(sprintf("%s %s", bad, cz_protected_fields[bad]), rep("i", length(bad)))
    ))
  }
  # validate shapes before any request
  for (nm in names(fields)) {
    v <- fields[[nm]]
    if (nm %in% cz_array_fields) {
      if (!is.list(v)) cli::cli_abort("{.field {nm}} must be a list (it is replaced as a whole).")
    } else if (is.null(v) || length(v) != 1 || is.list(v) || is.na(v) || !(is.character(v) || is.numeric(v))) {
      cli::cli_abort("{.field {nm}} must be a single string (use {.code \"\"} to clear it).")
    }
  }

  id <- cz_resolve_item(item, auth, cache = cache)
  current <- cz_get_native(auth, id)
  data <- current$data
  unknown <- setdiff(names(fields), names(data))
  if (length(unknown)) {
    cli::cli_abort(c(
      "Not a field of this item's type ({.val {data$itemType}}): {.field {unknown}}.",
      "i" = "Valid fields: {.field {setdiff(names(data), names(cz_protected_fields))}}."
    ))
  }

  fields <- Map(function(nm, v) if (nm %in% cz_array_fields) v else as.character(v), names(fields), fields)
  changed <- Filter(function(nm) {
    !identical(cz_canon(data[[nm]]), cz_canon(fields[[nm]]))
  }, names(fields))
  changes <- stats::setNames(lapply(changed, function(nm) list(before = data[[nm]], after = fields[[nm]])), changed)
  result <- list(item = id, changes = changes, written = FALSE)

  title <- cz_cli_escape(cz_show_value(data$title, 50))
  if (!length(changes)) {
    cli::cli_inform(c("i" = "Item {id} ({title}): nothing to change."))
    return(invisible(result))
  }
  lines <- vapply(changed, function(nm) {
    cz_cli_escape(sprintf(
      "%s: %s -> %s", nm,
      encodeString(cz_show_value(changes[[nm]]$before), quote = "\""),
      encodeString(cz_show_value(changes[[nm]]$after), quote = "\"")
    ))
  }, character(1))
  diff <- stats::setNames(lines, rep("*", length(lines)))

  if (dry_run) {
    cli::cli_inform(c("i" = "Dry run: nothing written. Use {.code dry_run = FALSE} to apply to item {id} ({title}).", diff))
    return(invisible(result))
  }

  cz_request(auth, "items", id) |>
    httr2::req_method("PATCH") |>
    httr2::req_headers(`If-Unmodified-Since-Version` = as.character(current$version)) |>
    httr2::req_body_json(lapply(changes, function(ch) ch$after), auto_unbox = TRUE) |>
    cz_perform()

  cli::cli_inform(c("v" = "Updated item {id} ({title}).", diff))
  result$written <- TRUE
  invisible(result)
}
