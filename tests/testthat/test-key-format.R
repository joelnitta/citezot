native <- function(title, family = "Smith", date = "2020", ...) {
  list(
    itemType = "journalArticle", title = title, date = date,
    creators = c(list(list(creatorType = "author", firstName = "A", lastName = family)), list(...))
  )
}
csl <- function(title, family = "Smith", year = 2020) {
  list(title = title, author = list(list(family = family, given = "A.")), issued = list(`date-parts` = list(list(year))))
}
fmt_1 <- "auth.lower + year + shorttitle(1).lower"
key <- function(item, formula = fmt_1, ...) cz_suggest_key(item, formula, ...)

# --- parsing ------------------------------------------------------------------
test_that("unsupported formula syntax is an error that says what is supported", {
  expect_error(key(native("T"), "auth || title"), "alternatives")
  expect_error(key(native("T"), "[auth][year]"), "old")
  expect_error(key(native("T"), "auth.lower; year"), "alternatives")
  expect_error(key(native("T"), "auth + journal"), "function `journal`")
  expect_error(key(native("T"), "auth.reverse"), "filter `reverse`")
  expect_error(key(native("T"), "auth +  + year"), "empty term")
  expect_error(key(native("T"), "shorttitle(x)"), "arguments")
  expect_error(key(native("T"), "auth + "), "empty term")
  expect_error(key(native("T"), "auth.lower"), NA)
})

test_that("literals and '+' inside quotes are handled", {
  expect_identical(key(native("T", "Kent"), "auth.lower + '_' + year"), "kent_2020")
  expect_identical(key(native("T", "Kent"), "auth.lower + '+' + year"), "kent+2020") # '+' is a legal key character
  expect_identical(key(native("T", "Kent"), "\"x\" + auth.lower"), "xkent")
})

# --- auth ----------------------------------------------------------------------
test_that("auth uses the first author's last name, spaces removed", {
  expect_identical(key(native("T", "De Kort"), "auth.lower"), "dekort")
  expect_identical(key(native("T", "Poinar Jr"), "auth.lower"), "poinarjr")
  expect_identical(key(native("T", "Smith"), "auth"), "Smith")
  expect_identical(key(native("T", "Smith"), "auth.upper"), "SMITH")
})

test_that("accents are folded to ASCII and Unicode hyphens become hyphens", {
  expect_identical(key(native("T", "Méndez-Reneau"), "auth.lower"), "mendez-reneau")
  expect_identical(key(native("T", "Muñoz‐Rodríguez"), "auth.lower"), "munoz-rodriguez")
  expect_identical(key(native("T", "Weiß"), "auth.lower"), "weiss")
  expect_identical(key(native("T", "Tørve"), "auth.lower"), "torve")
  expect_identical(key(native("T", "Łukasiewicz"), "auth.lower"), "lukasiewicz")
})

test_that("a name with only an organisation, or editors only, still yields a key", {
  org <- list(itemType = "report", title = "T", date = "2020", creators = list(list(creatorType = "author", name = "WHO Group")))
  expect_identical(key(org, "auth.lower + year"), "whogroup2020")
  ed <- list(itemType = "book", title = "T", date = "2020", creators = list(list(creatorType = "editor", lastName = "Editor", firstName = "E")))
  expect_identical(key(ed, "auth.lower"), "editor")
})

# --- year ----------------------------------------------------------------------
test_that("year takes the four-digit year from any date format", {
  for (d in c("2006", "2006-07-27", "July 27, 2006", "27/07/2006")) {
    expect_identical(key(native("T", date = d), "year"), "2006")
  }
  expect_error(key(native("T", date = "in press"), "year"), "empty key")
  expect_identical(key(native("T", "Kent", date = "in press"), "auth.lower + year"), "kent")
})

# --- shorttitle ------------------------------------------------------------------
test_that("shorttitle skips function words and takes the first n words", {
  t <- native("A taxonomic revision of the Hymenophyllaceae")
  expect_identical(key(t, "shorttitle(1).lower"), "taxonomic")
  expect_identical(key(t, "shorttitle(2).lower"), "taxonomicrevision")
  expect_identical(key(t, "shorttitle(3).lower"), "taxonomicrevisionhymenophyllaceae")
  expect_identical(key(native("On the origin of species"), "shorttitle(1).lower"), "origin")
})

