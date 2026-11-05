# Build the English + Japanese website into `_site/`.
#
# Needs: quarto, and the pkgsite and babelquarto packages (see
# `Config/Needs/website` in DESCRIPTION), plus citezot installed (the pages
# run the offline examples).
#
# The function reference is generated from `man/*.Rd` by pkgsite and is only
# written in English. babelquarto needs a `.ja.qmd` for every page, so the
# Japanese site gets a copy of each English reference page.
pkgsite::write_reference()
en <- list.files("reference", pattern = "\\.qmd$", full.names = TRUE)
en <- en[!grepl("\\.ja\\.qmd$", en)]
file.copy(en, sub("\\.qmd$", ".ja.qmd", en), overwrite = TRUE)
babelquarto::render_website(".")
