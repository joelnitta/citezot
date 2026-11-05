#' Zotero credentials
#'
#' Resolves the library ID and API key, by default from the environment
#' variables `ZOTERO_LIBRARY_ID` and `ZOTERO_API_KEY`. Set them once with
#' [cz_set_auth()], or load them yourself (e.g. from a gitignored `.Renviron`
#' or `.env.local`). citezot never reads credential files; only [cz_set_auth()]
#' writes the key, and only when you ask it to. The key is never printed.
#'
#' Create a key at <https://www.zotero.org/settings/keys>; the numeric user ID
#' is on the same page. A read-only key is enough for [cz_fetch_items()]; only
#' functions that change the library need a key with write access.
#'
#' @param library_id Numeric user ID (or group ID), as a string or number.
#'   If `NULL` (default), taken from `ZOTERO_LIBRARY_ID`.
#' @param api_key Zotero API key.
#' @param library_type `"user"` (personal library) or `"group"`.
#'
#' @return A `cz_auth` object, for the `auth` argument of other functions.
#' @export
#' @examples
#' # Explicit values (normally these come from environment variables). The key
#' # is never shown when the object is printed.
#' cz_auth(library_id = "1234567", api_key = "not-a-real-key")
cz_auth <- function(
  library_id = NULL,
  api_key = Sys.getenv("ZOTERO_API_KEY"),
  library_type = c("user", "group")
) {
  library_type <- rlang::arg_match(library_type)
  if (is.null(library_id)) {
    library_id <- Sys.getenv("ZOTERO_LIBRARY_ID")
  }
  library_id <- as.character(library_id)
  bad_id <- length(library_id) != 1 || is.na(library_id) || !nzchar(library_id)
  bad_key <- !rlang::is_string(api_key) || !nzchar(api_key)
  if (bad_id || bad_key) {
    # nolint start: duplicate_argument_linter.
    cli::cli_abort(c(
      "Zotero credentials not found.",
      "i" = paste0(
        "Set {.envvar ZOTERO_LIBRARY_ID} and {.envvar ZOTERO_API_KEY}, or ",
        "pass {.arg library_id} and {.arg api_key}."
      ),
      "i" = "Create a key at {.url https://www.zotero.org/settings/keys}.",
      "i" = "Then save it with {.run citezot::cz_set_auth()}."
    ))
    # nolint end
  }
  structure(
    list(
      library_id = library_id,
      api_key = api_key,
      library_type = library_type
    ),
    class = "cz_auth"
  )
}

#' @export
print.cz_auth <- function(x, ...) {
  cli::cli_text(
    "<cz_auth> {x$library_type} library {x$library_id} (API key hidden)"
  )
  invisible(x)
}

