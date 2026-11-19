# Study 1 database (2025): files and run order

*Mary Beth Neff, University of Oslo, November 2026.*

*LLM transparency: this README was drafted with Claude (Anthropic, Opus 5.5) and reviewed by Mary Beth Neff.*

> **Work in progress.** This folder is part of a Stage 1 Registered Report submission. The scripts, files and documentation may still change before or after Stage 1 review, so treat them as a working version rather than a final record.

This folder holds the script and inputs for building the Study 1 article database: empirical articles published in 2025 in level 1–2 psychology journals from the Norwegian Publication Indicator (NPI). The script builds on the Pilot 2 database script; its header lists what changed.

### Files

| File | What it is |
|---|---|
| `pilot-assessment_2025-db-curation_v2_public.R` | The script: NPI journal list, journal filtering and classification, OpenAlex download, record and abstract cleaning (with PubMed recovery of missing abstracts), MultiTagger classification, a stratified sample of 6,000 empirical articles, RIS files for Zotero, and exclusion tables. |
| `JOURNAL_CLASSIFICATION_README.md` | How the journal classification was made for Study 1. |
| `NPI_Scientific_Journals.csv` | The NPI register as downloaded on 2026-09-28. The script uses this copy instead of downloading the register again. |
| `2023journals_llm_classified_final.csv` | The Pilot 2 journal classification; carried over for journals still on the list (Step 1d). |
| `2025journals_llm_classified_final.csv` | The Study 1 journal classification (Step 1f). |

Keep all five files in one folder, the run folder (`study-1-db` by default).

The script also relies on two other folders: the **MultiTagger** folder (Step 4) and the **Pilot 2** folder, whose comparison script, `pilot2_db_multitagger-comparison._v2-public.R`, documents the MultiTagger label groups used here.

### Run order

1. **Set up.** At the top of the script, set `base_directory` (the folder that contains the run folder) and check `RUN_LABEL`. Set the environment variable `CONTACT_EMAIL` to your email: OpenAlex and PubMed ask for one with each request. `OPENALEX_API_KEY` and `NCBI_API_KEY` are optional.
2. **Run the script.** Steps 0–1 build the journal list from the NPI file and apply the journal classification. With both classification files in place this runs straight through.
3. **Steps 2–3** download the articles from OpenAlex, clean them, recover missing abstracts from PubMed and write `articles_for_classification.csv`. This needs internet access and takes a while.
4. **MultiTagger (manual).** The script stops at Step 4b. Run MultiTagger on `articles_for_classification.csv` as described in the MultiTagger README (`run_multitagger_study1db.py`), and save the output as `multitagger_predictions.csv` in the run folder.
5. **Run the script again.** Steps 4–8 classify the articles as empirical or non-empirical, draw the sample, write the RIS files, and write the exclusion tables and `classification_summary.txt`.

The script saves its outputs as it goes and reuses them on re-runs, so you can run it from the top each time (see "Re-running / resuming" in its configuration).

### Results will not match exactly

OpenAlex and PubMed change over time, so a new run will not reproduce our article pool exactly. In the original run, 3,183 abstracts were recovered from PubMed and 37,659 articles were sent to MultiTagger; the log prints the new counts next to these.

### Not shared

Files that contain article abstracts are not shared, because abstracts are usually copyrighted by the publishers: the OpenAlex download (`openalex_articles_raw_2025.rds`), the PubMed abstract cache, `articles_for_classification.csv`, the MultiTagger predictions, and the sample and RIS files. The steps above regenerate them.

### Requirements

- R ≥ 4.1.0 with dplyr, readr, stringr, tidyr, tibble, httr, jsonlite and xml2.
- Internet access for OpenAlex and PubMed.
- MultiTagger and its Python environment for Step 4 (see the MultiTagger README).
