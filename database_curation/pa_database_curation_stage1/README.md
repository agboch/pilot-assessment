# Database curation: Pilot 2 and Study 1

*Mary Beth Neff, University of Oslo, November 2026.*

*LLM transparency: this README was drafted with Claude (Anthropic, Opus 5.5) and reviewed by Mary Beth Neff.*

> **Work in progress.** These materials are part of a Stage 1 Registered Report submission (*Prevalence and Reporting Practices of Pilot Studies in Psychology*). Scripts, files and documentation may still change before or after Stage 1 review.

This folder documents how the article databases for the project were built: the journal list, the article download, the empirical / non-empirical classification, and the sample of 6,000 articles imported into Zotero. It covers Pilot 2 (articles published in 2023) and Study 1, the main study (articles published in 2025). The Pilot 1 database was built manually from Web of Science.

### The curation document (PDF)

[`Piloting_Meta-Assessment_Working_Group___Zotero_Database_Curation_README.pdf`](Piloting_Meta-Assessment_Working_Group___Zotero_Database_Curation_README.pdf) is the working group's full description of how the databases were built. It is the place to start for the overall process, and covers:

- **Pilot 1 (2022):** the manual Web of Science workflow, which has no scripts in this folder.
- **Pilot 2 (2023)** and the **proposed Study 1 (2025)** pipeline, at the level of decisions and steps.
- **The Zotero workflow shared by all three:** importing the RIS files, retrieving PDFs, the folder and subcollection structure, the pilot keyword searches, and exporting PDFs for screening.

It was first drafted in October 2025 and last updated on 18 November 2026. The folders below hold the scripts and files that carry out the Pilot 2 and Study 1 steps; their READMEs give the technical detail. Where the PDF and the folder READMEs differ, the folder READMEs are more recent. For example, the PDF cites the 2025 MultiTagger preprint, whereas the model actually used is the 2024 release (see the `multitagger` README).

### Folders

| Folder | What it holds |
|---|---|
| [`pilot-2-db/`](pilot-2-db/) | Pilot 2 (2023): the curation script, the journal classification and its documentation, the article classification prompt history, and the comparison of the LLM article classification with MultiTagger. |
| [`study-1-db/`](study-1-db/) | Study 1 (2025): the curation script, the NPI journal register, and the journal classifications it uses. Articles are classified with MultiTagger instead of an LLM. |
| [`multitagger/`](multitagger/) | The scripts for running the MultiTagger-v2 publication-type tagger, used by both databases, with setup instructions. |

Each folder has its own README with the run order and details.

### How the folders connect

**Pilot 2.** `pilot-2-db` builds the database and classifies articles with an LLM. MultiTagger was then run on the same articles, and the comparison script in `pilot-2-db` compares the two classifications. This comparison informed the choice of MultiTagger for Study 1.

1. `pilot-2-db/pilot2_db_curation_v5_replicable.R`: journals, articles, LLM classification, sample.
2. `multitagger/run_multitagger_pilot2db.py`: MultiTagger on the same articles.
3. `pilot-2-db/pilot2_db_multitagger-comparison._v2-public.R`: LLM vs MultiTagger.

**Study 1.** One script runs the whole pipeline and stops once for MultiTagger.

1. `study-1-db/pilot-assessment_2025-db-curation_v2_public.R`, Steps 0–3: journals, articles, cleaning; writes `articles_for_classification.csv`.
2. `multitagger/run_multitagger_study1db.py`: MultiTagger on that file; writes `multitagger_predictions.csv`.
3. The same R script, Steps 4–8: classification, sample, RIS files for Zotero, exclusion tables.

| | Pilot 2 | Study 1 |
|---|---|---|
| Publication year | 2023 | 2025 |
| Journals (NPI level 1–2, after screening) | 513 | 519 |
| Article classification | LLM (Claude) | MultiTagger-v2 |
| Sample | 6,000, simple random | 6,000, stratified by journal (square-root allocation) |

### Not shared

Files that contain article abstracts (the article downloads, classification inputs and outputs, and the samples) are not shared, because abstracts are usually copyrighted by the publishers. The scripts regenerate them. Because OpenAlex and PubMed change over time, a new run will not reproduce the original article pools exactly.

The MultiTagger model and code are not included either. They come from the MultiTagger-v2 authors (Menke et al., 2024; https://github.com/ScienceNLP-Lab/MultiTagger-v2), and the `multitagger` README explains how to download them.

### Contact

Mary Beth Neff (marybethneff@gmail.com), University of Oslo.