test_that("shorttitle(n, m) capitalises the first m words", {
  t <- native("A taxonomic revision of Hymenophyllaceae")
  expect_identical(key(t, "shorttitle(3,3)"), "TaxonomicRevisionHymenophyllaceae")
  expect_identical(key(t, "shorttitle(2,1)"), "Taxonomicrevision")
  expect_identical(key(t, "shorttitle(3,3).lower"), "taxonomicrevisionhymenophyllaceae")
})

test_that("titles are cut at the first sentence break, but not inside abbreviations", {
  expect_identical(key(native("Phylogeny: character evolution"), "shorttitle(5).lower"), "phylogeny")
  expect_identical(key(native("U.Taxonstand: an R package"), "shorttitle(1).lower"), "utaxonstand")
  expect_identical(key(native("Why? Because"), "shorttitle(3).lower"), "why")
  expect_identical(key(native(": odd title"), "shorttitle(1).lower"), "odd")
})

test_that("title words drop hyphens and punctuation, and split on slashes and dashes", {
  expect_identical(key(native("Early-diverging lineages"), "shorttitle(1).lower"), "earlydiverging")
  expect_identical(key(native("FAR-RED light"), "shorttitle(1).lower"), "farred")
  expect_identical(key(native("Let's practice"), "shorttitle(1).lower"), "lets")
  expect_identical(key(native("joelnitta/taxastand: v2"), "shorttitle(1).lower"), "joelnitta")
  expect_identical(key(native("Leafflower–leafflower moth"), "shorttitle(2).lower"), "leafflowerleafflower")
  expect_identical(key(native("Café au lait"), "shorttitle(1).lower"), "cafe")
})

test_that("HTML tags in titles are ignored", {
  expect_identical(key(native("<i>rbcL</i> data reveal groups"), "shorttitle(1).lower"), "rbcl")
  expect_identical(key(native("The <sub>2</sub> case"), "shorttitle(1).lower"), "2")
})

test_that("title() uses every word", {
  expect_identical(key(native("A taxonomic revision"), "title.lower"), "ataxonomicrevision")
})

test_that("a missing title gives an empty piece, not an error, unless the whole key is empty", {
  expect_identical(key(native(""), "auth.lower + year + shorttitle(1).lower"), "smith2020")
  expect_error(key(list(itemType = "book", creators = list()), "auth + year"), "empty key")
})

# --- whole formulas -------------------------------------------------------------
test_that("the author's own formula reproduces real keys from the library", {
  cases <- list(
    list(native("Phylogeny, character evolution, and classification of Selaginellaceae", "Zhou"), 2023, "zhou2023phylogeny"),
    list(native("Let's Practice What We Preach", "Gelman", "2012"), 2012, "gelman2012lets"),
    list(native("Life history, climate and biogeography", "De Kort", "2021"), 2021, "dekort2021life"),
    list(native("Modern applied statistics with S", "Venables", "2002"), 2002, "venables2002modern"),
    list(native("Mixed-ploidy Population of Microlepia marginata", "Koda", "2025"), 2025, "koda2025mixedploidy"),
    list(native("U.Taxonstand: An R package for standardizing", "Zhang", "2023"), 2023, "zhang2023utaxonstand"),
    list(native("hybpiper-rbgv and yang-and-smith-rbgv", "Jackson", "2021"), 2021, "jackson2021hybpiperrbgv")
  )
  for (cs in cases) {
    item <- cs[[1]]
    if (item$date == "2020") item$date <- as.character(cs[[2]])
    expect_identical(key(item), cs[[3]])
  }
})

test_that("BBT's default pattern is auth.lower + shorttitle(3,3) + year", {
  expect_identical(
    key(native("A taxonomic revision of Hymenophyllaceae", "Ebihara", "2006"), cz_default_key_format),
    "ebiharaTaxonomicRevisionHymenophyllaceae2006"
  )
})