#' Save Zotero credentials to `.Renviron`
#'
#' Prompts for your Zotero user (or group) ID and API key and saves them as
#' `ZOTERO_LIBRARY_ID` and `ZOTERO_API_KEY` in `.Renviron`, so you do not have
#' to edit that file by hand. They also take effect in the current R session
#' right away.
#'
#' The key is deliberately not an argument: values typed as arguments end up
#' in your command history and scripts. Instead, you are prompted. This only
#' works in an interactive session. Note that the prompt is not masked, so the
#' key is visible on screen while you paste it. The key is never printed back.
#' If either variable is already set in the file, you are asked before it is
#' replaced; other lines are left alone.
#'
#' @section Scope:
#' The default, `"user"`, writes to your user-level `~/.Renviron`, which is
#' available in every project and cannot be committed by accident (use
#' `R_ENVIRON_USER` to point R at a different file).
#'
#' `"project"` is for advanced use, such as a different key per project. It
#' writes `.Renviron` in the current working directory, and refuses unless that
#' file is listed in `.gitignore`. R reads only one `.Renviron`, so a project
#' file *replaces* (it is not merged with) your user-level one in that project,
#' hiding any other variables defined there (for example `GITHUB_PAT`).
#' Restart R after saving. citezot does not write `.Rprofile`, which is code,
#' not configuration.
#'
#' @param scope `"user"` (default) or `"project"`; see Scope.
#'
#' @return The path of the file written, invisibly.
#' @seealso [cz_auth()] to check the saved credentials.
#' @export
#' @examplesIf FALSE
#' # Interactive only: prompts for the ID and key.
#' cz_set_auth()
cz_set_auth <- function(scope = c("user", "project")) {
  scope <- rlang::arg_match(scope)
  if (!is_interactive()) {
    cli::cli_abort(c(
      "{.fn cz_set_auth} only works in interactive sessions.",
      "i" = paste0(
        "Add {.envvar ZOTERO_LIBRARY_ID} and {.envvar ZOTERO_API_KEY} to ",
        "your {.file .Renviron} by hand instead."
      )
    ))
  }
  path <- renviron_path(scope)
  library_id <- trimws(prompt_line("Zotero user (or group) ID: "))
  if (!grepl("^[0-9]+$", library_id)) {
    cli::cli_abort("The library ID must be a number, such as {.val 1234567}.")
  }
  api_key <- trimws(prompt_line("Zotero API key: "))
  if (!nzchar(api_key) || grepl("\\s", api_key)) {
    cli::cli_abort("The API key must be a single string with no spaces.")
  }
  vars <- c(ZOTERO_LIBRARY_ID = library_id, ZOTERO_API_KEY = api_key)

  lines <- if (file.exists(path)) readLines(path, warn = FALSE) else character()
  already <- vapply(
    names(vars),
    function(nm) any(grepl(renviron_pattern(nm), lines)),
    logical(1)
  )
  if (any(already) && !isTRUE(ask_yes_no("Replace existing credentials?"))) {
    cli::cli_abort("Left {.path {path}} unchanged.")
  }
  new_file <- !file.exists(path)
  writeLines(set_renviron_vars(lines, vars), path)
  if (new_file && .Platform$OS.type != "windows") {
    Sys.chmod(path, "600")
  }
  do.call(Sys.setenv, as.list(vars))

  cli::cli_inform(c(
    "v" = "Saved Zotero library {library_id} to {.path {path}}.",
    "i" = "Check it with {.run citezot::cz_auth()}."
  ))
  if (scope == "project") {
    cli::cli_inform(c(
      "!" = paste0(
        "In this project R reads only this {.file .Renviron}, not your ",
        "user-level one. Restart R to load it."
      )
    ))
  }
  invisible(path)
}

# Regex for a `NAME=` line in .Renviron.
renviron_pattern <- function(name) {
  paste0("^\\s*", name, "\\s*=")
}

# Replace `NAME=` lines in place, or append the ones that are missing.
set_renviron_vars <- function(lines, vars) {
  for (nm in names(vars)) {
    new <- paste0(nm, "=", vars[[nm]])
    hit <- grepl(renviron_pattern(nm), lines)
    if (any(hit)) {
      lines[hit] <- new
    } else {
      lines <- c(lines, new)
    }
  }
  lines
}

# Where `scope` stores credentials. For "project", also checks that the file
# is git-ignored, before anything is typed or written.
renviron_path <- function(scope) {
  if (scope == "user") {
    custom <- Sys.getenv("R_ENVIRON_USER")
    if (nzchar(custom)) {
      return(path.expand(custom))
    }
    return(path.expand(file.path("~", ".Renviron")))
  }
  ignore <- ".gitignore"
  entries <- if (file.exists(ignore)) {
    trimws(readLines(ignore, warn = FALSE))
  }
  ignored <- any(entries %in% c(".Renviron", "/.Renviron"))
  if (!ignored) {
    cli::cli_abort(c(
      "{.file .Renviron} is not listed in {.file .gitignore}.",
      "i" = "Add it first, so the key cannot be committed by accident."
    ))
  }
  file.path(getwd(), ".Renviron")
}

# Thin wrappers so tests can mock user interaction.
is_interactive <- function() rlang::is_interactive()
prompt_line <- function(prompt) readline(prompt)
ask_yes_no <- function(msg) utils::askYesNo(msg, default = FALSE)
