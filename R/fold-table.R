# ASCII transliteration for citation keys. Written with \u escapes because
# R code in a package must be ASCII. (iconv //TRANSLIT is platform dependent.)
cz_fold_from <- paste0(
  "\u00c0\u00c1\u00c2\u00c3\u00c4\u00c5\u00e0\u00e1\u00e2\u00e3\u00e4",
  "\u00e5\u00c8\u00c9\u00ca\u00cb\u00e8\u00e9\u00ea\u00eb\u00cc\u00cd",
  "\u00ce\u00cf\u00ec\u00ed\u00ee\u00ef\u00d2\u00d3\u00d4\u00d5\u00d6",
  "\u00d8\u00f2\u00f3\u00f4\u00f5\u00f6\u00f8\u00d9\u00da\u00db\u00dc",
  "\u00f9\u00fa\u00fb\u00fc\u00dd\u00fd\u00ff\u00d1\u00f1\u00c7\u00e7",
  "\u0106\u0107\u010c\u010d\u010e\u010f\u0110\u0111\u011a\u011b\u0118",
  "\u0119\u011e\u011f\u0141\u0142\u0143\u0144\u0147\u0148\u0158\u0159",
  "\u015a\u015b\u0160\u0161\u015e\u015f\u0164\u0165\u016e\u016f\u017d",
  "\u017e\u0179\u017a\u017b\u017c\u0100\u0101\u0112\u0113\u012a\u012b",
  "\u014c\u014d\u016a\u016b\u0102\u0103\u0150\u0151\u0170\u0171\u0130",
  "\u0131\u00d0\u00f0"
)
cz_fold_to <- paste0(
  "AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuYyyNnCcCcCcDdDdEeE",
  "eGgLlNnNnRrSsSsSsTtUuZzZzZzAaEeIiOoUuAaOoUuIiDd"
)
cz_fold_multi <- c(
  "\u00df" = "ss",
  "\u00c6" = "AE",
  "\u00e6" = "ae",
  "\u0152" = "OE",
  "\u0153" = "oe",
  "\u00de" = "Th",
  "\u00fe" = "th"
)
