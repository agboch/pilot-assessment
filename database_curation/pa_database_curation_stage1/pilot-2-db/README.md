# Pilot 2 database: files and run order

*Mary Beth Neff, University of Oslo, November 2026.*

*LLM transparency: this README was drafted with Claude (Anthropic, Opus 5.5) and reviewed by Mary Beth Neff.*

This folder holds the scripts and documentation for building the Pilot 2 article database (psychology journals, 2023) and for comparing its LLM classification with MultiTagger.

### Files

| File | What it is |
|---|---|
| `pilot2_db_curation_v5_replicable.R` | Builds the database: journal list from the Norwegian Publication Indicator (NPI), articles from OpenAlex, LLM classification of articles as empirical / non-empirical, a random sample of 6,000 empirical articles, and RIS files for Zotero. |
| `JOURNAL_CLASSIFICATION_README.md` | How the journal-level classification file was made (LLM plus manual review). |
| `journals_for_llm_review.csv` | The journals given to the LLM for journal-level classification (525 journals). |
| `journals_llm_classified_final.csv` | The finished journal classification; read by the curation script at Step 1c. 12 journals are excluded. |
| `article-classification-prompt-changelog.txt` | How the article-level LLM prompt was developed (v1–v7); v7 is the one used. |
| `pilot2_db_multitagger-comparison._v2-public.R` | Compares the LLM's empirical / non-empirical calls with MultiTagger's publication-type labels. |
| `fyi-our-results_multitagger_claude_output.txt` | Our results from the comparison script (run 2026-11-18). These use the Pilot 2 MultiTagger labels as stored, including the cut-off error described in the MultiTagger README; the script header gives the effect of correcting it. |

MultiTagger itself is run from a separate folder with its own README (the MultiTagger scripts).

### Run order

1. **Journal list.** Run `pilot2_db_curation_v5_replicable.R` from the start. Steps 0–1b download the NPI list and filter it. The script then stops at Step 1c unless `journals_llm_classified_final.csv` is in its working folder. To reuse our journal classification, copy the provided file there. To redo it, follow `JOURNAL_CLASSIFICATION_README.md`.
2. **Articles.** Run the script again. Steps 1c–3c download the articles from OpenAlex, filter them, and write `articles_abstracts_for_classification.csv` and the classification batches.
3. **LLM classification (manual).** At Step 3d the script prints the v7 prompt and stops if any classified batch is missing. Run the prompt on each batch with an LLM and save the results as `articles_classified_batch_XX.csv` in the working folder.
4. **Sample and export.** Run the script again. Steps 4–6 merge the batches into `articles_classified_all.csv`, draw the 6,000-article sample, write the RIS files and the summary report.
5. **MultiTagger.** Reformat `articles_abstracts_for_classification.csv` and run MultiTagger on it, as described in the MultiTagger README. This gives `multitagger_predictions.csv`.
6. **Comparison.** Put `articles_classified_all.csv` and `multitagger_predictions.csv` in one folder, set `WORKING_DIRECTORY` at the top of `pilot2_db_multitagger-comparison._v2-public.R`, and run it.

Each R script has a setting at the top for its working folder (`output_directory` in the curation script, `WORKING_DIRECTORY` in the comparison script).

### Results will not match exactly

OpenAlex and the NPI register change over time, and the LLM step is not deterministic, so a new run will not reproduce our article pool exactly. See the header of the curation script.

### Not shared

The article-level files (`articles_master.csv`, `articles_abstracts_for_classification.csv`, the classification batches, `articles_classified_all.csv`, the sample and the MultiTagger predictions) are not shared, because they contain full abstracts, which are usually copyrighted by the publishers. The steps above regenerate them.

### Requirements

- R ≥ 4.1.0 with dplyr, readr, stringr, httr and jsonlite (curation script) and tidyverse (comparison script).
- Internet access for the NPI download and the OpenAlex API.
- Access to an LLM for Step 3d (we used Claude).
