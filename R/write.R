#' Pin a citekey onto a Zotero item
#'
#' Sets the item's native `citationKey` field via the Web API (the same field
#' a desktop Better BibTeX install manages), so [cz_item_key()] and
#' [cz_fetch_items()] see it. Requires a key with write access.
#'
#' The default is a dry run: the item is *read* (to get its current version and
#' key) but nothing is written. Set `dry_run = FALSE` to write. The write
#' sends `If-Unmodified-Since-Version`, so if the item changed in the meantime
#' Zotero rejects it (HTTP 412) and nothing is overwritten.
#'
#' @param item The item to pin: a DOI, a Zotero item ID (bare, `"Q62TD7I9"`,
#'   or with the library ID as in CSL-JSON, `"6265773/Q62TD7I9"`), an existing
#'   citekey, or a one-row result of [cz_find()]. Zero or several matches is an
#'   error.
#' @param key The citekey to pin.
#' @param dry_run If `TRUE` (default), report what would change and write
#'   nothing.
#' @param overwrite Replace a *different* key that is already pinned. Defaults
#'   to `FALSE`, because changing a pinned key breaks documents citing it.
#' @inheritParams cz_fetch_items
#' @param cache Passed to [cz_fetch_items()] when `item` is a DOI or citekey
#'   that has to be looked up.
#'
#' @return Invisibly, a list with `item`, `before`, `after` and `written`.
#' @export
#' @examples
#' \dontrun{
#' cz_pin_key("10.1016/0022-5193(64)90038-4", "Hamilton1964") # dry run
#' cz_pin_key("10.1016/0022-5193(64)90038-4", "Hamilton1964", dry_run = FALSE)
#' }
cz_pin_key <- function(
  item,
  key,
  dry_run = TRUE,
  overwrite = FALSE,
  auth = cz_auth(),
  cache = getOption("citezot.cache", FALSE)
) {
  rlang::check_string(key)
  rlang::check_bool(dry_run)
  rlang::check_bool(overwrite)

  item_id <- cz_resolve_item(item, auth, cache = cache)
  current <- cz_get_native(auth, item_id)
  before <- current$data$citationKey
  if (is.null(before)) before <- ""

  if (nzchar(before) && before != key && !overwrite) {
    cli::cli_abort(c(
      "Item {item_id} already has the pinned key {.val {before}}.",
      "i" = "Use {.code overwrite = TRUE} to replace it with {.val {key}} (documents citing {.val {before}} will break)."
    ))
  }

  result <- list(item = item_id, before = before, after = key, written = FALSE)
  if (before == key) {
    cli::cli_inform(c("i" = "Item {item_id} already has the key {.val {key}}; nothing to do."))
    return(invisible(result))
  }

  shown_before <- if (nzchar(before)) before else "<none>"

  if (dry_run) {
    cli::cli_inform(c(
      "i" = "Dry run: nothing written. Use {.code dry_run = FALSE} to apply.",
      "*" = "Item {item_id}: citationKey {.val {shown_before}} -> {.val {key}}"
    ))
    return(invisible(result))
  }

  cz_request(auth, "items", item_id) |>
    httr2::req_method("PATCH") |>
    httr2::req_headers(`If-Unmodified-Since-Version` = as.character(current$version)) |>
    httr2::req_body_json(list(citationKey = key)) |>
    cz_perform()

  cli::cli_inform(c("v" = "Item {item_id}: citationKey {.val {shown_before}} -> {.val {key}}"))
  result$written <- TRUE
  invisible(result)
}
