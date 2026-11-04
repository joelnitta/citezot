# Zotero Web API v3: verified notes for the write side

Checked 2026-11-04 against the official docs (write_requests, basics, types_and_fields) and read-only calls to Joel's library. Nothing was written to the library. Items marked **[live]** were observed live; **[docs]** come from the documentation only and still need a live check on a throwaway item before relying on them.

## Item JSON (native)
- **[live]** `GET /users/{id}/items/{key}` returns `{key, version, library, links, meta, data}`. Writable fields are in `data`.
- **[live]** `data` includes `itemType`, `title`, `creators`, `DOI`, `date`, `extra`, `tags`, `collections`, `relations`, and **`citationKey`** (native field). So pinning via `PATCH {citationKey}` (as `cz_pin_key()` does) is correct.
- **[live]** Creator object: `{creatorType, firstName, lastName}`; `/creatorFields` also lists `name` (single-field creators).
- **[live]** Templates: `GET https://api.zotero.org/items/new?itemType=journalArticle` (a **global** endpoint, not under `/users/{id}/`) lists every writable field, including `citationKey`; `book` has `ISBN`. Valid fields per type: `/itemTypeFields?itemType=`; creator types: `/itemTypeCreatorTypes?itemType=`.

## Searching (matters for `cz_find()`)
- **[live]** Server-side `q` can NOT find items by DOI or citekey: `q=<DOI>` returns 0 results in the default mode and 14 fuzzy hits with `qmode=everything` (full text); `q=<citekey>` returns 0. The docs list no DOI/ISBN/citekey filter; only `itemKey` (max 50), `itemType`, `tag`, `since`, `q`.
- **[live]** Title words in `q` work (quick search covers title/creator/year).
- **Decision:** `cz_find()` filters client-side on the CSL-JSON from `cz_fetch_items()` (has `DOI`, `ISBN`, `citation-key`, title, authors), which is cheap with the cache. DOI comparison is case-insensitive and ignores `https://doi.org/` prefixes.

## Creating items
- **[docs]** `POST /users/{id}/items` with a JSON array of item `data` objects, max 50 (413 beyond). Only `itemType`, `tags`, `collections`, `relations` are required; collections are listed by collection **key**.
- **[docs]** `Zotero-Write-Token`: random 32-character string; the server remembers tokens of *successful* requests for 12 hours; **reusing one returns 412**, which means the earlier attempt succeeded. Omit it when sending `If-Unmodified-Since-Version`. For `cz_add()`, use the token (retry-safe, no version race). `cz_perform()`'s 412 message ("item changed") is wrong for this case and needs its own handling.
- **[docs]** 200 response maps array index to result. The page is inconsistent (`success` vs `successful`, plus `unchanged` and `failed`); parse both. Failed entries carry `key`, `code`, `message`.

## Updating items
- **[docs]** PATCH sends only changed properties (204 on success). PUT replaces everything and drops omitted fields, so **never use PUT**. Arrays (creators, tags, collections) are replaced wholesale: to add one tag you must send the full list. Clear a field with `""` or `[]`.
- **[docs]** `If-Unmodified-Since-Version` (or `version` in the body); mismatch is 412; a missing header on DELETE is 428. `dateAdded` that differs from the stored value is a 400.

## Deleting
- Out of scope for v1. If added: DELETE needs `If-Unmodified-Since-Version` (204 / 412 / 428); prefer moving to the trash by PATCHing `deleted`.

## Rate limiting
- **[docs]** `Backoff: <seconds>` can appear on any response including 200: finish the requests that are needed, then pause that long. `Retry-After: <seconds>` accompanies 429 (sometimes 503); without it on a 429, back off exponentially. The write_requests page does not cover this; it is on the basics page.
- **Gap:** `cz_request()` only honours these headers on 429/503. A `Backoff` on a successful response is not yet honoured: a bulk write loop must sleep.

## API key
- **[live]** `GET /keys/current` shows the key in Joel's environment has **write access** (library read+write, files). The key used for reading is therefore capable of writing. Recommended: a separate read-only key for routine use (`cz_update_bib()`), and a write key only in sessions that edit.

## Live write round trip (2026-11-04, Joel's go-ahead, one throwaway item XZVSG5K8)
All **[docs]** behaviours above that citezot relies on were confirmed:
- **POST create** returned 200 with all four maps present: `successful`, `success`, `unchanged`, `failed` (parsed from `successful[["0"]]$key`, falling back to `success[["0"]]`). The new item appeared in the next incremental fetch (5867 -> 5868) with its `citationKey`, pinned in the same request.
- **Write token**: re-sending the identical POST with the same `Zotero-Write-Token` returned **412** and created no duplicate item.
- **PATCH** with `If-Unmodified-Since-Version` succeeded (item version 23087 -> 23088); a stale version returned **412** and wrote nothing.
- `cz_pin_key(overwrite = TRUE)` changed `citationKey` via PATCH as intended.
- Crossref old records can have ALL-CAPS names (`WATSON J. D.`); citezot re-cases fully upper-case names, as Zotero's importer does.
- Crossref sends empty arrays (`"subtitle": []`) for absent values; never index `[[1]]` without a length check.

The test item has no delete route in citezot (v1 has no deletes): move it to the Zotero trash by hand.
