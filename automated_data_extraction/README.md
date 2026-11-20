# Automated data extraction: Pilot 1, Pilot 2 and Study 1

*Lukas Wallrich (Birkbeck, University of London) and Ilse L. Pit (Max Planck
Institute for Human Development), November 2026.*

*LLM transparency: this README was drafted with Claude (Anthropic, Opus 5.5).*

> **Work in progress.** These materials are part of a Stage 1 Registered Report
> submission (*Prevalence and Reporting Practices of Pilot Studies in Psychology*).
> Scripts, files and documentation may still change before or after Stage 1 review.

This folder holds the pipeline that extracts article-level metadata automatically,
and the evidence for how well it agrees with the manual coding in the two pilot
rounds (Pilot 1: 2022 articles; Pilot 2: 2023 articles). Given article DOIs and
their GROBID **TEI** files (and optionally the PDFs), the pipeline returns one row
per article with bibliographic metadata, first-author location, funding,
conflict-of-interest (COI) and preregistration fields. In Study 1 it supplies these
fields for the 2025 sample.

The code was developed in
[LukasWallrich/pilot_meta_extracter](https://github.com/LukasWallrich/pilot_meta_extracter);
this folder is a copy of the current files at commit
[`953693b`](https://github.com/LukasWallrich/pilot_meta_extracter/tree/953693b). The
development history, the sampling-frame runs and other superseded material stay in
that repository (see its `archive/README.md`).

Run every command below from this folder (`automated_data_extraction/`).

## Quick start

```r
source("run_pipeline.R")          # defines functions only
result <- run_pipeline(data.frame(doi = my_dois, tei_file = my_tei_paths))
# optional PDF front-page COI fallback:
# run_pipeline(df_with_pdf_file_column, pdf_coi_fallback = TRUE)
```

`run_pipeline()` queries OpenAlex, Crossref and OSF only for DOIs that are not in
the caches under `data/cache/`, and adds new results there. With
`use_api = FALSE` it runs offline and stops if a cache entry is missing. The 21
output columns and their derivation are documented in `docs/README_pipeline.md`.

Optional one-time setup: `Rscript setup/download_top_factor.R` downloads the TOP
Factor journal data (`top_factor_data.RData`, not committed). Without it,
`top_factor` is only available for DOIs already in the metadata cache.

## Study 1 (2025 sample)

1. **Sample.** The database team builds the classified article sample and imports
   it into Zotero, which retrieves the PDFs (see
   [`../database_curation/`](../database_curation/)).
2. **Full texts.** Convert the PDFs to TEI XML with GROBID, as for Pilot 2
   (`screening/grobid_conversion_workflow.yml`).
3. **Extraction.** Call `run_pipeline()` on a table with one row per article: `doi`
   and `tei_file`, plus `pdf_file` if the PDF COI fallback is used.
4. **Contact address.** Before making new API calls, set `contact_email` in
   `pipeline.conf` to the address of the person running the pipeline.

Grouping journals into fields is done in the analysis, not by this pipeline.

## Folder layout

| Path | Contents |
|---|---|
| `run_pipeline.R` | Generic entry point and the Pilot 1 + Pilot 2 driver (`PIPELINE_RUN=1`). |
| `pipeline.conf`, `R/0_config.R` | Settings: the contact address sent with API requests. |
| `R/1_…` to `R/5_…` | Extraction modules: OpenAlex/Crossref metadata; TEI funding/COI; preregistration; funder → country; PDF COI fallback. Sourcing them only defines functions. |
| `run_coi_pdf_fallback.R` | PDF COI fallback over the finished table of coded pilot articles. |
| `setup/` | TOP Factor reference-data setup. |
| `screening/` | GROBID PDF → TEI conversion workflow. |
| `validation/` | Stage reproductions, scoring against manual coding, figure scripts. |
| `data/` | Final outputs (top level), `inputs/` (coding responses, historical inputs, provenance), `cache/` (API caches), `stages/` (per-stage outputs). |
| `docs/` | Method documentation and `figures/`. |

## Output files

`data/final_extraction_pilot1-and-pilot2.csv` has one row per manually coded
article of both pilots (346), with the 21 columns documented in
`docs/README_pipeline.md`. The other files in `data/` are validation tables
derived from it and from the per-stage outputs in `data/stages/`.

**Coding responses.** `data/inputs/` holds the exported responses of the Pilot 1
and Pilot 2 coding forms (the forms themselves are in
[`../materials/manual_data_extraction/`](../materials/manual_data_extraction/)) and
the 11 June 2026 table that joins them with the automated metadata. Four
coding-process columns were removed from these three files: form timestamp, coder
initials, feedback on the coding form, and time taken to code. No script uses them;
every other field is unchanged.

## Reproducing the pilot results

These run offline from the committed files:

| Command | Reproduces |
|---|---|
| `Rscript validation/final_agreement.R` | Agreement of the final output with the original manual codes (table below). Read-only. |
| `Rscript validation/pilot2_auto_vs_manual.R` | `data/pilot2_auto_vs_manual_counts.csv`, `data/pilot2_final_statement_comparison.csv` |
| `Rscript validation/plot_pilot_confusion.R` | `docs/figures/pilot_extraction_{mixed,confusion,categories}.{png,pdf}` and `data/pilot_category_comparison.csv` |
| `Rscript validation/plot_pilot_categories.R` | The three-category figure and table alone |
| `Rscript validation/validate_rx_vs_metacheck.R` | `data/rx_vs_metacheck_metrics.csv` |
| `Rscript validation/pilot_link_funders.R` | `data/stages/funder*` (from the TEI stage table and caches) |

These scripts reproduce the committed tables and PNG figures byte for byte (the PDF
figures differ only in embedded dates).

Re-running extraction itself needs the source full texts, which are not shared
because they are copyrighted. The default locations are relative to this folder:

| Command | Needs |
|---|---|
| `PIPELINE_RUN=1 Rscript run_pipeline.R` | Pilot 1 TEIs at the paths in `data/inputs/pilot1_doi_tei_map.csv` (`../pilot_pilot_teis/tei/`) and Pilot 2 TEIs in `../pilot2_pdf_conversion/tei/` |
| `validation/pilot_extract_tei.R`, `validation/pilot_extract_prereg.R` | The same TEI folders; `metacheck` for the TEI stage |
| `run_coi_pdf_fallback.R` | Source PDFs: set `PILOT_PDF_ROOT` to the folder with `Zotero_PDFs/` and `pilot2/`; Poppler's `pdftotext`; the Pilot 2 TEI folder (file names only) |
| `Rscript validation/recover_missing_pilot2.R XML PDF OUT.csv` | The original XML and PDF of `10.1177/09567976231165271` (hashes in `data/inputs/recovered_tei/`) |
| `Rscript validation/match_pilot1_tei.R` | The Pilot 1 TEIs; documents how `data/inputs/pilot1_doi_tei_map.csv` was built |

With the full texts and the included caches, a cache-only run (`use_api = FALSE`)
followed by `run_coi_pdf_fallback.R` reproduces every cell of the final table for
345 of the 346 articles. The exception is `10.1037/pspi0000433`: the Pilot 2 TEI
folder holds two TEI files for it, so automatic PDF lookup by file name
(`map_pdf_files()`) misses its PDF and the fallback does not recover its COI
statement. Passing its `pdf_file` explicitly reproduces the recorded row.

TEIs were produced with GROBID 0.8.2 (Pilot 1 and the recovered Pilot 2 article)
and 0.8.2.1 (other Pilot 2 articles; `screening/grobid_conversion_workflow.yml`).

## Validation summary

All figures compare automated output with the **original manual codes** of the two
pilot rounds. They are agreement on the development sample: the rules were refined
after inspecting these articles, so they are optimistic for unseen articles. Pilot 1
is the cleaner out-of-sample test for the TEI extractor.

**Final output vs original codes** (`validation/final_agreement.R`; with the PDF COI
fallback):

| Measure | Pilot 1 | Pilot 2 | Pooled |
|---|---|---|---|
| Funding category | 47/52 (90.4%) | 78/84 (92.9%) | 125/136 (91.9%) |
| COI category (3 categories) | 53/64 (82.8%) | 76/84 (90.5%) | 129/148 (87.2%) |
| COI statement presence | 59/64 (92.2%) | 80/84 (95.2%) | 139/148 (93.9%) |
| Preregistration | 60/64 (93.8%) | 79/84 (94.0%) | 139/148 (93.9%) |

Blank Pilot 1 funding answers are treated as uncoded (see `docs/README_pipeline.md`).
The recorded Pilot 2 response for `10.1037/xge0001439` that lists only the CRediT
"Funding acquisition" role is retained as a positive manual funding code. Pilot 2
funding statement presence is also 78/84 (92.9%).

**Figures.** `docs/figures/pilot_extraction_mixed.*` keeps Pilot 1's original
Crossref-only binary comparison (n = 65 per outcome) and shows Pilot 2's final
three-category output. The percentages describe different tasks and are not directly
comparable. Alternatives: all-binary (`pilot_extraction_confusion.*`) and
all-three-category (`pilot_extraction_categories.*`; Pilot 1 categories reconstructed
from original Crossref metadata, funding n = 53, COI n = 65).

**XML-only extractor vs `metacheck` 0.1.0** (statement presence from TEI only,
`data/rx_vs_metacheck_metrics.csv`, 148 pooled):

| Outcome | Extractor accuracy / F1 | `metacheck` accuracy / F1 |
|---|---|---|
| Funding | 0.926 / 0.956 | 0.838 / 0.898 |
| COI | 0.878 / 0.914 | 0.831 / 0.878 |

On Pilot 1 alone, F1 is 0.92 vs 0.89 (funding) and 0.85 vs 0.81 (COI).

**Funder → country.** Of the 227 papers with at least one named funder, 200 (88%)
get at least one funder country (`docs/README_funders.md`). The funder resolutions
have not been re-audited since October 2026.

Module-level preregistration figures in `docs/README_prereg_extraction.md` come from
the preregistration stage table and use a stricter manual filter; they are not the
end-to-end figures above.

## Recovered Pilot 2 article

`10.1177/09567976231165271` was missing from the coded batch because its manual DOI
had a bare `doi.org/` prefix; `norm_doi()` now strips it. The output was regenerated
from the original GROBID 0.8.2 XML, whose source PDF matches the assigned Zotero/Drive
PDF by hash, with cached metadata and unchanged extraction rules. Provenance:
`data/inputs/recovered_tei/10.1177-09567976231165271.provenance.json`. It is in the
final table, all stage tables and all comparisons above.

## Software

Validated with R 4.6.1, dplyr 1.2.1, stringr 1.6.0, tidyr 1.3.2, purrr 1.2.2,
readr 2.2.0, xml2 1.6.0, httr 1.4.8, httr2 1.2.3, jsonlite 2.0.0, stringdist 0.9.17,
stringi 1.8.9, countrycode 1.8.0, sjrdata 1.0.25 (GitHub `ikashnitsky/sjrdata`),
ggplot2 4.0.3, patchwork 1.3.2, knitr 1.51, tidyverse 2.0.0 and `metacheck` 0.1.0
(GitHub `scienceverse/metacheck`; TEI stage only). The PDF fallback needs Poppler's
`pdftotext`. Sourcing `R/1_extract_doi_metadata.R` installs `pacman`, `pak` and
`sjrdata` if they are missing.

API politeness: the code sends a contact address with OpenAlex, Crossref and OSF
requests. It is set once, as `contact_email` in `pipeline.conf`. `OPENALEX_API_KEY`
is optional and read from the environment.

## Data sources

OpenAlex · Crossref (including the Funder Registry) · Scimago Journal Rank
(`sjrdata`) · TOP Factor (Center for Open Science) · OSF and AsPredicted · GROBID.
Please cite the sources you rely on.

## Licence

CC BY 4.0, as for the whole repository; see [`../LICENSE`](../LICENSE).