test_that("CSL-JSON items give the same key as native items", {
  expect_identical(key(csl("Gene flow among ferns", "Kent", 2002)), key(native("Gene flow among ferns", "Kent", "2002")))
  expect_identical(key(csl("Gene flow among ferns", "Kent", 2002)), "kent2002gene")
})

test_that("a full native item from the API (with $data) works", {
  full <- list(key = "X", version = 3, data = native("Gene flow", "Kent", "2002"))
  expect_identical(key(full), "kent2002gene")
})

test_that("keys are ASCII and pandoc-safe", {
  k <- key(native("Café: *odd* “quotes”", "O'Brien", "2020"), "auth.lower + year + shorttitle(2).lower")
  expect_match(k, "^[A-Za-z0-9_:.+-]+$")
  expect_identical(k, "obrien2020cafe")
})

# --- collisions -----------------------------------------------------------------
test_that("a taken key gets a letter: a, b, ... aa", {
  it <- native("Gene flow", "Kent", "2002")
  expect_identical(key(it, existing = "other"), "kent2002gene")
  expect_identical(key(it, existing = "kent2002gene"), "kent2002genea")
  expect_identical(key(it, existing = c("kent2002gene", "kent2002genea")), "kent2002geneb")
  taken <- c("kent2002gene", paste0("kent2002gene", letters))
  expect_identical(key(it, existing = taken), "kent2002geneaa")
})

test_that("cz_postfix counts like spreadsheet columns", {
  expect_identical(vapply(c(1, 26, 27, 28, 52, 53, 702, 703), cz_postfix, ""), c("a", "z", "aa", "ab", "az", "ba", "zz", "aaa"))
})

# --- finding the formula -----------------------------------------------------------
write_prefs <- function(dir, lines) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, file.path(dir, "prefs.js"))
}

test_that("the option wins over everything", {
  withr::local_options(citezot.key_format = "auth + year", citezot.zotero_profile = withr::local_tempdir())
  expect_identical(cz_key_format(), list(formula = "auth + year", source = "option"))
})

test_that("the formula is read from the Zotero profile, and only that line", {
  d <- withr::local_tempdir()
  write_prefs(d, c(
    'user_pref("extensions.zotero.sync.server.username", "secret-user");',
    'user_pref("extensions.zotero.translators.better-bibtex.citekeyFormatEditing", "wrong");',
    'user_pref("extensions.zotero.translators.better-bibtex.citekeyFormat", "auth.lower + year + shorttitle(1).lower");'
  ))
  withr::local_options(citezot.key_format = NULL, citezot.zotero_profile = d)
  fmt <- cz_key_format()
  expect_identical(fmt, list(formula = "auth.lower + year + shorttitle(1).lower", source = "zotero profile"))
  expect_false(grepl("secret", paste(unlist(fmt), collapse = ""), fixed = TRUE))
  # the prefs.js path itself is also accepted
  withr::local_options(citezot.zotero_profile = file.path(d, "prefs.js"))
  expect_identical(cz_key_format()$source, "zotero profile")
})

test_that("escaped quotes in the stored formula are unescaped", {
  d <- withr::local_tempdir()
  write_prefs(d, 'user_pref("extensions.zotero.translators.better-bibtex.citekeyFormat", "auth + \\"-\\" + year");')
  withr::local_options(citezot.key_format = NULL, citezot.zotero_profile = d)
  expect_identical(cz_key_format()$formula, 'auth + "-" + year')
})

test_that("with no option and no Zotero settings, BBT's default is used", {
  withr::local_options(citezot.key_format = NULL, citezot.zotero_profile = withr::local_tempdir())
  expect_identical(cz_key_format(), list(formula = cz_default_key_format, source = "default"))
  d <- withr::local_tempdir()
  write_prefs(d, 'user_pref("extensions.zotero.other", 1);')
  withr::local_options(citezot.zotero_profile = d)
  expect_identical(cz_key_format()$source, "default")
})

test_that("cz_suggest_key uses the resolved formula when none is given", {
  withr::local_options(citezot.key_format = "auth.lower + year")
  expect_identical(cz_suggest_key(native("T", "Kent", "2002")), "kent2002")
})
