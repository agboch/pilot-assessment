################################################################################
# Pilot TF Meta-Assessment Psychology Journal Database Curation
# MAIN STUDY DATABASE SCRIPT - VERSION 1 (builds on the Pilot 2 script)
################################################################################
#
# PURPOSE:
#   Builds the Study 1 (2025) article database for the Pilot TF Meta-Assessment.
#   Filters psychology journals from the Norwegian Publication Indicator (NPI)
#   register to identify level 1-2, empirical, English-language journals with
#   online ISSNs. Downloads articles for those journals from OpenAlex, removes
#   junk / poorly indexed entries, classifies the remaining articles as
#   empirical or non-empirical with MultiTagger, samples empirical articles
#   (stratified by journal), and exports them to RIS for Zotero.
#   The Pilot 1 and Pilot 2 databases can be rebuilt with the same script by
#   changing PUBLICATION_YEAR, NPI_LEVEL_YEAR and RUN_LABEL (see Step 9).
#
# CHANGES SINCE THE PILOT 2 SCRIPT
#   Scope
#     - PUBLICATION_YEAR is 2025; the NPI level column follows it.
#     - Journal classification is redone for the current NPI list (Steps
#       1d-1f): Pilot 2 calls are carried over for journals still on the list,
#       new journals are classified, and the run stops if any journal is left
#       unclassified (the Pilot 2 script kept such journals silently).
#   Cleaning
#     - All record / abstract / title cleaning happens BEFORE classification,
#       so nothing junk is sent to the classifier.
#     - Missing abstracts are recovered from PubMed (Step 3b2), so closed-access
#       articles from publishers that withhold abstracts from OpenAlex are not
#       dropped (this would otherwise bias the sample towards open access).
#     - Title patterns tightened to avoid false exclusions (see Step 3b).
#     - Per-journal counts and OpenAlex indexing checks (Step 3d).
#   Classification
#     - The LLM article classification step is replaced by MultiTagger
#       (Step 4), using the label groups of pilot2_db_multitagger-comparison._v2-public.R,
#       decision rule A, and a documented manual review decision (Step 4e-1).
#   Sampling and reporting
#     - Sample stratified by journal (sqrt allocation) with sampling weights
#       (Step 6); journal and article exclusion tables (Step 8a).
#     - Optional comparison against a previous run (Step 9).
#   Robustness
#     - Checkpoints: saved outputs are reused on re-runs (see CONFIGURATION).
#     - Robust NPI reader for encoding / quoting problems in the register file.
#     - OpenAlex: cursor paging with retries and a completeness check (page
#       paging caps at 10,000 results per query, and the Pilot 2 script
#       skipped a whole batch on any HTTP error). DOIs de-duplicated before
#       sampling.
#
# WORKFLOW:
#   Step 0  [auto]    Download NPI register; extract Psychology (English) journals
#   Step 1a [auto]    NPI level 1-2 in NPI_LEVEL_YEAR (only levels 1-2 eligible)
#   Step 1b [auto]    Online ISSN present (only online ISSNs used)
#   Step 1c [auto]    Journal-title keyword filter (on level 1-2 with online ISSN)
#   Step 1d [auto]    Compare remaining journals with the previous (Pilot 2)
#                     journal classification; carry over, list new / dropped
#   Step 1e [manual]  LLM classification + manual review of new journals
#   Step 1f [auto]    Validate classification; apply journal exclusions
#   Step 2  [auto]    Download articles from OpenAlex (PUBLICATION_YEAR)
#   Step 3  [auto]    Record cleaning (3b), PubMed abstract recovery (3b2),
#                     abstract checks (3c), title screening (3c2); per-journal counts
#   Step 4  [manual]  Run MultiTagger on articles_for_classification.csv (external)
#           [auto]    Read multitagger_predictions.csv; label firing rates,
#                     no-opinion analysis, rule sensitivity; classify each
#                     article as empirical / non-empirical / no opinion
#   Step 5            (removed; numbering kept so references to Steps 6-9 stay valid)
#   Step 6  [auto]    Sample empirical articles
#   Step 7  [auto]    Export sample to RIS for Zotero
#   Step 8  [auto]    8a exclusion tables (journals, articles); 8b summary report
#   Step 9  [optional] Compare against a reference run (e.g. Pilot 1)
#
# INPUT FILES:
#   2023journals_llm_classified_final.csv  Previous (Pilot 2) journal classification (Step 1d)
#   2025journals_llm_classified_final.csv  in this run's folder, before Step 1f
#                                       (_draft + appended classified rows)
#   multitagger_predictions.csv         before Step 4b (produced by MultiTagger)
#
# OUTPUT FILES:
#   (journal classification files are prefixed with NPI_LEVEL_YEAR, shown as 2025)
#   NPI_Scientific_Journals.csv               Full NPI register (downloaded)
#   npi_summary.csv                           NPI entry count, download time, header fix
#   psych_db.csv                              All Psychology (English) journals
#   filtered_psych_db.csv / excluded_psych_db.csv
#   2023journals_llm_classified_final.csv     Copy of the previous (Pilot 2) file
#   2025journals_vs_2023_comparison.csv       Current vs previous journal list
#                                             (in both / new / dropped + reason)
#   2025journals_to_classify.csv              Journals needing LLM classification
#   2025journals_llm_classified_draft.csv     Carried-over rows; append classified rows
#   2025journals_vs_2023_classification_changes.csv  Calls that differ from 2023
#                                             (only if JOURNAL_RECLASSIFY_ALL = TRUE)
#   2025journals_missing_classification.csv  Only written if Step 1f finds gaps
#   journals_for_openalex.csv                 Final journal list
#   pubmed_abstracts_cache.csv                PubMed lookups by DOI (reused on re-runs)
#   pubmed_recovery_by_journal.csv            Missing abstracts recovered per journal
#   articles_master.csv                       All downloaded articles + cleaning status
#   articles_excluded_record.csv              Removed: missing title / DOI, duplicate DOI
#   articles_excluded_title.csv               Removed: non-research entries by title (3c2)
#   articles_excluded_abstract.csv            Removed: missing/junk abstracts
#   articles_for_classification.csv           Clean articles with article_id
#   journal_article_counts.csv                Articles per journal at each stage
#   journals_poorly_indexed.csv               Journals with mostly unusable abstracts
#   exclusions_by_journal.csv                 Exclusions per journal, by reason
#   issns_without_openalex_articles.csv       Queried ISSNs with no articles returned
#   articles_classified_all.csv               Articles + MT labels + empirical call
#   mt_rule_sensitivity.csv                   Empirical counts under rules A/B/C/strict
#   openalex_articles_raw_<year>.rds          Raw OpenAlex download (reused on re-runs)
#   mt_label_firing_rates.csv                 Articles per MT label + example titles
#   mt_manual_label_decisions.csv             Record of the Step 4e-1 manual decision
#   multitagger_report.txt                    Log of Steps 4c-4e
#   sampling_plan_by_journal.csv              Empirical articles per journal and what
#                                             each sampling method would take (Step 6)
#   articles_empirical_sample.csv             Sample of empirical articles (stratified
#                                             by journal, sqrt allocation) + sampling_weight
#   journal_sample_summary.csv                Journal representation in sample
#   psychology_<year>_empirical_for_zotero_part_XX.ris
#   exclusion_table_journals.csv              Journal exclusions, NPI register -> sample
#   exclusion_table_articles.csv              Article exclusions, download -> sample
#   exclusion_reasons_detail.csv              Article exclusions by detailed reason
#   journal_funnel_to_sample.csv              Every journal sent to OpenAlex, per stage
#   classification_summary.txt                Summary report (includes the tables)
#   reference_comparison.txt                  (Step 9, optional)
#
# CONTACT:     Mary Beth Neff (marybethneff@gmail.com)
# INSTITUTION: University of Oslo, Norway
# DATE:        2026-09-25 (version 1); 2026-09-28 (Step 4e-1 manual label decision);
#              2026-11-18 (tidied for sharing - see TIDY-UP NOTE below);
#              2026-11-19 (public version - see PUBLIC VERSION NOTE below)
# VERSION:     1 (main study database script)
#
# LLM TRANSPARENCY NOTE:
#   This script was developed with Claude (Anthropic, Opus 5.5).
#   LLM-dependent classification is used at one point in the pipeline: journal
#   classification (Step 1e), done outside the script and reviewed manually.
#   Article classification (Step 4) uses MultiTagger, not an LLM.
#
# TIDY-UP NOTE (2026-11-18):
#   Comments, header and duplicated code tidied; no change to the pipeline,
#   except two fixes: (1) author names in the sample / RIS files no longer
#   lose characters outside Latin-1 (e.g. "Lukasz" was written as "ukasz");
#   (2) the year in the journal-funnel labels (Step 8a) follows
#   PUBLICATION_YEAR instead of being fixed at 2025.
#
# PUBLIC VERSION NOTE (2026-11-19):
#   This is the shareable copy of the script. The pipeline is the same as the
#   project's internal copy; only these things differ:
#   0. Working folder: base_directory is NA by default (= the current working
#      directory) instead of the author's own folder (see SETUP).
#   1. Contact email: OpenAlex and PubMed (NCBI) ask for a contact email with
#      each request. It is now read from CONTACT_EMAIL (empty by default)
#      instead of being fixed to the author's address. Set your own before
#      running steps that go online (see CONFIGURATION).
#   2. Self-contained folder: the previous (Pilot 2) journal classification is
#      read from this run's folder (2023journals_llm_classified_final.csv)
#      instead of a separate pilot-2 folder.
#   3. No article-level data shipped: abstracts are copyrighted by
#      publishers, so no file that contains them is shared. A new run
#      rebuilds these files itself:
#        - openalex_articles_raw_2025.rds (the OpenAlex download) is NOT
#          shared. Step 2 downloads the articles from OpenAlex again.
#        - pubmed_abstracts_cache.csv is NOT shared. Step 3b2 queries PubMed
#          again and builds a new cache.
#        - multitagger_predictions.csv is NOT shared. It is made outside R:
#          run MultiTagger on articles_for_classification.csv (written in
#          Step 3) as described in the MultiTagger README
#          (run_multitagger_study1db.py), and save its output in the run
#          folder as multitagger_predictions.csv before Step 4b. The script
#          stops at Step 4b with these instructions if the file is missing.
#      OpenAlex and PubMed change over time, so a new run will not reproduce
#      the original article pool exactly (original run: 3,183 abstracts
#      recovered from PubMed, 37,659 articles sent to MultiTagger). The log
#      prints the new counts next to the original ones.
#   Files shared with this version (all in the run folder):
#     NPI_Scientific_Journals.csv               NPI register as downloaded 2026-09-28
#     2023journals_llm_classified_final.csv     Pilot 2 journal classification
#     2025journals_llm_classified_final.csv     Study 1 journal classification
#     JOURNAL_CLASSIFICATION_README.md          How the journal classification was made
#   The "NPI downloaded" date in classification_summary.txt is taken from the
#   NPI file's modification date, so after copying it may show the copy date;
#   the original download was 2026-09-28.
#
# DEPENDENCIES:
#   R >= 4.1.0; dplyr, readr, stringr, tidyr, tibble, httr, jsonlite, xml2
#
# CLASSIFICATION NOTE:
#   Article classification uses MultiTagger V2: the pretrained model released
#   with Menke JD, Kilicoglu H, Smalheiser NR (2024), Publication type tagging
#   using transformer models and multi-label classification, AMIA Annual
#   Symposium Proceedings (https://pubmed.ncbi.nlm.nih.gov/40417522/); see the
#   MultiTagger README for how it was run. Label definitions from Cohen et al. (medRxiv 2021;
#   https://doi.org/10.1101/2021.07.13.21260468). Full label documentation and
#   the rationale for the psychology-specific label groups are in
#   pilot2_db_multitagger-comparison._v2-public.R (Section 2).
#
#   Journal-level classification (Step 1e) is performed externally via LLM
#   and manual review; see JOURNAL_CLASSIFICATION_README.md. Only journals
#   not already classified in Pilot 2 are sent to the LLM by default.
#
################################################################################
# SETUP
################################################################################

library(dplyr)
library(readr)
library(stringr)
library(tidyr)
library(httr)
library(jsonlite)
library(xml2)       # PubMed abstract recovery (Step 3b2)

# Use a fresh folder per run so outputs from different runs don't mix
# (e.g. "study-1-db" for Study 1, "pilot-1" / "pilot-2" for pilot re-runs).
# SET THIS: the folder that contains the run folder (RUN_LABEL) with the input
# files. Example: base_directory <- "C:/path/to/your/folder"
# Leave as NA to use the current working directory (getwd()).
base_directory   <- NA
if (is.na(base_directory)) base_directory <- getwd()
RUN_LABEL        <- "study-1-db"
output_directory <- file.path(base_directory, RUN_LABEL)
dir.create(output_directory, showWarnings = FALSE, recursive = TRUE)
setwd(output_directory)

cat("Package versions:\n")
for (p in c("dplyr", "readr", "stringr", "tidyr", "httr", "jsonlite", "xml2"))
  cat(sprintf("  %-9s %s\n", paste0(p, ":"), packageVersion(p)))
cat("\n")


################################################################################
# CONFIGURATION
################################################################################

# --- Re-running / resuming (checkpoints) ---
# Every step up to MultiTagger first checks for the files it saves and loads
# them instead of re-running, so the script can be re-run from the top:
#   Step 0  psych_db.csv, npi_summary.csv            (from NPI_Scientific_Journals.csv)
#   Step 1  filtered/excluded_psych_db.csv, <year>journals_* files,
#           journals_for_openalex.csv                 (needs <year>journals_llm_classified_final.csv)
#   Step 2  openalex_articles_raw_<year>.rds
#   Step 3  articles_master.csv, articles_for_classification.csv,
#           journal_article_counts.csv, journals_poorly_indexed.csv,
#           issns_without_openalex_articles.csv       (PubMed lookups: pubmed_abstracts_cache.csv)
#   Step 4  multitagger_predictions.csv (MultiTagger output, external)
# A step's files are reused only if they are newer than its inputs, so a
# change upstream (new NPI download, edited journal classification) makes
# the later steps re-run automatically.
FORCE_RERUN         <- FALSE   # TRUE = ignore saved Step 0/1/3 files and recompute
REDOWNLOAD_NPI      <- FALSE   # TRUE = download the NPI register again
REDOWNLOAD_OPENALEX <- FALSE   # TRUE = download from OpenAlex again

# --- Journal classification (Steps 1d-1f) ---
# Classification file from the previous run. Its calls are carried over for
# journals that are still on the list; new journals are sent to the LLM.
# Public version: read from this run's folder (internal copy used
# file.path(base_directory, "pilot-2", "journals_llm_classified_final.csv"),
# the same file).
PREVIOUS_JOURNAL_CLASSIFICATION <- file.path(output_directory,
                                             "2023journals_llm_classified_final.csv")
PREVIOUS_RUN_LABEL     <- "pilot-2"  # name of the run that file comes from (for the log)
PREVIOUS_LEVEL_YEAR    <- 2023   # NPI level year the previous file was built from
JOURNAL_RECLASSIFY_ALL <- FALSE  # TRUE = classify every journal again, not only new ones

# --- Scope ---
PUBLICATION_YEAR  <- 2025        # Target publication year (was 2023 in Pilot 2)
NPI_LEVEL_YEAR    <- PUBLICATION_YEAR  # Which "Level YYYY" NPI column to filter on
DOCUMENT_TYPE     <- "article"   # OpenAlex work type
LANGUAGE          <- "en"

# --- OpenAlex ---
ARTICLES_PER_PAGE <- 200         # OpenAlex max page size
REQUEST_DELAY     <- 0.5         # Seconds between requests
MAX_RETRIES       <- 5           # Retries per request on HTTP error / timeout
ISSN_BATCH_SIZE   <- 25          # ISSNs per request (avoids HTTP 400)
# --- Contact email (OpenAlex and PubMed/NCBI) ---
# Both services ask for a contact email with each request (OpenAlex "polite
# pool"; NCBI E-utilities policy). Use YOUR OWN address - set it here or as
# the environment variable CONTACT_EMAIL. Empty = no email sent (requests
# still work, but may be slower or rate-limited). Only used by steps that go
# online: Step 2 (if REDOWNLOAD_OPENALEX or no saved download) and Step 3b2.
CONTACT_EMAIL     <- Sys.getenv("CONTACT_EMAIL", "")
OPENALEX_MAILTO   <- CONTACT_EMAIL
OPENALEX_API_KEY  <- Sys.getenv("OPENALEX_API_KEY", "")   # set if you have one

# --- PubMed abstract recovery (Step 3b2) ---
USE_PUBMED_ABSTRACTS <- TRUE     # look up missing/short OpenAlex abstracts in PubMed
PUBMED_BATCH_SIZE    <- 100      # DOIs per PubMed search
PUBMED_CACHE_FILE    <- "pubmed_abstracts_cache.csv"  # re-runs only query new DOIs
NCBI_API_KEY         <- Sys.getenv("NCBI_API_KEY", "")  # optional; raises rate limit
NCBI_DELAY           <- if (nzchar(NCBI_API_KEY)) 0.12 else 0.4  # NCBI: 10 / 3 req per s

# --- Cleaning ---
MIN_ABSTRACT_CHARS     <- 100    # Shorter abstracts are treated as junk
MIN_LATIN_SHARE        <- 0.5    # Below this share of Latin letters = non-English/garbled
DUPLICATE_ABSTRACT_MIN <- 3      # Same abstract on >= this many DOIs = boilerplate

# --- Journal diagnostics ---
MIN_JOURNAL_ARTICLES   <- 10     # Only flag journals with at least this many articles
POORLY_INDEXED_PCT     <- 50     # % unusable abstracts at which a journal is flagged

# --- MultiTagger ---
MT_PREDICTIONS_FILE <- "multitagger_predictions.csv"
# Decision rule mapping MT labels to empirical / non-empirical:
#   "A"      Empirical + Group 1 = empirical; Groups 2+3 = non-empirical
#   "B"      Empirical + Group 2 = empirical; Groups 1+3 = non-empirical
#   "C"      Group 3 only = non-empirical (default in the comparison script)
#   "strict" At least one Empirical/Group 1 label, no Group 3 label, and not
#            a review/systematic review without meta-analysis
# NOTE: under "C", an article tagged only "review" counts as empirical.
MT_DECISION_RULE    <- "A"   # Empirical + Group 1 = empirical (Study 1 choice)
# --- POST-MANUAL-REVIEW DECISION: labels moved to non-empirical (Step 4e-1) ---
# Not part of the original MultiTagger label grouping. Decided after manual
# review of the Step 4d firing rates and example titles (Study 1, 2025 data,
# 2026-09-28): these Group 1 ("strong empirical candidate") labels mostly tag
# non-empirical articles in this dataset, so they are moved to Group 3
# (non-empirical). Name = label, value = reason (printed in the log and saved
# to mt_manual_label_decisions.csv). Set to character(0) to undo.
MANUAL_LABELS_TO_NON_EMPIRICAL <- c(
  consensus_development_conference =
    "tags consensus statements, recommendations and guideline development",
  clinical_conference =
    "tags narrative overviews, rationales and research agendas, not original studies"
)

# --- Sampling / export ---
SAMPLE_SIZE    <- 6000
# How the sample is drawn from the empirical articles (Step 6). In the
# stratified methods each journal is a stratum: the number of articles per
# journal is fixed first, then articles are drawn at random within journals.
#   "sqrt"     (chosen for Study 1) articles per journal proportional to the
#              square root of the journal's number of empirical articles:
#              every journal is sampled, large journals get more articles but
#              their dominance is dampened. This is a power allocation with
#              power 0.5 (Bankier MD, 1988, Power allocations: determining
#              sample sizes for subnational areas, The American Statistician
#              42(3), 174-177, https://www.jstor.org/stable/2684995)
#   "simple"   simple random sample - journals in proportion to their size
#              (the largest journals dominate; small ones may get none)
#   "balanced" equal cap per journal - the smallest cap that reaches
#              SAMPLE_SIZE (near-even number of articles per journal)
# A sampling_weight column (journal's empirical articles / articles sampled
# from it) is added, for re-weighting to field-level estimates.
SAMPLING_METHOD      <- "sqrt"
SQRT_MIN_PER_JOURNAL <- 0   # optional floor per journal for "sqrt" (0 = none)
RANDOM_SEED    <- 123
RIS_BATCH_SIZE <- 1000

# --- Optional reproduction check (Step 9) ---
# Point this at a previous run's folder (e.g. Pilot 1) to compare outputs.
# Set PUBLICATION_YEAR / NPI_LEVEL_YEAR / RUN_LABEL to that pilot's values first.
REFERENCE_DIRECTORY <- NA   # e.g. file.path(base_directory, "pilot-1")

# --- Journal classification file names (derived; no need to edit) ---
# Prefixed with the NPI level year (e.g. 2025journals_...), so this run's
# files sit next to the previous run's copy (e.g. 2023journals_...).
JOURNAL_FILE_PREFIX <- paste0(NPI_LEVEL_YEAR, "journals_")
JF_TO_CLASSIFY <- paste0(JOURNAL_FILE_PREFIX, "to_classify.csv")
JF_DRAFT       <- paste0(JOURNAL_FILE_PREFIX, "llm_classified_draft.csv")
JF_FINAL       <- paste0(JOURNAL_FILE_PREFIX, "llm_classified_final.csv")
JF_COMPARISON  <- paste0(JOURNAL_FILE_PREFIX, "vs_", PREVIOUS_LEVEL_YEAR, "_comparison.csv")
JF_CHANGES     <- paste0(JOURNAL_FILE_PREFIX, "vs_", PREVIOUS_LEVEL_YEAR, "_classification_changes.csv")
JF_MISSING     <- paste0(JOURNAL_FILE_PREFIX, "missing_classification.csv")


################################################################################
# HELPER FUNCTIONS
################################################################################

# Reconstruct abstract text from OpenAlex inverted-index format (0-based positions).
reconstruct_abstract <- function(inverted_index) {
  if (is.null(inverted_index) || length(inverted_index) == 0) return(NA_character_)
  tryCatch({
    max_pos <- max(unlist(inverted_index))
    words   <- character(max_pos + 1)
    for (word in names(inverted_index)) {
      for (pos in inverted_index[[word]]) words[pos + 1] <- word
    }
    paste(words[words != ""], collapse = " ")
  }, error = function(e) NA_character_)
}

safe_field <- function(x) if (is.null(x) || length(x) == 0) NA else x[[1]]

# Pull one field from a list of records as a character vector.
col_chr <- function(lst, key) vapply(lst, function(x) {
  v <- x[[key]]
  if (is.null(v) || length(v) == 0 || is.na(v[[1]])) NA_character_ else as.character(v[[1]])
}, character(1))

# Return, for each string, the name of the first pattern group it matches.
match_group <- function(x, groups) {
  reason <- rep(NA_character_, length(x))
  for (g in names(groups)) {
    pat <- paste(groups[[g]], collapse = "|")
    hit <- is.na(reason) & !is.na(x) & grepl(pat, x, ignore.case = TRUE, perl = TRUE)
    reason[hit] <- g
  }
  reason
}

section <- function(title) {
  cat("================================================================================\n")
  cat(title, "\n")
  cat("================================================================================\n\n")
}

has_value  <- function(x) !is.na(x) & str_trim(x) != "" & x != '""'
norm_issn  <- function(x) toupper(str_remove_all(coalesce(x, ""), "[^0-9Xx]"))
norm_title <- function(x) str_squish(str_replace_all(tolower(coalesce(x, "")), "[^a-z0-9]+", " "))
norm_doi   <- function(x) tolower(str_remove(x, "^https?://(dx\\.)?doi\\.org/"))
read_chr_csv <- function(f) read_csv(f, show_col_types = FALSE, col_types = cols(.default = "c"))

# Checkpoints. Before Steps 0, 1 and 3 run, the script checks for the CSVs
# that step saves. If they all exist and are newer than the files the step
# is built from, they are loaded and the step is skipped. A step re-runs
# automatically when an input changes (e.g. a new journal classification
# file re-runs Step 1, which re-runs Step 3). FORCE_RERUN = TRUE, or
# deleting one of the step's files, makes it run again.
outputs_current <- function(outputs, inputs = character(0)) {
  if (FORCE_RERUN || !all(file.exists(outputs))) return(FALSE)
  inputs <- inputs[file.exists(inputs)]
  length(inputs) == 0 || min(file.mtime(outputs)) >= max(file.mtime(inputs))
}
checkpoint_msg <- function(step, outputs) {
  cat(sprintf("CHECKPOINT: saved %s files found and up to date - loading them, %s is skipped:\n",
              step, step))
  for (f in outputs) cat(sprintf("  %-45s saved %s\n", f, format(file.mtime(f), "%Y-%m-%d %H:%M")))
  cat("  (Set FORCE_RERUN <- TRUE or delete one of these files to re-run the step.)\n\n")
}


################################################################################
# STEP 0: DOWNLOAD NPI REGISTER AND EXTRACT PSYCHOLOGY JOURNALS
################################################################################

STEP0_OUTPUTS <- c("psych_db.csv", "npi_summary.csv")
level_col     <- paste("Level", NPI_LEVEL_YEAR)

if (!REDOWNLOAD_NPI && outputs_current(STEP0_OUTPUTS, "NPI_Scientific_Journals.csv")) {
  section("STEP 0: NPI REGISTER - LOADING SAVED FILES")
  checkpoint_msg("Step 0", STEP0_OUTPUTS)
  psych_db    <- read_chr_csv("psych_db.csv")
  npi_summary <- read_chr_csv("npi_summary.csv")
  n_npi_entries      <- as.integer(npi_summary$n_npi_entries)
  header_fix_applied <- as.logical(npi_summary$header_fix_applied)
  npi_download_time  <- as.POSIXct(npi_summary$npi_download_time)
  if (!level_col %in% names(psych_db))
    stop(sprintf("Column '%s' not in psych_db.csv. Set FORCE_RERUN <- TRUE.", level_col))
  cat(sprintf("Total NPI entries:             %d\n", n_npi_entries))
  cat(sprintf("Psychology (English) journals: %d\n\n", nrow(psych_db)))
} else {
  section("STEP 0a: DOWNLOADING NPI REGISTER")
  
  npi_url    <- "https://kanalregister.hkdir.no/publiseringskanaler/csvliste/tidsskrift?request_locale=en"
  local_file <- "NPI_Scientific_Journals.csv"
  
  if (file.exists(local_file) && !REDOWNLOAD_NPI) {
    npi_download_time <- file.mtime(local_file)
    cat(sprintf("Reusing %s (downloaded %s). Set REDOWNLOAD_NPI <- TRUE to refresh.\n\n",
                local_file, format(npi_download_time, "%Y-%m-%d %H:%M")))
  } else {
    download_success <- tryCatch({
      download.file(npi_url, destfile = local_file, method = "auto", quiet = FALSE)
      TRUE
    }, error = function(e) { cat(sprintf("ERROR: %s\n", e$message)); FALSE })
    if (!download_success) stop("NPI download failed. Check internet connection and try again.")
    npi_download_time <- Sys.time()
  }
  
  # The NPI file is read with base R, not readr::read_delim(). In Sept 2026
  # read_delim() crashed the R session ("R Session Aborted") on this file under
  # R 4.1.2, and a plain read.table() stopped part-way with "invalid input found
  # on input connection" and "EOF within quoted string". The Sept 2026 file
  # contains (a) at least one line that is not valid UTF-8 and (b) at least one
  # line with an unmatched double quote. Either one silently truncates or
  # merges rows in a normal reader. read_npi() therefore:
  #   1. reads raw lines; re-encodes lines that are not valid UTF-8 from
  #      Windows-1252 (the usual cause: a stray Latin-1 character)
  #   2. parses lines with balanced quotes normally (quote = '"')
  #   3. parses lines with an odd number of quotes on their own, splitting on
  #      ";" and stripping surrounding quotes, so one stray quote cannot swallow
  #      the rest of the file
  #   4. checks that every data line became exactly one row
  # All repaired lines are printed so they can be checked by eye.
  # Output matches readr: all columns character; "" and "NA" read as NA.
  read_npi <- function(path) {
    lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
    
    # 1. Encoding repair
    bad_enc <- which(!validUTF8(lines))
    if (length(bad_enc) > 0) {
      fixed <- iconv(lines[bad_enc], from = "windows-1252", to = "UTF-8")
      fixed[is.na(fixed)] <- iconv(lines[bad_enc][is.na(fixed)], "UTF-8", "UTF-8", sub = "?")
      lines[bad_enc] <- fixed
    }
    Encoding(lines) <- "UTF-8"
    lines[1] <- sub("^(\ufeff|\u00ef\u00bb\u00bf)", "", lines[1])   # byte-order mark (as character or as bytes)
    keep     <- nzchar(trimws(lines))
    line_no  <- which(keep)                              # line numbers in the file
    bad_enc  <- intersect(bad_enc, line_no)
    lines    <- lines[keep]
    
    hdr  <- scan(text = lines[1], what = "character", sep = ";", quote = "\"",
                 quiet = TRUE, na.strings = character(0), encoding = "UTF-8")
    body <- lines[-1]
    body_line_no <- line_no[-1]
    
    # 2-3. Split balanced / unbalanced-quote lines
    odd  <- which(nchar(gsub("[^\"]", "", body)) %% 2 == 1)
    good <- setdiff(seq_along(body), odd)
    
    split_unquoted <- function(x) {
      f <- strsplit(x, ";", fixed = TRUE)[[1]]
      if (endsWith(x, ";")) f <- c(f, "")
      f <- sub("\"$", "", sub("^\"", "", f))
      gsub("\"\"", "\"", f, fixed = TRUE)
    }
    odd_rows <- lapply(body[odd], split_unquoted)
    
    n_fields_good <- count.fields(textConnection(body[good]), sep = ";", quote = "\"",
                                  comment.char = "", blank.lines.skip = FALSE)
    n_cols <- max(length(hdr), n_fields_good, lengths(odd_rows), na.rm = TRUE)
    col_names <- hdr
    if (n_cols > length(hdr)) col_names <- c(hdr, paste0("...", (length(hdr) + 1):n_cols))
    
    dat_good <- utils::read.table(text = body[good], sep = ";", quote = "\"", header = FALSE,
                                  col.names = col_names, check.names = FALSE,
                                  colClasses = "character", na.strings = c("", "NA"),
                                  comment.char = "", fill = TRUE, strip.white = FALSE,
                                  blank.lines.skip = FALSE, stringsAsFactors = FALSE,
                                  encoding = "UTF-8")
    # 4. Row check
    if (nrow(dat_good) != length(good))
      stop(sprintf("NPI parse error: %d lines gave %d rows. Open %s and check quoting.",
                   length(good), nrow(dat_good), path))
    
    m <- as.matrix(dat_good)
    if (length(odd) > 0) {
      m_odd <- do.call(rbind, lapply(odd_rows, function(f) { length(f) <- n_cols; f }))
      m_odd[!is.na(m_odd) & m_odd %in% c("", "NA")] <- NA
      m <- rbind(m, m_odd)[order(c(good, odd)), , drop = FALSE]
    }
    colnames(m) <- col_names
    
    # Report
    all_fields <- c(n_fields_good, lengths(odd_rows))
    cat(sprintf("Header fields: %d | fields per data row: %s\n", length(hdr),
                paste(sprintf("%s (%d rows)", names(table(all_fields)), table(all_fields)),
                      collapse = ", ")))
    if (length(bad_enc) > 0) {
      cat(sprintf("Re-encoded %d line(s) that were not valid UTF-8 (read as Windows-1252):\n",
                  length(bad_enc)))
      for (i in head(bad_enc, 10)) cat(sprintf("  line %d: %s\n", i,
                                               substr(lines[match(i, line_no)], 1, 120)))
    }
    if (length(odd) > 0) {
      cat(sprintf("Parsed %d line(s) with an unmatched quote separately - check these rows:\n",
                  length(odd)))
      for (i in head(odd, 10)) cat(sprintf("  line %d (%d fields): %s\n", body_line_no[i],
                                           length(odd_rows[[match(i, odd)]]),
                                           substr(body[i], 1, 120)))
      if (any(lengths(odd_rows) != length(hdr)))
        cat("  WARNING: some of these lines do not have the header's number of fields.\n")
    }
    
    tibble::as_tibble(as.data.frame(m, stringsAsFactors = FALSE, optional = TRUE),
                      .name_repair = "minimal")
  }
  
  full_db <- read_npi(local_file)
  cat(sprintf("Loaded: %d journal entries\n\n", nrow(full_db)))
  
  # --- 0b. Correct column headers ---------------------------------------------
  section("STEP 0b: CORRECTING COLUMN HEADERS")
  
  # As of Jan/Feb 2026 the NPI download had a one-position left-shift in the
  # header from publisher_id onwards (same number of fields, names misaligned).
  # The register may since have been fixed, so by default ("auto") the fix is
  # applied only if it makes the "Online ISSN" column look more like ISSNs.
  # Set TRUE / FALSE to force it. ALWAYS check the printed sample below.
  APPLY_HEADER_FIX   <- "auto"
  corrected_full_db  <- full_db
  original_names     <- names(full_db)
  publisher_id_index <- which(original_names == "publisher_id")
  
  issn_share <- function(df) {
    if (!"Online ISSN" %in% names(df)) return(0)
    x <- df[["Online ISSN"]]
    x <- x[!is.na(x) & x != ""]
    if (length(x) == 0) 0 else mean(grepl("^[0-9]{4}-?[0-9]{3}[0-9Xx]$", x))
  }
  
  shifted_db <- NULL
  if (length(publisher_id_index) > 0 && publisher_id_index < length(original_names)) {
    corrected_names <- original_names
    for (i in length(corrected_names):(publisher_id_index + 1)) {
      corrected_names[i] <- original_names[i - 1]
    }
    corrected_names[publisher_id_index] <- "UNKNOWN_BUT_IRRELEVANT"
    shifted_db <- full_db
    names(shifted_db) <- corrected_names
  }
  
  share_as_is   <- issn_share(full_db)
  share_shifted <- if (is.null(shifted_db)) NA else issn_share(shifted_db)
  cat(sprintf("Share of 'Online ISSN' values that look like ISSNs: as downloaded %.1f%% | with header fix %s\n",
              100 * share_as_is,
              if (is.na(share_shifted)) "n/a" else sprintf("%.1f%%", 100 * share_shifted)))
  
  use_fix <- if (identical(APPLY_HEADER_FIX, "auto")) {
    !is.null(shifted_db) && share_shifted > share_as_is
  } else isTRUE(APPLY_HEADER_FIX) && !is.null(shifted_db)
  
  if (use_fix) {
    corrected_full_db <- shifted_db
    cat("Column headers corrected (header shift still present).\n\n")
  } else {
    cat("Header correction not applied (columns already aligned).\n\n")
  }
  header_fix_applied <- use_fix
  
  level_col <- paste("Level", NPI_LEVEL_YEAR)
  if (!level_col %in% names(corrected_full_db)) {
    cat("Available level columns: ",
        paste(grep("^Level", names(corrected_full_db), value = TRUE), collapse = ", "), "\n")
    stop(sprintf("Column '%s' not found. Set NPI_LEVEL_YEAR to an available year.", level_col))
  }
  
  cat("Sample (first 5 journals, key columns) - check alignment:\n")
  corrected_full_db %>%
    select(`NPI Scientific Field`, Language, `International Title`,
           all_of(level_col), `Online ISSN`) %>%
    head(5) %>% print()
  cat("\n")
  
  # --- 0c. Extract Psychology (English) journals ------------------------------
  section("STEP 0c: EXTRACTING PSYCHOLOGY (ENGLISH) JOURNALS")
  
  psych_db <- corrected_full_db %>%
    filter(`NPI Scientific Field` == "Psychology", Language == "English")
  
  cat(sprintf("Total NPI entries:             %d\n", nrow(corrected_full_db)))
  cat(sprintf("Psychology (English) journals: %d\n\n", nrow(psych_db)))
  write_csv(psych_db, "psych_db.csv")
  
  n_npi_entries <- nrow(corrected_full_db)
  write_csv(tibble(n_npi_entries = n_npi_entries, header_fix_applied = header_fix_applied,
                   npi_download_time = format(npi_download_time, "%Y-%m-%d %H:%M:%S")),
            "npi_summary.csv")
}


################################################################################
# STEP 1: JOURNAL FILTERS
################################################################################

# Journal eligibility is applied in this order, one criterion at a time:
#   1a. NPI level 1 or 2 in NPI_LEVEL_YEAR  (only level 1-2 are eligible)
#   1b. Has an Online ISSN                  (only online ISSNs are used)
#   1c. Journal-title keyword filter        (applied to 1-2 with online ISSN)
#   1d-1f. Journal classification (LLM + manual review) of what remains
# Each excluded journal records the first stage it failed
# (excluded_psych_db.csv, column exclusion_stage).

STEP1_OUTPUTS <- c("filtered_psych_db.csv", "excluded_psych_db.csv", JF_COMPARISON,
                   JF_TO_CLASSIFY, JF_DRAFT, "journals_for_openalex.csv")
STEP1_INPUTS  <- c("psych_db.csv", JF_FINAL, PREVIOUS_JOURNAL_CLASSIFICATION)
previous_source <- PREVIOUS_RUN_LABEL
journal_classification_changes <- NULL

if (file.exists(JF_FINAL) && outputs_current(STEP1_OUTPUTS, STEP1_INPUTS)) {
  section("STEP 1: JOURNAL FILTERS - LOADING SAVED FILES")
  checkpoint_msg("Step 1", STEP1_OUTPUTS)
  filtered_psych_db     <- read_chr_csv("filtered_psych_db.csv")
  excluded_psych_db     <- read_chr_csv("excluded_psych_db.csv")
  journal_comparison    <- read_chr_csv(JF_COMPARISON)
  journals_to_classify  <- read_chr_csv(JF_TO_CLASSIFY)
  journals_carried_over <- read_chr_csv(JF_DRAFT)
  journals_for_openalex <- read_chr_csv("journals_for_openalex.csv")
  if (JOURNAL_RECLASSIFY_ALL && file.exists(JF_CHANGES))
    journal_classification_changes <- read_chr_csv(JF_CHANGES)
  n_dropped <- sum(journal_comparison$status == "dropped_from_current_list")
  cat("Excluded journals by stage:\n")
  print(count(excluded_psych_db, exclusion_stage))
  cat(sprintf("\nJournals after keyword filter:  %d\n", nrow(filtered_psych_db)))
  cat(sprintf("Journals retained for OpenAlex: %d\n\n", nrow(journals_for_openalex)))
} else {
  # --- 1a. Level 1-2 -----------------------------------------------------------
  section("STEP 1a: NPI LEVEL 1-2")
  
  level_eligible_db <- psych_db %>% filter(.data[[level_col]] %in% c("1", "2"))
  
  cat(sprintf("Psychology (English) journals:  %d\n", nrow(psych_db)))
  cat(sprintf("Level 1-2 in %s:          %d\n", NPI_LEVEL_YEAR, nrow(level_eligible_db)))
  cat("Level distribution (all psychology journals):\n")
  print(count(psych_db, level = .data[[level_col]]))
  cat("\n")
  
  # --- 1b. Online ISSN ---------------------------------------------------------
  section("STEP 1b: ONLINE ISSN")
  
  issn_eligible_db <- level_eligible_db %>% filter(has_value(`Online ISSN`))
  
  cat(sprintf("Level 1-2 journals:             %d\n", nrow(level_eligible_db)))
  cat(sprintf("  with Online ISSN:             %d\n", nrow(issn_eligible_db)))
  cat(sprintf("  without Online ISSN (excl.):  %d\n\n",
              nrow(level_eligible_db) - nrow(issn_eligible_db)))
  
  # --- 1c. Journal-title keyword filter ----------------------------------------
  section("STEP 1c: JOURNAL-TITLE KEYWORD FILTER")
  
  # Journal-title keywords suggesting predominantly non-empirical content.
  non_empirical_pattern <- regex(
    paste(collapse = "|", c(
      "REVIEW", "OVERVIEW", "ANNUAL",
      "OPINION", "COMMENTARY", "COMMENT", "PERSPECTIVES", "VIEWPOINT",
      "TRENDS", "DIRECTIONS", "FRONTIERS", "HORIZON", "COMPASS",
      "THEORY", "THEORETICAL",
      "ADVANCES", "ADVANCING", "PROGRESS",
      "BULLETIN", "BRIEF", "NEWS", "NEWSLETTER", "REPORT",
      "PROCEEDINGS", "CONFERENCE",
      "FORUM", "DEBATE", "CURRENT", "CONTEMPORARY", "EMERGING",
      "HANDBOOK", "ENCYCLOPEDIA", "ENCYCLOPAEDIA",
      "GUIDELINE", "GUIDELINES"   # guideline journals (cf. MultiTagger practice_guideline)
    )),
    ignore_case = TRUE
  )
  
  keyword_hit <- function(x) str_detect(coalesce(x, ""), non_empirical_pattern)
  filtered_psych_db <- issn_eligible_db %>%
    filter(!keyword_hit(`Original Title`), !keyword_hit(`International Title`))
  
  cat(sprintf("Level 1-2 with Online ISSN:     %d\n", nrow(issn_eligible_db)))
  cat(sprintf("  excluded by keyword:          %d\n", nrow(issn_eligible_db) - nrow(filtered_psych_db)))
  cat(sprintf("  remaining for classification: %d\n\n", nrow(filtered_psych_db)))
  
  excluded_psych_db <- psych_db %>%
    mutate(exclusion_stage = case_when(
      !.data[[level_col]] %in% c("1", "2") ~ "1a: not level 1-2",
      !has_value(`Online ISSN`)             ~ "1b: no Online ISSN",
      keyword_hit(`Original Title`) | keyword_hit(`International Title`) ~ "1c: title keyword",
      TRUE ~ NA_character_
    )) %>%
    filter(!is.na(exclusion_stage)) %>%
    relocate(exclusion_stage)
  
  cat("Excluded journals by stage:\n")
  print(count(excluded_psych_db, exclusion_stage))
  cat("\n")
  
  write_csv(filtered_psych_db, "filtered_psych_db.csv")
  write_csv(excluded_psych_db, "excluded_psych_db.csv")
  
  # --- 1d. Compare this run's journal list with the previous classification ---
  section("STEP 1d: COMPARING JOURNAL LIST WITH PREVIOUS CLASSIFICATION")
  
  # The journal classification file used in Pilot 2 was built from the NPI
  # level 1-2 list for 2023. The level 1-2 list for NPI_LEVEL_YEAR can differ
  # (journals added, dropped, or moved level), so this step:
  #   - matches the current journal list to the previous classification by
  #     Online ISSN (normalised: digits/X only, upper case)
  #   - carries over the previous classification for journals in both lists
  #   - lists journals that are new (need LLM classification + manual review)
  #   - lists journals that dropped out of the list, with the likely reason
  #   - flags new journals whose title matches a dropped journal (probable
  #     ISSN change: check these before classifying them from scratch)
  # Set JOURNAL_RECLASSIFY_ALL <- TRUE to send every journal to the LLM instead;
  # the previous calls are then used only for comparison (Step 1f).
  
  required_cols <- c("Online ISSN", "International Title", "publishes_original_research",
                     "confidence", "manual_review", "final_empirical_no")
  check_cols <- function(df, file) {
    missing <- setdiff(required_cols, colnames(df))
    if (length(missing) > 0)
      stop(sprintf("%s is missing column(s): %s", file, paste(missing, collapse = ", ")))
  }
  
  if (!file.exists(PREVIOUS_JOURNAL_CLASSIFICATION))
    stop("Previous journal classification not found:\n  ", PREVIOUS_JOURNAL_CLASSIFICATION,
         "\nSet PREVIOUS_JOURNAL_CLASSIFICATION in the configuration.")
  
  previous_classified <- read_csv(PREVIOUS_JOURNAL_CLASSIFICATION, show_col_types = FALSE,
                                  col_types = cols(.default = "c"))
  check_cols(previous_classified, basename(PREVIOUS_JOURNAL_CLASSIFICATION))
  previous_classified <- previous_classified %>% mutate(issn_key = norm_issn(`Online ISSN`))
  if (any(duplicated(previous_classified$issn_key)))
    cat(sprintf("NOTE: %d duplicated ISSN(s) in the previous file; first row used.\n\n",
                sum(duplicated(previous_classified$issn_key))))
  previous_classified <- previous_classified %>% distinct(issn_key, .keep_all = TRUE)
  
  # Keep a copy of the previous file next to this run's files, named by its
  # level year (e.g. 2023journals_llm_classified_final.csv), for side-by-side
  # comparison. Not made if it would overwrite this run's own final file.
  previous_copy <- file.path(output_directory,
                             paste0(PREVIOUS_LEVEL_YEAR, "journals_llm_classified_final.csv"))
  if (basename(previous_copy) != JF_FINAL &&
      normalizePath(previous_copy, mustWork = FALSE) !=
      normalizePath(PREVIOUS_JOURNAL_CLASSIFICATION, mustWork = FALSE)) {
    file.copy(PREVIOUS_JOURNAL_CLASSIFICATION, previous_copy, overwrite = TRUE)
    cat(sprintf("Copied previous classification to: %s\n\n", basename(previous_copy)))
  }
  
  current_journals <- filtered_psych_db %>% mutate(issn_key = norm_issn(`Online ISSN`))
  
  # Where do journals that dropped out of the list sit in the current NPI?
  # Matched by Online ISSN first; journals that lost or changed their Online
  # ISSN are matched by title instead.
  psych_lookup <- psych_db %>%
    mutate(issn_key = norm_issn(`Online ISSN`)) %>%
    filter(issn_key != "") %>%
    distinct(issn_key, .keep_all = TRUE) %>%
    transmute(issn_key, level_now = .data[[level_col]], in_psych_db = TRUE)
  psych_title_lookup <- psych_db %>%
    mutate(title_key = norm_title(`International Title`)) %>%
    filter(title_key != "") %>%
    distinct(title_key, .keep_all = TRUE) %>%
    transmute(title_key, level_now_by_title = .data[[level_col]],
              online_issn_now = `Online ISSN`, in_psych_db_by_title = TRUE)
  
  journal_comparison <- full_join(
    current_journals %>%
      transmute(issn_key, in_current = TRUE, current_title = `International Title`,
                current_issn = `Online ISSN`, current_level = .data[[level_col]]),
    previous_classified %>%
      transmute(issn_key, in_previous = TRUE, previous_title = `International Title`,
                previous_issn = `Online ISSN`,
                previous_publishes_original_research = publishes_original_research,
                previous_confidence = confidence,
                previous_final_empirical_no = final_empirical_no),
    by = "issn_key"
  ) %>%
    mutate(title_key = norm_title(coalesce(current_title, previous_title))) %>%
    left_join(psych_lookup, by = "issn_key") %>%
    left_join(psych_title_lookup, by = "title_key") %>%
    mutate(
      in_current  = coalesce(in_current, FALSE),
      in_previous = coalesce(in_previous, FALSE),
      status = case_when(
        in_current & in_previous ~ "in_both",
        in_current               ~ "new_in_current_list",
        TRUE                     ~ "dropped_from_current_list"
      ),
      # Same order as Steps 1a-1c: level, then Online ISSN, then keyword.
      level_found = coalesce(level_now, level_now_by_title),
      dropped_reason = case_when(
        status != "dropped_from_current_list" ~ NA_character_,
        is.na(in_psych_db) & is.na(in_psych_db_by_title) ~
          "not found among Psychology (English) journals in current NPI",
        !coalesce(level_found, "") %in% c("1", "2") ~
          paste0("1a: ", level_col, " = ", coalesce(na_if(level_found, ""), "none")),
        is.na(in_psych_db) & !has_value(online_issn_now) ~ "1b: no Online ISSN in current NPI",
        is.na(in_psych_db) ~ paste0("Online ISSN changed (now ", online_issn_now, ")"),
        TRUE ~ "1c: journal-title keyword filter"
      )
    ) %>%
    select(-level_now, -level_now_by_title, -online_issn_now, -in_psych_db_by_title)
  
  # Probable ISSN changes: new journal with the same title as a dropped one.
  dropped_titles <- journal_comparison %>%
    filter(status == "dropped_from_current_list", title_key != "") %>%
    select(title_key, possible_previous_issn = previous_issn)
  journal_comparison <- journal_comparison %>%
    left_join(dropped_titles %>% distinct(title_key, .keep_all = TRUE), by = "title_key") %>%
    mutate(possible_previous_issn = if_else(status == "new_in_current_list",
                                            possible_previous_issn, NA_character_)) %>%
    select(-title_key, -in_psych_db) %>%
    arrange(status, coalesce(current_title, previous_title))
  
  write_csv(journal_comparison, JF_COMPARISON)
  
  n_in_both <- sum(journal_comparison$status == "in_both")
  n_new     <- sum(journal_comparison$status == "new_in_current_list")
  n_dropped <- sum(journal_comparison$status == "dropped_from_current_list")
  cat(sprintf("Previous classification (%s):  %d journals\n", previous_source, nrow(previous_classified)))
  cat(sprintf("Current list (%s 1-2):   %d journals\n", level_col, nrow(current_journals)))
  cat(sprintf("  In both (classification carried over): %d\n", n_in_both))
  cat(sprintf("  New (need classification):             %d\n", n_new))
  cat(sprintf("    of which title matches a dropped journal (check ISSN change): %d\n",
              sum(!is.na(journal_comparison$possible_previous_issn))))
  cat(sprintf("  Dropped from list:                     %d\n", n_dropped))
  if (n_dropped > 0) {
    cat("\nDropped journals by reason:\n")
    journal_comparison %>% filter(status == "dropped_from_current_list") %>%
      count(dropped_reason, sort = TRUE) %>% print()
  }
  cat(sprintf("\nSaved: %s\n\n", JF_COMPARISON))
  
  # Files for the classification step:
  #   JF_TO_CLASSIFY  journals to send to the LLM (new since the previous list,
  #                   or all journals if JOURNAL_RECLASSIFY_ALL = TRUE). Same
  #                   columns as the previous classification file.
  #   JF_DRAFT        journals carried over from the previous file, with their
  #                   previous classification. The classified JF_TO_CLASSIFY
  #                   rows are appended to this and saved as JF_FINAL.
  classification_cols <- setdiff(names(previous_classified), "issn_key")
  to_classify_keys <- if (JOURNAL_RECLASSIFY_ALL) current_journals$issn_key else
    journal_comparison$issn_key[journal_comparison$status == "new_in_current_list"]
  
  journals_to_classify <- current_journals %>% filter(issn_key %in% to_classify_keys)
  for (col in setdiff(classification_cols, names(journals_to_classify)))
    journals_to_classify[[col]] <- NA_character_
  journals_to_classify <- journals_to_classify %>%
    select(all_of(classification_cols)) %>%
    mutate(across(any_of(c("publishes_original_research", "confidence",
                           "manual_review", "final_empirical_no")), ~ NA_character_))
  
  journals_carried_over <- previous_classified %>%
    filter(issn_key %in% current_journals$issn_key, !issn_key %in% to_classify_keys) %>%
    select(all_of(classification_cols)) %>%
    arrange(`International Title`)
  
  write_csv(journals_to_classify,  JF_TO_CLASSIFY)
  write_csv(journals_carried_over, JF_DRAFT)
  cat(sprintf("Saved: %s (%d journals to classify)\n", JF_TO_CLASSIFY, nrow(journals_to_classify)))
  cat(sprintf("Saved: %s (%d journals carried over from %s)\n\n", JF_DRAFT,
              nrow(journals_carried_over), previous_source))
  
  # --- 1e. Journal classification (manual LLM step) ---------------------------
  section("STEP 1e: CHECKING FOR JOURNAL CLASSIFICATION FILE")
  
  classified_file <- file.path(output_directory, JF_FINAL)
  if (!file.exists(classified_file)) {
    cat(">>> MANUAL STEP: journal classification\n")
    cat(sprintf("    1. Classify %s with the prompt in\n", JF_TO_CLASSIFY))
    cat("       JOURNAL_CLASSIFICATION_README.md, then review manually as in Pilot 2.\n")
    cat(sprintf("    2. Append the classified rows to %s\n", JF_DRAFT))
    cat(sprintf("    3. Save the result as %s in:\n", JF_FINAL))
    cat("      ", output_directory, "\n\n")
    stop("Stopping. Re-run after saving ", JF_FINAL, ".")
  }
  
  # --- 1f. Apply journal classification exclusions ----------------------------
  section("STEP 1f: APPLYING JOURNAL CLASSIFICATION EXCLUSIONS")
  
  # Exclusion rule (as in Pilot 2): final_empirical_no = "yes" excludes a
  # journal; blank or "no" keeps it. For journals classified in this run, a
  # blank final_empirical_no is filled with the Pilot 2 rule (LLM 'no' with
  # medium/high confidence = "yes"). Carried-over rows are used as they are.
  # Journals found not to fit after review can be excluded later by setting
  # final_empirical_no = "yes" and manual_review = "yes" in JF_FINAL.
  
  cat(sprintf("Using: %s (last modified %s)\n\n", JF_FINAL,
              format(file.mtime(classified_file), "%Y-%m-%d %H:%M")))
  journals_llm_classified <- read_csv(classified_file, show_col_types = FALSE,
                                      col_types = cols(.default = "c"))
  check_cols(journals_llm_classified, JF_FINAL)
  
  blank <- function(x) is.na(x) | str_trim(x) == ""
  journals_llm_classified <- journals_llm_classified %>%
    mutate(
      issn_key            = norm_issn(`Online ISSN`),
      classified_this_run = issn_key %in% to_classify_keys,
      final_empirical_no  = case_when(
        !blank(final_empirical_no) ~ tolower(str_trim(final_empirical_no)),
        classified_this_run & tolower(publishes_original_research) == "no" &
          tolower(confidence) %in% c("medium", "high") ~ "yes",
        TRUE ~ "no"
      )
    )
  
  # Checks: every journal in the current list appears once, and every journal
  # classified in this run has an LLM classification.
  dup_keys <- journals_llm_classified$issn_key[duplicated(journals_llm_classified$issn_key)]
  if (length(dup_keys) > 0) {
    cat("Journals listed more than once in", JF_FINAL, ":\n")
    print(journals_llm_classified %>% filter(issn_key %in% dup_keys) %>%
            select(`International Title`, `Online ISSN`, publishes_original_research))
    stop("Remove the duplicate rows from ", JF_FINAL, " and re-run.")
  }
  journals_missing_classification <- current_journals %>%
    filter(!issn_key %in% journals_llm_classified$issn_key |
             issn_key %in% journals_llm_classified$issn_key[
               journals_llm_classified$classified_this_run &
                 blank(journals_llm_classified$publishes_original_research)]) %>%
    select(-issn_key)
  if (nrow(journals_missing_classification) > 0) {
    write_csv(journals_missing_classification, JF_MISSING)
    cat(sprintf("%d journal(s) in the current list are missing or unclassified in %s:\n",
                nrow(journals_missing_classification), JF_FINAL))
    for (j in head(journals_missing_classification$`International Title`, 30)) cat("  -", j, "\n")
    stop("Classify these (see ", JF_MISSING, ") and re-run.")
  }
  
  cat(sprintf("Journals in %s: %d (%d carried over, %d classified this run)\n\n", JF_FINAL,
              nrow(journals_llm_classified),
              sum(!journals_llm_classified$classified_this_run),
              sum(journals_llm_classified$classified_this_run)))
  
  # Only when every journal was re-classified: compare with the previous calls.
  if (JOURNAL_RECLASSIFY_ALL) {
    journal_classification_changes <- journals_llm_classified %>%
      transmute(issn_key, `International Title`, `Online ISSN`,
                publishes_now = publishes_original_research, confidence_now = confidence,
                final_empirical_no_now = final_empirical_no) %>%
      inner_join(previous_classified %>%
                   transmute(issn_key, publishes_before = publishes_original_research,
                             confidence_before = confidence,
                             final_empirical_no_before = if_else(blank(final_empirical_no), "no",
                                                                 tolower(str_trim(final_empirical_no)))),
                 by = "issn_key") %>%
      filter(tolower(coalesce(publishes_now, "")) != tolower(coalesce(publishes_before, "")) |
               final_empirical_no_now != final_empirical_no_before) %>%
      select(-issn_key)
    write_csv(journal_classification_changes, JF_CHANGES)
    cat(sprintf("Re-classified journals whose call differs from %s: %d of %d (saved: %s)\n\n",
                previous_source, nrow(journal_classification_changes), n_in_both, JF_CHANGES))
  }
  
  low_confidence_no <- journals_llm_classified %>%
    filter(tolower(publishes_original_research) == "no", tolower(confidence) == "low")
  if (nrow(low_confidence_no) > 0) {
    cat(sprintf("NOTE: %d journal(s) classified 'no' with low confidence - retained.\n\n",
                nrow(low_confidence_no)))
  }
  
  excluded_keys <- journals_llm_classified$issn_key[which(journals_llm_classified$final_empirical_no == "yes")]
  journals_for_openalex <- filtered_psych_db %>%
    filter(!norm_issn(`Online ISSN`) %in% excluded_keys)
  n_journals_excluded_classification <- nrow(filtered_psych_db) - nrow(journals_for_openalex)
  
  cat(sprintf("Journals after keyword filter:          %d\n", nrow(filtered_psych_db)))
  cat(sprintf("Journals excluded by classification:    %d\n", n_journals_excluded_classification))
  cat(sprintf("Journals retained for OpenAlex:         %d\n\n", nrow(journals_for_openalex)))
  
  write_csv(journals_for_openalex, "journals_for_openalex.csv")
}

# Counts for the summary report (same whether computed or loaded)
n_level_eligible <- nrow(psych_db) - sum(excluded_psych_db$exclusion_stage == "1a: not level 1-2")
n_issn_eligible  <- n_level_eligible - sum(excluded_psych_db$exclusion_stage == "1b: no Online ISSN")
n_journals_excluded_classification <- nrow(filtered_psych_db) - nrow(journals_for_openalex)


################################################################################
# STEP 2: DOWNLOAD ARTICLES FROM OPENALEX
################################################################################

section("STEP 2: DOWNLOADING ARTICLES FROM OPENALEX")

issns <- journals_for_openalex %>%
  filter(!is.na(`Online ISSN`) & `Online ISSN` != "") %>%
  pull(`Online ISSN`) %>% unique()

issn_batches <- split(issns, ceiling(seq_along(issns) / ISSN_BATCH_SIZE))
cat(sprintf("ISSNs: %d in %d batch(es); year %d; type %s; language %s\n\n",
            length(issns), length(issn_batches), PUBLICATION_YEAR, DOCUMENT_TYPE, LANGUAGE))

# One GET with retries and exponential back-off. Stops (rather than skipping
# the batch) if the request keeps failing, so a partial download is never
# mistaken for a complete one.
openalex_get <- function(query) {
  for (attempt in seq_len(MAX_RETRIES)) {
    resp <- tryCatch(GET("https://api.openalex.org/works", query = query, timeout(60)),
                     error = function(e) NULL)
    if (!is.null(resp) && status_code(resp) == 200) return(resp)
    code <- if (is.null(resp)) "no response" else status_code(resp)
    cat(sprintf("    attempt %d failed (%s); retrying...\n", attempt, code))
    Sys.sleep(REQUEST_DELAY * 2^attempt)
  }
  stop("OpenAlex request failed after ", MAX_RETRIES, " attempts. Re-run Step 2.")
}

parse_article <- function(article) {
  src <- article$primary_location$source
  first_page <- safe_field(article$biblio$first_page)
  last_page  <- safe_field(article$biblio$last_page)
  pages <- if (!is.na(first_page) && !is.na(last_page)) paste0(first_page, "-", last_page)
  else if (!is.na(first_page)) first_page else NA
  
  authors <- NA
  if (length(article$authorships) > 0) {
    author_names <- unlist(lapply(article$authorships,
                                  function(a) safe_field(a$author$display_name)))
    author_names <- author_names[!is.na(author_names)]
    authors <- if (length(author_names) == 1) author_names[1]
    else if (length(author_names) == 2) paste(author_names, collapse = " and ")
    else if (length(author_names) > 2) paste0(author_names[1], " et al.")
    else NA
  }
  
  list(
    openalex_id  = safe_field(article$id),
    doi          = safe_field(article$doi),
    title        = safe_field(article$display_name),
    journal      = if (!is.null(src$display_name)) src$display_name else NA,
    source_id    = if (!is.null(src$id)) src$id else NA,
    source_issns = if (length(src$issn) > 0) paste(unlist(src$issn), collapse = "|") else NA,
    abstract     = if (!is.null(article$abstract_inverted_index))
      reconstruct_abstract(article$abstract_inverted_index) else NA,
    year         = safe_field(article$publication_year),
    volume       = safe_field(article$biblio$volume),
    issue        = safe_field(article$biblio$issue),
    pages        = pages,
    authors      = authors
  )
}

# Raw download saved as an R object so later runs can skip Step 2. It is
# reused if it was made with the same year / type / language and covers
# every ISSN in the current journal list. If the journal list has since
# shrunk (e.g. journals excluded after review), the saved
# articles are filtered to the current ISSNs. New ISSNs need a new download.
OPENALEX_RAW_FILE <- sprintf("openalex_articles_raw_%d.rds", PUBLICATION_YEAR)
openalex_settings <- list(year = PUBLICATION_YEAR, type = DOCUMENT_TYPE, language = LANGUAGE)

# One-time migration: runs made before the raw file existed saved every
# downloaded article in articles_master.csv (with the original OpenAlex
# abstract in abstract_openalex). If that file exists, the raw file is
# rebuilt from it instead of downloading again.
if (!file.exists(OPENALEX_RAW_FILE) && !REDOWNLOAD_OPENALEX &&
    file.exists("articles_master.csv")) {
  master_old <- read_csv("articles_master.csv", show_col_types = FALSE,
                         col_types = cols(.default = "c"))
  raw_cols <- c("openalex_id", "doi", "title", "journal", "source_id", "source_issns",
                "abstract", "year", "volume", "issue", "pages", "authors")
  if ("abstract_openalex" %in% names(master_old)) master_old$abstract <- master_old$abstract_openalex
  if (all(raw_cols %in% names(master_old))) {
    rebuilt <- do.call(Map, c(list(f = function(...) list(...)), as.list(master_old[raw_cols])))
    names(rebuilt) <- NULL
    saveRDS(list(articles = rebuilt, counts = NA_integer_, issns = issns,
                 settings = openalex_settings,
                 download_time = file.mtime("articles_master.csv")),
            OPENALEX_RAW_FILE)
    cat(sprintf("Rebuilt %s from articles_master.csv (%d articles) - no re-download needed.\n",
                OPENALEX_RAW_FILE, length(rebuilt)))
    cat("  (Assumes articles_master.csv came from the current journal list.)\n\n")
  }
  rm(master_old)
}

if (file.exists(OPENALEX_RAW_FILE) && !REDOWNLOAD_OPENALEX) {
  openalex_raw <- readRDS(OPENALEX_RAW_FILE)
  if (!identical(openalex_raw$settings, openalex_settings))
    stop(OPENALEX_RAW_FILE, " was made with different year/type/language settings. ",
         "Set REDOWNLOAD_OPENALEX <- TRUE (or delete the file) to download again.")
  new_issns <- setdiff(issns, openalex_raw$issns)
  if (length(new_issns) > 0) {
    cat(sprintf("%d ISSN(s) in the journal list were not in the saved download:\n",
                length(new_issns)))
    print(journals_for_openalex %>% filter(`Online ISSN` %in% new_issns) %>%
            select(`International Title`, `Online ISSN`))
    stop("Set REDOWNLOAD_OPENALEX <- TRUE (or delete ", OPENALEX_RAW_FILE,
         ") to download again.")
  }
  all_articles    <- openalex_raw$articles
  openalex_counts <- openalex_raw$counts
  openalex_download_time <- openalex_raw$download_time
  dropped_issns <- setdiff(openalex_raw$issns, issns)
  if (length(dropped_issns) > 0) {
    keep <- vapply(all_articles, function(a) {
      any(strsplit(coalesce(a$source_issns, ""), "|", fixed = TRUE)[[1]] %in% issns)
    }, logical(1))
    all_articles <- all_articles[keep]
    cat(sprintf("Journal list is smaller than at download: %d ISSN(s) dropped, %d articles removed.\n",
                length(dropped_issns), sum(!keep)))
  }
  cat(sprintf("Reusing %s (downloaded %s): %d articles.\n",
              OPENALEX_RAW_FILE, format(openalex_download_time, "%Y-%m-%d %H:%M"),
              length(all_articles)))
  cat("Set REDOWNLOAD_OPENALEX <- TRUE to download again.\n\n")
} else {
  all_articles     <- list()
  openalex_counts  <- integer(0)   # records per batch reported by OpenAlex
  
  for (batch_num in seq_along(issn_batches)) {
    batch_issns   <- issn_batches[[batch_num]]
    filter_string <- paste0(
      "primary_location.source.issn:", paste(batch_issns, collapse = "|"),
      ",publication_year:", PUBLICATION_YEAR,
      ",type:",             DOCUMENT_TYPE,
      ",language:",         LANGUAGE
    )
    cat(sprintf("Batch %d / %d (%d ISSNs):\n", batch_num, length(issn_batches), length(batch_issns)))
    
    # Cursor paging (page= paging is capped at 10,000 results per query).
    cursor        <- "*"
    batch_fetched <- 0
    repeat {
      query <- list(filter = filter_string, `per-page` = ARTICLES_PER_PAGE, cursor = cursor)
      if (nzchar(OPENALEX_MAILTO))  query$mailto  <- OPENALEX_MAILTO
      if (nzchar(OPENALEX_API_KEY)) query$api_key <- OPENALEX_API_KEY
      
      parsed <- fromJSON(content(openalex_get(query), as = "text", encoding = "UTF-8"),
                         simplifyVector = FALSE)
      if (cursor == "*") openalex_counts[batch_num] <- parsed$meta$count
      if (length(parsed$results) == 0) break
      
      all_articles <- c(all_articles, lapply(parsed$results, parse_article))
      batch_fetched <- batch_fetched + length(parsed$results)
      cursor <- parsed$meta$next_cursor
      if (is.null(cursor)) break
      Sys.sleep(REQUEST_DELAY)
    }
    
    cat(sprintf("  fetched %d of %d reported\n", batch_fetched, openalex_counts[batch_num]))
    if (batch_fetched != openalex_counts[batch_num])
      cat("  WARNING: fetched count differs from OpenAlex's reported count.\n")
  }
  
  openalex_download_time <- Sys.time()
  saveRDS(list(articles = all_articles, counts = openalex_counts, issns = issns,
               settings = openalex_settings, download_time = openalex_download_time),
          OPENALEX_RAW_FILE)
  cat(sprintf("\nDownload complete: %d articles (OpenAlex reported %d)\n",
              length(all_articles), sum(openalex_counts)))
  cat(sprintf("Saved: %s (reused on later runs)\n\n", OPENALEX_RAW_FILE))
}
total_fetched <- length(all_articles)


################################################################################
# STEP 3: CLEAN ENTRIES, TITLES AND ABSTRACTS; COUNT PER JOURNAL
#
# All cleaning happens here, before classification:
#   3a. Convert to data frame
#   3b. Record cleaning (missing title, missing/duplicate DOI)
#   3b2. Recover missing abstracts from PubMed
#   3c. Abstract cleaning (missing, boilerplate, too short, duplicated, garbled)
#   3c2. Title screening (front matter, notices, editorials, announcements)
#   3d. Per-journal counts and OpenAlex indexing checks
#   3e. Save
#   3f. Exclusions by journal (exclusions_by_journal.csv)
################################################################################

STEP3_OUTPUTS <- c("articles_master.csv", "articles_for_classification.csv",
                   "journal_article_counts.csv", "journals_poorly_indexed.csv",
                   "issns_without_openalex_articles.csv")
STEP3_INPUTS  <- c(OPENALEX_RAW_FILE, "journals_for_openalex.csv")

step3_saved_is_current_layout <- file.exists("articles_master.csv") &&
  "title_screen_reason" %in% names(read_csv("articles_master.csv", n_max = 0,
                                            show_col_types = FALSE))
if (step3_saved_is_current_layout && outputs_current(STEP3_OUTPUTS, STEP3_INPUTS)) {
  section("STEP 3: CLEANING - LOADING SAVED FILES")
  checkpoint_msg("Step 3", STEP3_OUTPUTS)
  articles_df                 <- read_chr_csv("articles_master.csv")
  articles_for_classification <- read_chr_csv("articles_for_classification.csv")
  journal_article_counts      <- read_csv("journal_article_counts.csv", show_col_types = FALSE)
  journals_poorly_indexed     <- read_csv("journals_poorly_indexed.csv", show_col_types = FALSE)
  issns_without_articles      <- read_chr_csv("issns_without_openalex_articles.csv")
  cat("Articles by cleaning outcome:\n")
  print(count(articles_df, status) %>% mutate(pct = round(100 * n / sum(n), 1)))
  cat(sprintf("\nArticles for classification: %d of %d downloaded\n\n",
              nrow(articles_for_classification), nrow(articles_df)))
} else {
  # --- 3a. Convert to data frame -----------------------------------------------
  section("STEP 3a: CONVERTING ARTICLE LIST TO DATA FRAME")
  
  articles_df <- tibble(
    openalex_id  = col_chr(all_articles, "openalex_id"),
    doi          = col_chr(all_articles, "doi"),
    title        = col_chr(all_articles, "title"),
    journal      = col_chr(all_articles, "journal"),
    source_id    = col_chr(all_articles, "source_id"),
    source_issns = col_chr(all_articles, "source_issns"),
    abstract     = col_chr(all_articles, "abstract"),
    year         = as.integer(col_chr(all_articles, "year")),
    volume       = col_chr(all_articles, "volume"),
    issue        = col_chr(all_articles, "issue"),
    pages        = col_chr(all_articles, "pages"),
    authors      = col_chr(all_articles, "authors")
  ) %>%
    mutate(
      journal  = coalesce(journal, "(no journal name)"),
      doi_key  = tolower(str_remove(doi, "^https?://(dx\\.)?doi\\.org/")),
      abstract = str_squish(abstract)
    )
  
  cat(sprintf("Articles: %d | with abstract: %.1f%%\n\n",
              nrow(articles_df), 100 * mean(!is.na(articles_df$abstract))))
  
  # Spot-check abstract reconstruction (first, middle, last).
  for (i in unique(c(1, ceiling(nrow(articles_df) / 2), nrow(articles_df))))
    cat(sprintf("[%d] %s\n\n", i, str_trunc(coalesce(articles_df$abstract[i], "NA"), 200)))
  
  # --- 3b. Record cleaning -----------------------------------------------------
  section("STEP 3b: RECORD CLEANING (MISSING / DUPLICATE ENTRIES)")
  
  # Order of Step 3 (sourcing and cleaning first, content filters after):
  #   3b  record cleaning: missing title, missing/duplicate DOI, title = journal name
  #   3b2 missing abstracts recovered from PubMed
  #   3c  abstract checks: missing / unusable abstracts
  #   3c2 title screening: non-research entries (front matter, notices,
  #       editorials, announcements ...), applied to articles with a usable abstract
  # The title patterns are defined here; the screening itself is Step 3c2.
  #
  # Title patterns, matched case-insensitively against ARTICLE TITLES only.
  # Groups are checked in order; each excluded article gets the first matching
  # group as its title_screen_reason (saved, so false positives can be audited).
  #
  # Notes on the patterns:
  #   - "front_matter" catches non-article entries that OpenAlex types as
  #     "article" (Issue Information, Table of Contents, Masthead, covers,
  #     editorial boards, reviewer thank-yous).
  #   - Advertisements are matched only as whole titles ("^ads?$", "^ad:"):
  #     a plain "\\bad\\b" would also match "AD" (Alzheimer's disease).
  #   - "notice" is anchored ("^notice"), since it is a common verb in
  #     empirical titles (e.g. "Do children notice ...").
  #   - "correction" is anchored ("^correction", "correction to"), since
  #     "error correction", "correction for attenuation" etc. are empirical.
  #   Review articles_excluded_title.csv for remaining false positives
  #   ("\\bconference\\b", "on demand" and "call for" are the most likely).
  title_exclusion_groups <- list(
    front_matter = c(
      "^issue information", "^table of contents", "^contents$", "^in this issue",
      "^masthead", "^(front|back|inside front|inside back) cover", "^cover (image|picture)",
      "^cover$", "^editorial board", "^thanks? to (our )?reviewers",
      "^reviewer acknowledg", "^acknowledg(e)?ments? to (the )?reviewers",
      "^list of reviewers", "^index$", "^author index", "^subject index",
      "\\bfront matter\\b", "^information for authors", "^instructions (for|to) authors"
    ),
    post_publication_notice = c(
      "corrigendum", "erratum", "^correction", "correction to",
      "\\bretraction\\b", "\\bretracted\\b", "\\bexpression of concern\\b"
    ),
    editorial_or_commentary = c(
      "\\beditorial\\b", "from the editor", "book review", "obituary", "in memoriam",
      "letter to the editor", "^a commentary", "^commentary on", "^commentary:",
      "presidential address", "invited lecture", "\\bkeynote\\b",
      "^an interview with", "^interview with"
    ),
    award = c(
      "^award", "award announcement", "award notice",
      "^distinguished contribution award", "gold medal",
      "award:", "award,", "\\baward$"
    ),
    advertisement = c("^advertisement", "^ads?$", "^ad:"),
    conference_or_meeting = c(
      "\\bconference\\b", "annual meeting", "symposium recap", "\\brecap\\b",
      "conference schedule", "\\bproceedings\\b", "^schedule$"
    ),
    call_or_announcement = c(
      "call for", "\\bcfp\\b", "^special issue", "special issue$", "save the date",
      "^notice", "\\bnewsletter\\b"
    ),
    training_listing = c("\\bwebinar\\b", "^\\d{4} .* course$", "on-demand", "on demand"),
    supplemental_material = c("^supplemental material", "^supplementary material"),
    guideline_or_consensus = c(
      "consensus statement", "consensus guidelines",
      "^practice guideline", "^clinical practice guideline"
    )
  )
  
  articles_df <- articles_df %>%
    mutate(
      title_squished = str_squish(title),
      exclusion_reason = case_when(
        is.na(title_squished) | title_squished == "" ~ "missing_title",
        is.na(doi_key) | doi_key == ""               ~ "missing_doi",
        duplicated(doi_key)                          ~ "duplicate_doi",
        tolower(title_squished) == tolower(str_squish(journal)) ~ "title_is_journal_name",
        TRUE ~ NA_character_
      )
    )
  
  # Title screening is applied in Step 3c2; here the matching group is only recorded.
  articles_df$title_screen_reason <- match_group(articles_df$title_squished, title_exclusion_groups)
  
  cat("Record exclusions by reason:\n")
  articles_df %>% filter(!is.na(exclusion_reason)) %>% count(exclusion_reason, sort = TRUE) %>% print()
  cat("\n")
  
  # --- 3b2. Recover missing abstracts from PubMed ----------------------------
  section("STEP 3b2: RECOVERING MISSING ABSTRACTS FROM PUBMED")
  
  # Why: OpenAlex only redistributes abstracts it is licensed to share. Most
  # abstracts of closed-access articles from APA, Elsevier and Springer Nature
  # are missing (Elsevier and Springer Nature had them removed; APA deposits
  # few in Crossref). Without this step those articles are dropped for "no
  # abstract", which removes most closed-access articles of those publishers
  # and skews the sample towards open access. PubMed holds abstracts for many
  # of these journals.
  #
  # What: articles still in play after 3b whose OpenAlex abstract is missing or
  # shorter than MIN_ABSTRACT_CHARS are looked up in PubMed by DOI (esearch on
  # the [aid] field, then efetch). A PubMed abstract is used only when the DOI
  # in the PubMed record matches the article's DOI exactly. Every lookup, found
  # or not, is stored in PUBMED_CACHE_FILE: re-runs only query new DOIs, and the
  # cache fixes the recovered abstracts for replication. Delete the cache file
  # to query everything again.
  #
  # abstract_source records where each abstract came from ("openalex" /
  # "pubmed"); abstract_openalex keeps the original OpenAlex text.
  #
  # PUBLIC VERSION: the original run's cache is not shared (PubMed abstracts
  # are publisher-copyrighted), so the first run of this copy queries PubMed
  # for all DOIs (a few minutes; needs internet) and builds its own cache.
  # The result is compared with the original run below. A different number
  # changes the articles sent to MultiTagger, and so Steps 4-8.
  ORIGINAL_RUN_PUBMED_RECOVERED <- 3183    # Study 1 run, cache built Sept 2026
  ORIGINAL_RUN_FOR_CLASSIFICATION <- 37659
  
  ncbi_request <- function(endpoint, params) {
    url <- paste0("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/", endpoint)
    params$tool  <- "pilot_tf_db_curation"
    if (nzchar(CONTACT_EMAIL)) params$email <- CONTACT_EMAIL
    if (nzchar(NCBI_API_KEY)) params$api_key <- NCBI_API_KEY
    for (attempt in seq_len(MAX_RETRIES)) {
      resp <- tryCatch(POST(url, body = params, encode = "form", timeout(120)),
                       error = function(e) NULL)
      if (!is.null(resp) && status_code(resp) == 200) {
        Sys.sleep(NCBI_DELAY)
        return(content(resp, as = "text", encoding = "UTF-8"))
      }
      Sys.sleep(NCBI_DELAY * 2^attempt)
    }
    stop("PubMed request failed after ", MAX_RETRIES, " attempts. ",
         "Re-run Step 3b2; lookups already done are kept in ", PUBMED_CACHE_FILE, ".")
  }
  
  # One row per PubMed record: its own DOI (not reference DOIs), PMID, abstract.
  # Structured abstracts keep their section labels ("Methods: ...").
  parse_pubmed_xml <- function(xml_text) {
    arts <- xml_find_all(read_xml(xml_text), "//PubmedArticle")
    if (length(arts) == 0)
      return(tibble(doi_key = character(), pmid = character(), pubmed_abstract = character()))
    tibble(
      pmid = xml_text(xml_find_first(arts, "./MedlineCitation/PMID")),
      doi_key = tolower(vapply(arts, function(a) {
        d <- xml_text(xml_find_first(a, "./PubmedData/ArticleIdList/ArticleId[@IdType='doi']"))
        if (is.na(d)) d <- xml_text(xml_find_first(a, "./MedlineCitation/Article/ELocationID[@EIdType='doi']"))
        d
      }, character(1))),
      pubmed_abstract = vapply(arts, function(a) {
        parts <- xml_find_all(a, "./MedlineCitation/Article/Abstract/AbstractText")
        if (length(parts) == 0) return(NA_character_)
        labels <- xml_attr(parts, "Label")
        txt    <- str_squish(xml_text(parts))
        str_squish(paste(ifelse(is.na(labels), txt, paste0(labels, ": ", txt)), collapse = " "))
      }, character(1))
    ) %>% filter(!is.na(doi_key))
  }
  
  articles_df <- articles_df %>%
    mutate(abstract_openalex = abstract,
           abstract_source   = if_else(!is.na(abstract) & abstract != "", "openalex", NA_character_))
  
  needs_abstract <- function(df) is.na(df$exclusion_reason) &
    (is.na(df$abstract) | nchar(coalesce(df$abstract, "")) < MIN_ABSTRACT_CHARS)
  
  if (USE_PUBMED_ABSTRACTS) {
    pubmed_targets <- unique(articles_df$doi_key[needs_abstract(articles_df)])
    
    pubmed_cache <- if (file.exists(PUBMED_CACHE_FILE)) {
      read_csv(PUBMED_CACHE_FILE, show_col_types = FALSE, col_types = cols(.default = "c"))
    } else {
      tibble(doi_key = character(), pmid = character(),
             pubmed_abstract = character(), retrieved = character())
    }
    to_query <- setdiff(pubmed_targets, pubmed_cache$doi_key)
    
    cat(sprintf("Articles with missing or short (< %d chars) abstract: %d\n",
                MIN_ABSTRACT_CHARS, length(pubmed_targets)))
    cat(sprintf("  already in cache: %d | to query now: %d\n\n",
                length(pubmed_targets) - length(to_query), length(to_query)))
    
    if (length(to_query) > 0 && !nzchar(CONTACT_EMAIL))
      cat("NOTE: CONTACT_EMAIL is empty - querying PubMed without a contact email.\n",
          "     Please set your own (see CONFIGURATION).\n\n")
    if (length(to_query) > 0) {
      doi_batches <- split(to_query, ceiling(seq_along(to_query) / PUBMED_BATCH_SIZE))
      for (b in seq_along(doi_batches)) {
        dois <- doi_batches[[b]]
        term <- paste0("\"", str_remove_all(dois, "\""), "\"[aid]", collapse = " OR ")
        es <- fromJSON(ncbi_request("esearch.fcgi",
                                    list(db = "pubmed", term = term, retmax = 1000, retmode = "json")))
        pmids <- unlist(es$esearchresult$idlist)
        
        found <- tibble(doi_key = character(), pmid = character(), pubmed_abstract = character())
        if (length(pmids) > 0) {
          found <- parse_pubmed_xml(ncbi_request("efetch.fcgi",
                                                 list(db = "pubmed", id = paste(pmids, collapse = ","),
                                                      retmode = "xml"))) %>%
            filter(doi_key %in% dois) %>%
            distinct(doi_key, .keep_all = TRUE)
        }
        pubmed_cache <- bind_rows(
          pubmed_cache,
          tibble(doi_key = dois) %>% left_join(found, by = "doi_key") %>%
            mutate(retrieved = format(Sys.Date()))
        )
        write_csv(pubmed_cache, PUBMED_CACHE_FILE)   # saved per batch: safe to interrupt
        if (b %% 10 == 0 || b == length(doi_batches))
          cat(sprintf("  batch %d / %d done\n", b, length(doi_batches)))
      }
      cat("\n")
    }
    
    recovered <- pubmed_cache %>%
      filter(doi_key %in% pubmed_targets, !is.na(pubmed_abstract),
             nchar(pubmed_abstract) >= MIN_ABSTRACT_CHARS) %>%
      distinct(doi_key, .keep_all = TRUE) %>%
      select(doi_key, pmid, pubmed_abstract)
    
    articles_df <- articles_df %>%
      left_join(recovered, by = "doi_key") %>%
      mutate(
        use_pubmed      = needs_abstract(.) & !is.na(pubmed_abstract),
        abstract        = if_else(use_pubmed, pubmed_abstract, abstract),
        abstract_source = if_else(use_pubmed, "pubmed", abstract_source)
      ) %>%
      select(-pubmed_abstract, -use_pubmed)
    
    n_in_pubmed <- sum(pubmed_targets %in% pubmed_cache$doi_key[!is.na(pubmed_cache$pmid)])
    n_recovered <- sum(articles_df$abstract_source %in% "pubmed")
    cat(sprintf("Found in PubMed:          %d of %d (%.1f%%)\n", n_in_pubmed,
                length(pubmed_targets), 100 * n_in_pubmed / max(length(pubmed_targets), 1)))
    cat(sprintf("Abstract recovered:       %d of %d (%.1f%%)\n", n_recovered,
                length(pubmed_targets), 100 * n_recovered / max(length(pubmed_targets), 1)))
    cat(sprintf("  original run recovered: %d (difference: %+d)\n\n",
                ORIGINAL_RUN_PUBMED_RECOVERED, n_recovered - ORIGINAL_RUN_PUBMED_RECOVERED))
    
    pubmed_recovery_by_journal <- articles_df %>%
      filter(doi_key %in% pubmed_targets, is.na(exclusion_reason)) %>%
      group_by(journal) %>%
      summarise(n_missing   = n(),
                n_recovered = sum(abstract_source %in% "pubmed"),
                .groups = "drop") %>%
      mutate(n_still_missing = n_missing - n_recovered,
             pct_recovered   = round(100 * n_recovered / n_missing, 1)) %>%
      arrange(desc(n_missing))
    
    cat("Recovery by journal (30 journals with the most missing abstracts):\n")
    print(head(pubmed_recovery_by_journal, 30), n = 30, width = 150)
    cat("\n")
    write_csv(pubmed_recovery_by_journal, "pubmed_recovery_by_journal.csv")
    cat("Saved: pubmed_recovery_by_journal.csv\n\n")
  } else {
    cat("PubMed lookup switched off (USE_PUBMED_ABSTRACTS = FALSE).\n\n")
  }
  
  # --- 3c. Abstract cleaning --------------------------------------------------
  section("STEP 3c: ABSTRACT CLEANING")
  
  # Formatting clean-up (conservative), plus removal of trailing
  # copyright / database-record lines (e.g. "(PsycInfo Database Record (c) 2025
  # APA, all rights reserved)"), which are not abstract content.
  clean_abstract_text <- function(x) {
    x %>%
      str_replace("^Abstract\\s*Abstract\\s*", "") %>%
      str_replace("^Abstract[:.]?\\s*", "") %>%
      str_replace_all("<[^>]+>", " ") %>%
      str_replace_all("&lt;", "<") %>%
      str_replace_all("&gt;", ">") %>%
      str_replace_all("&amp;", "&") %>%
      str_replace_all("&#[0-9]+;", " ") %>%
      str_remove(regex("\\s*\\(PsycI?NFO Database Record[^)]*\\)?\\s*\\)?\\s*$", ignore_case = TRUE)) %>%
      str_remove("\\s*(Copyright\\s*)?\u00a9\\s*(19|20)\\d{2}.{0,200}$") %>%
      str_squish()
  }
  
  # Boilerplate patterns: the abstract field holds non-abstract content.
  # Patterns are tested on both the raw and the cleaned text: on raw text
  # alone, anything wrapped in HTML (e.g. "<p>International audience</p>") or
  # prefixed with "Abstract" would slip past the "^" anchors.
  junk_abstract_pattern <- regex(
    paste(collapse = "|", c(
      "^international audience$", "^contains fulltext", "^item does not contain fulltext",
      "^no description supplied$", "abstract is not available",
      "full html content is provided on this page", "please use the get access link",
      "a preview has been provided",
      "^sponsorship:", "^this work was supported by", "^funding:", "^formulae display",
      "^the online version contains supplementary material", "^click on the pdf file",
      "^no abstract available", "^status: published", "^this is the final version",
      "^peer reviewed$", "^editorial reviewed$",
      "^clinicaltrials", "^the trial is registered", "^registered at clinicaltrials",
      "^us nih clinical trials",
      "^this study is not (pre-?)?registered", "^this study was not (pre-?)?registered",
      "^preregistered on osf",
      "^http", "^10\\.", "^/$", "^test$", "^commentary$",
      "^data de publicaci", "international congress of psychology",
      "^\u00a9", "^copyright", "this article is protected by copyright",
      "^graphical abstract", "^keywords?:", "^n/?a\\.?$", "^summary not available",
      "^abstract not available", "^\\[?no abstract", "^issue information",
      "^table of contents", "^this article has been retracted"
    )),
    ignore_case = TRUE
  )
  
  articles_df <- articles_df %>%
    mutate(
      abstract_clean = clean_abstract_text(abstract),
      junk_raw       = str_detect(coalesce(abstract, ""), junk_abstract_pattern),
      junk_clean     = str_detect(coalesce(abstract_clean, ""), junk_abstract_pattern),
      latin_share    = str_count(coalesce(abstract_clean, ""), "[A-Za-z]") /
        pmax(str_count(coalesce(abstract_clean, ""), "\\p{L}"), 1),
      abstract_key   = str_squish(str_replace_all(tolower(abstract_clean), "[^a-z0-9 ]", " "))
    ) %>%
    group_by(abstract_key) %>%
    # Duplicates are counted among articles that pass record cleaning and
    # title screening.
    mutate(n_sharing_abstract = if_else(is.na(abstract_key) | abstract_key == "", 0L,
                                        as.integer(sum(is.na(exclusion_reason) &
                                                         is.na(title_screen_reason))))) %>%
    ungroup() %>%
    mutate(
      abstract_reason = case_when(
        !is.na(exclusion_reason)                              ~ NA_character_,
        is.na(abstract) | abstract == ""                      ~ "no_abstract",
        junk_raw | junk_clean                                 ~ "boilerplate_pattern",
        nchar(abstract_clean) < MIN_ABSTRACT_CHARS            ~ "too_short",
        tolower(abstract_clean) == tolower(title_squished)    ~ "abstract_equals_title",
        latin_share < MIN_LATIN_SHARE                         ~ "non_latin_script",
        n_sharing_abstract >= DUPLICATE_ABSTRACT_MIN          ~ "duplicate_abstract",
        TRUE ~ NA_character_
      ),
      status = case_when(
        !is.na(exclusion_reason)         ~ "excluded_record",
        abstract_reason == "no_abstract" ~ "no_abstract",
        !is.na(abstract_reason)          ~ "junk_abstract",
        !is.na(title_screen_reason)      ~ "excluded_title",
        TRUE                             ~ "for_classification"
      )
    )
  
  cat("Abstract exclusions by reason:\n")
  articles_df %>% filter(!is.na(abstract_reason)) %>% count(abstract_reason, sort = TRUE) %>% print()
  cat(sprintf("\nBoilerplate caught only after cleaning (missed on raw text): %d\n",
              sum(articles_df$junk_clean & !articles_df$junk_raw & is.na(articles_df$exclusion_reason),
                  na.rm = TRUE)))
  n_dup_pairs <- sum(articles_df$n_sharing_abstract == 2 & articles_df$status == "for_classification")
  cat(sprintf("Abstracts shared by exactly 2 DOIs (kept, check manually): %d\n\n", n_dup_pairs))
  
  junk_preview <- articles_df %>% filter(status == "junk_abstract")
  for (i in seq_len(min(25, nrow(junk_preview)))) {
    cat(sprintf("[%d] %s | %s | %s\n    %s\n\n", i, junk_preview$abstract_reason[i],
                junk_preview$doi[i], junk_preview$journal[i],
                str_trunc(junk_preview$abstract[i], 120)))
  }
  if (interactive()) View(junk_preview %>% select(abstract_reason, doi, title, journal, abstract))
  
  # --- 3c2. Title screening -----------------------------------------------------
  section("STEP 3c2: TITLE SCREENING (NON-RESEARCH ENTRIES)")
  cat("Articles with a usable abstract removed by title (front matter, notices,\n")
  cat("editorials, announcements ...), by reason:\n")
  articles_df %>% filter(status == "excluded_title") %>%
    count(title_screen_reason, sort = TRUE) %>% print()
  cat(sprintf("Total removed by title screening: %d\n\n",
              sum(articles_df$status == "excluded_title")))
  
  articles_for_classification <- articles_df %>%
    filter(status == "for_classification") %>%
    mutate(abstract = abstract_clean) %>%
    arrange(doi_key) %>%                       # deterministic ID order
    mutate(article_id = row_number()) %>%
    select(article_id, doi, title, journal, source_id, abstract, abstract_source,
           year, volume, issue, pages, authors)
  
  # --- 3d. Per-journal counts and indexing checks -----------------------------
  section("STEP 3d: ARTICLES PER JOURNAL AND OPENALEX INDEXING CHECKS")
  
  journal_article_counts <- articles_df %>%
    group_by(journal, source_id) %>%
    summarise(
      n_downloaded            = n(),
      n_excluded_record       = sum(status == "excluded_record"),
      n_no_abstract           = sum(status == "no_abstract"),
      n_junk_abstract         = sum(status == "junk_abstract"),
      n_excluded_title        = sum(status == "excluded_title"),
      n_for_classification    = sum(status == "for_classification"),
      .groups = "drop"
    ) %>%
    mutate(
      n_after_record_cleaning = n_downloaded - n_excluded_record,
      pct_unusable_abstract = round(100 * (n_no_abstract + n_junk_abstract) /
                                      pmax(n_after_record_cleaning, 1), 1),
      poorly_indexed        = n_after_record_cleaning >= MIN_JOURNAL_ARTICLES &
        pct_unusable_abstract >= POORLY_INDEXED_PCT
    ) %>%
    arrange(desc(n_downloaded))
  
  cat(sprintf("Journals with >= 1 article: %d\n\n", nrow(journal_article_counts)))
  cat("Top 15 journals by articles downloaded:\n")
  journal_article_counts %>%
    select(journal, n_downloaded, n_for_classification, pct_unusable_abstract) %>%
    head(15) %>% print(n = 15, width = 150)
  
  journals_poorly_indexed <- journal_article_counts %>% filter(poorly_indexed)
  cat(sprintf("\nPoorly indexed journals (>= %d%% unusable abstracts, n >= %d): %d\n",
              POORLY_INDEXED_PCT, MIN_JOURNAL_ARTICLES, nrow(journals_poorly_indexed)))
  if (nrow(journals_poorly_indexed) > 0)
    journals_poorly_indexed %>% select(journal, n_after_record_cleaning, pct_unusable_abstract) %>%
    print(n = Inf, width = 150)
  
  # Queried ISSNs that returned no articles at all (not indexed, wrong ISSN in
  # NPI, or no output in PUBLICATION_YEAR).
  issn_found <- vapply(issns, function(x)
    any(str_detect(coalesce(articles_df$source_issns, ""), fixed(x))), logical(1))
  issns_without_articles <- journals_for_openalex %>%
    filter(`Online ISSN` %in% issns[!issn_found]) %>%
    select(`International Title`, `Online ISSN`, any_of(c("Print ISSN")))
  cat(sprintf("\nQueried ISSNs with no OpenAlex articles for %d: %d of %d\n\n",
              PUBLICATION_YEAR, nrow(issns_without_articles), length(issns)))
  
  # --- 3e. Save ----------------------------------------------------------------
  section("STEP 3e: CLEANING SUMMARY AND SAVED FILES")
  
  cat("Articles by cleaning outcome:\n")
  cleaning_summary <- articles_df %>%
    mutate(outcome = factor(status, levels = c("excluded_record", "no_abstract",
                                               "junk_abstract", "excluded_title",
                                               "for_classification"))) %>%
    count(outcome, .drop = FALSE) %>%
    mutate(pct = round(100 * n / sum(n), 1))
  print(cleaning_summary)
  cat(sprintf("  Total downloaded: %d\n", nrow(articles_df)))
  cat(sprintf("  Kept articles with abstract from OpenAlex: %d | from PubMed: %d\n\n",
              sum(articles_df$status == "for_classification" & articles_df$abstract_source %in% "openalex"),
              sum(articles_df$status == "for_classification" & articles_df$abstract_source %in% "pubmed")))
  
  cat("Detailed reasons (record, abstract and title exclusions):\n")
  articles_df %>%
    filter(status != "for_classification") %>%
    mutate(reason = case_when(status == "excluded_record" ~ exclusion_reason,
                              status == "excluded_title"  ~ title_screen_reason,
                              TRUE                        ~ abstract_reason)) %>%
    count(status, reason, sort = TRUE) %>%
    print(n = Inf)
  cat("\n")
  
  write_csv(articles_df %>% select(-title_squished, -abstract_key, -junk_raw, -junk_clean),
            "articles_master.csv")
  write_csv(articles_df %>% filter(status == "excluded_record") %>%
              select(exclusion_reason, doi, title, journal, abstract),
            "articles_excluded_record.csv")
  write_csv(articles_df %>% filter(status == "excluded_title") %>%
              select(title_screen_reason, doi, title, journal, abstract),
            "articles_excluded_title.csv")
  write_csv(articles_df %>% filter(status %in% c("no_abstract", "junk_abstract")) %>%
              select(abstract_reason, doi, title, journal, abstract),
            "articles_excluded_abstract.csv")
  write_csv(articles_for_classification, "articles_for_classification.csv")
  write_csv(journal_article_counts,      "journal_article_counts.csv")
  write_csv(journals_poorly_indexed,     "journals_poorly_indexed.csv")
  write_csv(issns_without_articles,      "issns_without_openalex_articles.csv")
  
  cat(sprintf("Articles for classification: %d of %d downloaded\n",
              nrow(articles_for_classification), nrow(articles_df)))
  cat(sprintf("  original run: %d (difference: %+d; see PUBLIC VERSION NOTE)\n\n",
              ORIGINAL_RUN_FOR_CLASSIFICATION,
              nrow(articles_for_classification) - ORIGINAL_RUN_FOR_CLASSIFICATION))
  
  # --- 3f. Exclusions by journal (OpenAlex indexing check) --------------------
  # Same information as 3d, from the other direction: share of each journal's
  # articles excluded, and why. Grouped by OpenAlex source_id (stable per
  # journal); printed by journal name. A high % no_abstract / junk_abstract
  # means the journal is poorly indexed in OpenAlex. Also lists journals with
  # ALL articles excluded.
  exclusions_by_journal <- articles_df %>%
    mutate(journal_key = coalesce(source_id, journal)) %>%
    group_by(journal_key) %>%
    summarise(
      journal         = names(sort(table(journal), decreasing = TRUE))[1],
      issn            = first(na.omit(source_issns)),
      n               = n(),
      n_record        = sum(status == "excluded_record"),
      n_title         = sum(status == "excluded_title"),
      n_no_abstract   = sum(status == "no_abstract"),
      n_junk_abstract = sum(status == "junk_abstract"),
      n_kept          = sum(status == "for_classification"),
      n_kept_pubmed   = sum(status == "for_classification" & abstract_source %in% "pubmed"),
      .groups = "drop"
    ) %>%
    mutate(
      pct_excluded    = round(100 * (n - n_kept) / n, 1),
      pct_no_abstract = round(100 * n_no_abstract / n, 1),
      pct_junk        = round(100 * n_junk_abstract / n, 1)
    ) %>%
    arrange(desc(pct_excluded), desc(n))
  
  cat("Exclusions by journal (journals with >= 10 articles, highest % excluded first):\n")
  exclusions_by_journal %>%
    filter(n >= 10) %>%
    select(journal, n, n_kept, n_kept_pubmed, pct_excluded, pct_no_abstract, pct_junk, n_record, n_title) %>%
    print(n = 30, width = 160)
  
  cat(sprintf("\nJournals with ALL articles excluded: %d\n",
              sum(exclusions_by_journal$n_kept == 0)))
  exclusions_by_journal %>%
    filter(n_kept == 0) %>%
    select(journal, issn, n, n_no_abstract, n_junk_abstract, n_record, n_title) %>%
    print(n = Inf, width = 160)
  
  write_csv(exclusions_by_journal, "exclusions_by_journal.csv")
}


################################################################################
# STEP 4: MULTITAGGER CLASSIFICATION
#
#   4a. (removed - MultiTagger is run outside this script)
#   4b. Check for multitagger_predictions.csv (stop with instructions if missing)
#   4c. Read multitagger_predictions.csv. It holds the article details
#       (article_id, doi, title, journal, abstract, abstract_source, ...) and
#       the MultiTagger labels, so it is the only input for Steps 4-7.
#   4d. MultiTagger descriptives: no-opinion rate, label firing rates with
#       example titles, label groups (from pilot2_db_multitagger-comparison._v2-public.R,
#       without the comparison against the LLM article classifications)
#   4e. Decision rule:
#       4e-1 POST-MANUAL-REVIEW DECISION: labels in
#            MANUAL_LABELS_TO_NON_EMPIRICAL moved to Group 3 (non-empirical)
#       4e-2 sensitivity across rules, then apply MT_DECISION_RULE
#
# Console output of 4c-4e is also written to multitagger_report.txt.
################################################################################

while (sink.number() > 0) sink()   # close any log left open by an earlier stop

section("STEP 4b: CHECKING FOR MULTITAGGER PREDICTIONS")

if (!file.exists(MT_PREDICTIONS_FILE)) {
  cat(">>> MANUAL STEP: run MultiTagger on articles_for_classification.csv\n")
  cat("    Save the output as", MT_PREDICTIONS_FILE, "in:\n   ", output_directory, "\n")
  cat("    Expected: the article columns plus one 0/1 column per label\n")
  cat("    (optionally prob_<label> columns).\n")
  cat("    See the MultiTagger README (run_multitagger_study1db.py).\n\n")
  stop("Stopping. Re-run after saving MultiTagger predictions.")
}
cat(sprintf("Using %s (saved %s).\n\n", MT_PREDICTIONS_FILE,
            format(file.mtime(MT_PREDICTIONS_FILE), "%Y-%m-%d %H:%M")))

sink("multitagger_report.txt", split = TRUE)
cat(sprintf("MULTITAGGER REPORT - %s - generated %s\n\n", RUN_LABEL,
            format(Sys.time(), "%Y-%m-%d %H:%M")))

section("STEP 4c: READING MULTITAGGER PREDICTIONS")

# MultiTagger's 59 labels and our four label groups for psychology. This table
# is IDENTICAL to the one in pilot2_db_multitagger-comparison._v2-public.R (Section 2),
# which explains the groups and gives the references; keep the two in step.
#   paper_group  grouping in the MultiTagger V1 paper (Cohen et al., 2021):
#                "Clinical" = Table 1, clinically related study designs;
#                "Other" = Table 2, other publication types
#   our_group    Empirical (30)  study designs and study types
#                Group 1   (8)   strong empirical candidates for psychology
#                Group 2   (6)   grey zone
#                Group 3   (15)  non-empirical
# Step 4e-1 moves some labels to Group 3 after manual review; the table
# itself always shows the ORIGINAL groups.
EMP <- "Empirical"
G1  <- "Group 1: strong empirical candidate"
G2  <- "Group 2: grey zone"
G3  <- "Group 3: non-empirical"

label_info <- tribble(
  ~label,                                  ~paper_group,   ~our_group, ~definition,
  "autobiography",                         "Other",        G3,  "A person's account of their own life",
  "bibliography",                          "Other",        G3,  "A list of references on a topic",
  "biography",                             "Other",        G2,  "An account of another person's life",
  "case_control_study",                    "Clinical",     EMP, "Compares people with an outcome (cases) to people without (controls)",
  "case_reports",                          "Clinical",     EMP, "Detailed report of an individual case or small series",
  "clinical_conference",                   "Other",        G1,  "Proceedings or summaries of clinical conferences",
  "clinical_studies_as_topic",             "Other",        G1,  "Articles about clinical studies as a subject",
  "clinical_study",                        "Clinical",     EMP, "Parent tag for all clinical studies",
  "clinical_trial",                        "Clinical",     EMP, "Participants prospectively assigned to interventions",
  "clinical_trial_protocol",               "Not in paper", EMP, "Protocol for a clinical trial",
  "cohort_study",                          "Clinical",     EMP, "Follows a defined group over time, comparing exposures",
  "comment",                               "Other",        G2,  "Short commentary on another published article",
  "congress",                              "Other",        G1,  "Published as congress proceedings",
  "consensus_development_conference",      "Other",        G1,  "Proceedings of consensus-building conferences",
  "cross_cultural_comparison",             "Clinical",     EMP, "Compares a variable across cultural or national groups",
  "cross_over_study",                      "Clinical",     EMP, "Participants receive several treatments in sequence",
  "cross_sectional_study",                 "Clinical",     EMP, "Measures a population at a single point in time",
  "double_blind_method",                   "Clinical",     EMP, "Participants and investigators masked to allocation",
  "editorial",                             "Other",        G3,  "Opinion piece by an editor or invited author",
  "evaluation_studies",                    "Clinical",     EMP, "Assesses the effectiveness of programmes or methods",
  "evaluation_studies_as_topic",           "Other",        G1,  "Evaluation methodology as a topic",
  "expression_of_concern",                 "Other",        G3,  "Editor's notice of concern about a published article",
  "feasibility_studies",                   "Clinical",     EMP, "Assesses whether a larger study is practicable",
  "focus_groups",                          "Clinical",     EMP, "Group discussion as the main data-collection method",
  "follow_up_studies",                     "Clinical",     EMP, "Re-examines participants after an earlier assessment",
  "genome_wide_association_study",         "Clinical",     EMP, "Scans the genome for variants linked to a trait",
  "historical_article",                    "Other",        G2,  "History of medicine or science",
  "human_experimentation",                 "Clinical",     EMP, "Deliberate experimental procedures on humans",
  "interview",                             "Other",        G1,  "A published interview",
  "interviews_as_topic",                   "Other",        G1,  "Interviews as a method or topic of study",
  "lectures",                              "Other",        G3,  "Published as, or derived from, a lecture",
  "legal_cases",                           "Other",        G3,  "Reports of legal cases or court decisions",
  "letter",                                "Other",        G3,  "Letter to the editor",
  "longitudinal_studies",                  "Clinical",     EMP, "Follows individuals over an extended period",
  "matched_pair_analysis",                 "Clinical",     EMP, "Cases and controls individually matched",
  "meta_analysis",                         "Clinical",     G1,  "Statistical synthesis of results from many studies",
  "multicenter_study",                     "Clinical",     EMP, "Conducted across several sites",
  "news",                                  "Other",        G3,  "News items",
  "newspaper_article",                     "Other",        G3,  "Published in a newspaper",
  "personal_narratives",                   "Other",        G2,  "First-person account of personal experience",
  "portaits",                              "Other",        G3,  "Portraits / profiles of individuals (sic: label is spelled 'portaits')",
  "practice_guideline",                    "Clinical",     G3,  "Formally issued practice guideline",
  "predictive_value_of_tests",             "Other",        EMP, "Diagnostic accuracy or predictive value of tests",
  "prospective_studies",                   "Clinical",     EMP, "Data collected forward from enrolment",
  "published_erratum",                     "Other",        G3,  "Correction to a published article",
  "random_allocation",                     "Clinical",     EMP, "Random assignment of participants to conditions",
  "randomized_controlled_trial",           "Clinical",     EMP, "Random allocation to intervention and control arms",
  "reproducibility_of_results",            "Other",        EMP, "Replicability, reliability or validity of results",
  "retraction_of_publication",             "Other",        G3,  "Formal retraction of a publication",
  "retrospective_studies",                 "Clinical",     EMP, "Analyses data collected before the study began",
  "review",                                "Clinical",     G2,  "Review article of any type",
  "scientific_integrity_review",           "Other",        G3,  "Review of scientific integrity issues",
  "systematic_review",                     "Clinical",     G2,  "Systematic search and synthesis of evidence",
  "systematic_review_as_topic",            "Other",        G3,  "Systematic reviews as a method or topic",
  "twin_study",                            "Clinical",     EMP, "Uses twin pairs to separate genetic and environmental effects",
  "validation_studies",                    "Clinical",     EMP, "Establishes the validity of a measure or procedure",
  "veterinary_clinical_trial",             "Not in paper", EMP, "Veterinary clinical trial",
  "veterinary_observational_study",        "Not in paper", EMP, "Veterinary observational study",
  "veterinary_randomized_controlled_trial","Not in paper", EMP, "Veterinary randomised controlled trial"
)

# Label lists used below. Step 4e-1 updates these (not label_info).
label_order <- label_info$label
strong_candidates_to_keep_empirical_for_psyc <- label_info$label[label_info$our_group == G1]
grey_zone_labels     <- label_info$label[label_info$our_group == G2]
non_empirical_labels <- label_info$label[label_info$our_group == G3]
empirical_labels     <- label_info$label[label_info$our_group == EMP]
stopifnot(length(label_order) == 59, !anyDuplicated(label_order),
          lengths(list(empirical_labels, strong_candidates_to_keep_empirical_for_psyc,
                       grey_zone_labels, non_empirical_labels)) == c(30, 8, 6, 15))

# Group of each label, read from the CURRENT lists (so after Step 4e-1 it
# reflects the manual review decision).
label_group <- function(l) case_when(
  l %in% strong_candidates_to_keep_empirical_for_psyc ~ "Group 1: strong empirical candidate",
  l %in% grey_zone_labels                             ~ "Group 2: grey zone",
  l %in% non_empirical_labels                         ~ "Group 3: non-empirical",
  TRUE                                                ~ "Empirical"
)

mt_raw <- read_chr_csv(MT_PREDICTIONS_FILE)

required_mt_cols <- c("article_id", "doi", "title", "journal", "abstract", label_order)
missing_mt_cols  <- setdiff(required_mt_cols, names(mt_raw))
if (length(missing_mt_cols) > 0)
  stop(MT_PREDICTIONS_FILE, " is missing column(s): ",
       paste(head(missing_mt_cols, 10), collapse = ", "))

# Labels: already thresholded by MultiTagger (per-label cut-offs), used as is.
classified_articles <- mt_raw %>%
  mutate(across(all_of(label_order), as.integer),
         article_id = as.integer(article_id))
if (anyNA(classified_articles[, label_order]) ||
    !all(unlist(classified_articles[, label_order]) %in% c(0, 1)))
  stop("Label columns must contain only 0 and 1.")

# Probabilities (optional): keep only the most likely label and its
# probability - the useful part for articles where no label fired.
prob_cols <- paste0("prob_", label_order)
if (all(prob_cols %in% names(mt_raw))) {
  mt_probs <- as.matrix(mt_raw %>% select(all_of(prob_cols)) %>%
                          mutate(across(everything(), as.numeric)))
  top_i <- max.col(mt_probs, ties.method = "first")
  classified_articles$mt_top_label <- label_order[top_i]
  classified_articles$mt_top_prob  <- mt_probs[cbind(seq_len(nrow(mt_probs)), top_i)]
} else {
  mt_probs <- NULL
}
classified_articles <- classified_articles %>%
  select(-any_of(c(prob_cols, "predicted_types"))) %>%
  mutate(mt_has_prediction = TRUE)

n_dup_doi <- sum(duplicated(tolower(classified_articles$doi)))
if (n_dup_doi > 0) {
  cat(sprintf("NOTE: %d duplicated DOI(s) - first row kept.\n", n_dup_doi))
  classified_articles <- classified_articles %>% filter(!duplicated(tolower(doi)))
}
if (!"abstract_source" %in% names(classified_articles))
  classified_articles$abstract_source <- NA_character_

cat(sprintf("Articles: %d | label columns: %d | probabilities: %s\n\n",
            nrow(classified_articles), length(label_order),
            if (is.null(mt_probs)) "no" else "yes"))
# If the predictions file has an empty abstract column (e.g. a copy shared
# without abstracts), classification and sampling are unaffected; abstracts
# are only carried into articles_empirical_sample.csv.
abstracts_removed <- all(is.na(classified_articles$abstract) |
                           str_trim(classified_articles$abstract) == "")
if (abstracts_removed)
  cat("NOTE: abstract column is empty (public version) - classification and\n",
      "     sample are unaffected; the sample file will have no abstracts.\n\n")

pred_rows     <- classified_articles
pred_all_zero <- rowSums(pred_rows[, label_order]) == 0

section("STEP 4d: MULTITAGGER DESCRIPTIVES")
set.seed(RANDOM_SEED)   # example titles are drawn at random; fixed for the log

cat("Data check:\n")
cat(sprintf("  Articles with predictions:   %d\n", nrow(pred_rows)))
cat(sprintf("  Label columns:               %d\n", length(label_order)))
cat(sprintf("  Labels fired in total:       %d (mean %.2f per article)\n\n",
            sum(pred_rows[, label_order]), mean(rowSums(pred_rows[, label_order]))))

cat("MT no-opinion rate (no label fired):\n")
cat(sprintf("  %d of %d (%.1f%%)\n\n", sum(pred_all_zero), nrow(pred_rows),
            100 * mean(pred_all_zero)))

cat("No-opinion rate by abstract source:\n")
pred_rows %>% mutate(no_opinion = pred_all_zero) %>%
  group_by(abstract_source) %>%
  summarise(n = n(), n_no_opinion = sum(no_opinion),
            pct_no_opinion = round(100 * mean(no_opinion), 1), .groups = "drop") %>% print()
cat("\n")

cat("Sample titles - MT had no opinion:\n")
no_op_examples <- pred_rows[pred_all_zero, ] %>% slice_sample(n = min(10, sum(pred_all_zero)))
for (i in seq_len(nrow(no_op_examples)))
  cat(sprintf("  %2d. %s  [%s]\n", i, str_trunc(no_op_examples$title[i], 110),
              no_op_examples$journal[i]))
cat("\n")

if (!is.null(mt_probs)) {
  cat("No-opinion articles: label MT came closest to assigning (highest probability):\n")
  pred_rows[pred_all_zero, ] %>%
    mutate(group = label_group(mt_top_label)) %>%
    group_by(mt_top_label, group) %>%
    summarise(n = n(), median_prob = round(median(mt_top_prob), 3), .groups = "drop") %>%
    arrange(desc(n)) %>% head(15) %>% print(n = 15, width = 150)
  cat("\n")
}

# Firing rates for all 59 labels, with 2 example titles each
firing_rates <- tibble(label = label_order,
                       count = colSums(pred_rows[, label_order])) %>%
  mutate(pct   = round(100 * count / nrow(pred_rows), 2),
         group = label_group(label)) %>%
  arrange(desc(count))
firing_examples <- lapply(firing_rates$label, function(l) {
  t <- pred_rows$title[pred_rows[[l]] == 1 & !is.na(pred_rows$title)]
  if (length(t) == 0) character(0) else sample(t, min(2, length(t)))
})
firing_rates$example_1 <- vapply(firing_examples, function(x) if (length(x) >= 1) x[1] else NA_character_, "")
firing_rates$example_2 <- vapply(firing_examples, function(x) if (length(x) >= 2) x[2] else NA_character_, "")

cat("Firing rates and example titles: all 59 labels (sorted by frequency)\n\n")
for (i in seq_len(nrow(firing_rates))) {
  cat(sprintf("[%s]  n = %d (%.2f%%)  |  %s\n", firing_rates$label[i], firing_rates$count[i],
              firing_rates$pct[i], firing_rates$group[i]))
  if (firing_rates$count[i] == 0) {
    cat("  (no articles fired this label)\n")
  } else {
    for (x in na.omit(c(firing_rates$example_1[i], firing_rates$example_2[i])))
      cat(sprintf("  - %s\n", str_trunc(x, 120)))
  }
}
cat("\n")

cat("Firing rates by label group:\n")
for (g in c("Empirical", "Group 1: strong empirical candidate",
            "Group 2: grey zone", "Group 3: non-empirical")) {
  cat(sprintf("\n%s:\n", g))
  firing_rates %>% filter(group == g) %>% select(label, count, pct) %>% print(n = Inf)
}
cat("\n")

cat("Articles with at least one label in each group (groups overlap):\n")
fired_any <- function(labels) sum(rowSums(pred_rows[, labels, drop = FALSE]) > 0)
tibble(
  group = c("Empirical", "Group 1: strong empirical candidate", "Group 2: grey zone",
            "Group 3: non-empirical", "No opinion"),
  n = c(fired_any(empirical_labels), fired_any(strong_candidates_to_keep_empirical_for_psyc),
        fired_any(grey_zone_labels), fired_any(non_empirical_labels), sum(pred_all_zero))
) %>% mutate(pct = round(100 * n / nrow(pred_rows), 1)) %>% print()
cat("\n")

write_csv(firing_rates, "mt_label_firing_rates.csv")
cat("Saved: mt_label_firing_rates.csv\n\n")

section("STEP 4e: DECISION RULE")

# --- 4e-1. POST-MANUAL-REVIEW DECISION: move labels to non-empirical ------------
cat("4e-1. POST-MANUAL-REVIEW DECISION - LABELS MOVED TO NON-EMPIRICAL\n")
cat("--------------------------------------------------------------------\n")

# !!! MANUAL REVIEW DECISION - not part of the original MultiTagger grouping !!!
# Made after reviewing the Step 4d firing rates and example titles. Labels in
# MANUAL_LABELS_TO_NON_EMPIRICAL (set in CONFIGURATION, with the reason for
# each) are taken out of their original group and treated as Group 3
# (non-empirical). Step 4d (firing rates, group tables) shows the ORIGINAL
# groups; everything from here on (rule sensitivity, classification,
# the sample) uses the ADJUSTED groups.
cat("*** MANUAL REVIEW DECISION - labels moved to Group 3 (non-empirical) ***\n")
cat("    (not part of the original MultiTagger grouping; see CONFIGURATION)\n\n")
manual_label_decisions <- tibble(label = character(), from_group = character(),
                                 to_group = character(), reason = character(),
                                 n_articles = integer())
for (l in names(MANUAL_LABELS_TO_NON_EMPIRICAL)) {
  if (!l %in% label_order) stop("Unknown label in MANUAL_LABELS_TO_NON_EMPIRICAL: ", l)
  from_group <- label_group(l)
  strong_candidates_to_keep_empirical_for_psyc <- setdiff(strong_candidates_to_keep_empirical_for_psyc, l)
  grey_zone_labels     <- setdiff(grey_zone_labels, l)
  empirical_labels     <- setdiff(empirical_labels, l)
  non_empirical_labels <- union(non_empirical_labels, l)
  hits <- pred_rows %>% filter(.data[[l]] == 1)
  cat(sprintf("Moved %s: %s -> Group 3: non-empirical\n", l, from_group))
  cat(sprintf("  Reason: %s\n", MANUAL_LABELS_TO_NON_EMPIRICAL[[l]]))
  cat(sprintf("  Articles with this label: %d (these now count as non-empirical)\n", nrow(hits)))
  for (i in seq_len(min(10, nrow(hits)))) {
    fired <- label_order[unlist(hits[i, label_order]) == 1]
    cat(sprintf("  - %s\n    labels: %s\n", str_trunc(hits$title[i], 100),
                paste(fired, collapse = "; ")))
  }
  cat("\n")
  manual_label_decisions <- bind_rows(manual_label_decisions, tibble(
    label = l, from_group = from_group, to_group = "Group 3: non-empirical",
    reason = MANUAL_LABELS_TO_NON_EMPIRICAL[[l]], n_articles = nrow(hits)))
}
write_csv(manual_label_decisions, "mt_manual_label_decisions.csv")
cat("Saved: mt_manual_label_decisions.csv (record of this manual decision)\n\n")
firing_rates$group_after_manual_review <- label_group(firing_rates$label)
write_csv(firing_rates, "mt_label_firing_rates.csv")   # adds the adjusted group
cat(sprintf("Group sizes now: Empirical %d | Group 1 %d | Group 2 %d | Group 3 %d labels\n\n",
            length(empirical_labels), length(strong_candidates_to_keep_empirical_for_psyc),
            length(grey_zone_labels), length(non_empirical_labels)))

cat("4e-2. DECISION RULES\n")
cat("--------------------\n")
mt_classify <- function(pred, rule) {
  fired    <- function(labels) rowSums(pred[, labels, drop = FALSE]) > 0
  all_zero <- rowSums(pred[, label_order, drop = FALSE]) == 0
  empirical <- switch(
    rule,
    A = !fired(c(grey_zone_labels, non_empirical_labels)),
    B = !fired(c(strong_candidates_to_keep_empirical_for_psyc, non_empirical_labels)),
    C = !fired(non_empirical_labels),
    strict = fired(c(empirical_labels, strong_candidates_to_keep_empirical_for_psyc)) &
      !fired(non_empirical_labels) &
      !((pred$review == 1 | pred$systematic_review == 1) & pred$meta_analysis == 0),
    stop("Unknown MT_DECISION_RULE: ", rule)
  )
  ifelse(all_zero, NA, empirical)
}

# Sensitivity: how many articles each rule would call empirical.
mt_rule_sensitivity <- bind_rows(lapply(c("A", "B", "C", "strict"), function(r) {
  x <- mt_classify(pred_rows, r)
  tibble(rule = r, empirical = sum(x %in% TRUE), non_empirical = sum(x %in% FALSE),
         no_opinion = sum(is.na(x)), selected = r == MT_DECISION_RULE)
}))
cat("Empirical / non-empirical counts under each rule:\n")
cat("  A      Empirical + Group 1 = empirical; Groups 2+3 = non-empirical\n")
cat("  B      Empirical + Group 2 = empirical; Groups 1+3 = non-empirical\n")
cat("  C      Group 3 only = non-empirical\n")
cat("  strict Empirical/Group 1 label, no Group 3 label, no review without meta-analysis\n\n")
print(mt_rule_sensitivity)
cat("\n")
write_csv(mt_rule_sensitivity, "mt_rule_sensitivity.csv")

classified_articles$mt_empirical <- NA
classified_articles$mt_empirical[classified_articles$mt_has_prediction] <-
  mt_classify(pred_rows, MT_DECISION_RULE)

label_matrix <- as.matrix(classified_articles[, label_order])
label_matrix[is.na(label_matrix)] <- 0
classified_articles <- classified_articles %>%
  mutate(
    mt_all_zero = mt_has_prediction & rowSums(label_matrix) == 0,
    mt_labels   = apply(label_matrix, 1, function(r) {
      l <- label_order[r == 1]
      if (length(l) == 0) "(no labels fired)" else paste(l, collapse = "; ")
    }),
    mt_groups   = apply(label_matrix, 1, function(r) {
      l <- label_order[r == 1]
      if (length(l) == 0) "No opinion" else paste(unique(label_group(l)), collapse = "; ")
    }),
    mt_status   = case_when(
      is.na(mt_empirical) ~ "no_opinion",
      mt_empirical        ~ "empirical",
      TRUE                ~ "non_empirical"
    )
  )

cat(sprintf("Rule %s applied:\n", MT_DECISION_RULE))
print(count(classified_articles, mt_status) %>% mutate(pct = round(100 * n / sum(n), 1)))
cat("\n")

write_csv(classified_articles, "articles_classified_all.csv")
cat(sprintf("Saved: articles_classified_all.csv (%d articles + MT labels + mt_status)\n\n",
            nrow(classified_articles)))

sink()   # end of multitagger_report.txt
cat("Saved: multitagger_report.txt (console output of Steps 4c-4e)\n\n")


################################################################################
# STEP 6: SAMPLE EMPIRICAL ARTICLES
################################################################################

section("STEP 6: SAMPLING EMPIRICAL ARTICLES")

# Only articles MultiTagger called empirical under MT_DECISION_RULE (set in
# CONFIGURATION; for Study 1, rule A: at least one label assigned, none from
# Group 2 or Group 3 after the Step 4e-1 manual review decision).
# MT no-opinion articles are excluded.
empirical_articles <- classified_articles %>%
  filter(mt_status == "empirical") %>%
  distinct(doi, .keep_all = TRUE) %>%
  arrange(article_id)

cat(sprintf("Empirical articles available (rule %s): %d\n", MT_DECISION_RULE,
            nrow(empirical_articles)))
if (nrow(empirical_articles) < SAMPLE_SIZE)
  cat(sprintf("WARNING: fewer than %d available; sampling all.\n", SAMPLE_SIZE))

# Under rules A and C, the empirical articles include some whose only labels
# are Group 1 (strong empirical candidates for psychology). Breakdown, so
# this is visible in the log:
has_emp_label <- rowSums(empirical_articles[, empirical_labels]) > 0
has_g1_label  <- rowSums(empirical_articles[, strong_candidates_to_keep_empirical_for_psyc]) > 0
cat("Why these articles count as empirical:\n")
cat(sprintf("  empirical-design labels only:        %6d\n", sum(has_emp_label & !has_g1_label)))
cat(sprintf("  Group 1 labels only (added by rule %s): %6d\n", MT_DECISION_RULE,
            sum(!has_emp_label & has_g1_label)))
cat(sprintf("  both:                                %6d\n", sum(has_emp_label & has_g1_label)))

# --- 6a. Journals in the empirical pool (before sampling) --------------------
cat("\n6a. JOURNALS REPRESENTED AMONG EMPIRICAL ARTICLES\n")
cat("--------------------------------------------------\n")
pool_by_journal <- empirical_articles %>% count(journal, name = "n_empirical") %>%
  arrange(desc(n_empirical))
cat(sprintf("Journals with >= 1 empirical article: %d\n", nrow(pool_by_journal)))
cat("Empirical articles per journal:\n")
print(summary(pool_by_journal$n_empirical))
cat(sprintf("Journals with < 5 / < 10 / < 20 empirical articles: %d / %d / %d\n",
            sum(pool_by_journal$n_empirical < 5), sum(pool_by_journal$n_empirical < 10),
            sum(pool_by_journal$n_empirical < 20)))
cat(sprintf("The 10 largest journals hold %.1f%% of all empirical articles:\n",
            100 * sum(head(pool_by_journal$n_empirical, 10)) / nrow(empirical_articles)))
print(head(pool_by_journal, 10))

# --- 6b. What each sampling method would give per journal -------------------
cat("\n6b. ARTICLES PER JOURNAL UNDER EACH SAMPLING METHOD\n")
cat("---------------------------------------------------\n")
n_target <- min(SAMPLE_SIZE, nrow(empirical_articles))
n_pool   <- pool_by_journal$n_empirical

# Allocate `total` articles across journals in proportion to `weights`,
# never more than a journal has, optionally at least `min_n` per journal.
# Articles a journal cannot supply are passed on to the others; fractions
# are rounded by largest remainder so the total is exact. Deterministic.
allocate_sample <- function(n_pool, total, weights, min_n = 0) {
  a <- pmin(n_pool, min_n)
  for (iter in 1:200) {
    remaining <- total - sum(a)
    open <- a < n_pool
    if (remaining < 1e-9 || !any(open)) break
    w <- weights * open
    a <- pmin(n_pool, a + remaining * w / sum(w))
  }
  base  <- floor(a)
  extra <- round(total - sum(base))
  for (i in order(-(a - base))) {
    if (extra <= 0) break
    if (base[i] < n_pool[i]) { base[i] <- base[i] + 1; extra <- extra - 1 }
  }
  as.integer(base)
}

# simple: expected articles per journal (actual numbers vary by chance)
quota_simple <- n_target * n_pool / sum(n_pool)
# sqrt: fixed quota per journal
quota_sqrt <- allocate_sample(n_pool, n_target, sqrt(n_pool), SQRT_MIN_PER_JOURNAL)
# balanced: smallest equal cap that reaches the target
journal_cap <- 1
while (sum(pmin(n_pool, journal_cap)) < n_target) journal_cap <- journal_cap + 1
quota_balanced <- pmin(n_pool, journal_cap)

method_summary <- function(name, q) {
  tibble(method = name,
         total = round(sum(q)),
         max_per_journal = round(max(q)),
         median_per_journal = round(median(q), 1),
         top10_share_pct = round(100 * sum(sort(q, decreasing = TRUE)[1:10]) / sum(q), 1),
         journals_below_1 = sum(q < 1))
}
cat("Comparison (simple = expected values):\n")
print(bind_rows(method_summary("simple", quota_simple),
                method_summary("sqrt", quota_sqrt),
                method_summary(sprintf("balanced (cap %d)", journal_cap), quota_balanced)),
      width = 160)

cat("\nsqrt allocation by journal size:\n")
tibble(n_pool, quota_sqrt) %>%
  mutate(size_band = cut(n_pool, c(0, 9, 29, 99, 299, Inf),
                         labels = c("1-9", "10-29", "30-99", "100-299", "300+"))) %>%
  group_by(size_band) %>%
  summarise(journals = n(),
            sampled_per_journal = paste0(min(quota_sqrt), "-", max(quota_sqrt)),
            share_of_sample_pct = round(100 * sum(quota_sqrt) / n_target, 1),
            share_of_pool_pct   = round(100 * sum(n_pool) / sum(pool_by_journal$n_empirical), 1),
            .groups = "drop") %>% print()

sampling_plan <- pool_by_journal %>%
  mutate(simple_expected = round(quota_simple, 1),
         sqrt            = quota_sqrt,
         balanced        = quota_balanced)
write_csv(sampling_plan, "sampling_plan_by_journal.csv")
cat("\nSaved: sampling_plan_by_journal.csv (per journal, all three methods)\n\n")

# --- 6c. Draw the sample -------------------------------------------------------
cat(sprintf("6c. DRAWING THE SAMPLE (SAMPLING_METHOD = \"%s\")\n", SAMPLING_METHOD))
cat("----------------------------------------------\n")
set.seed(RANDOM_SEED)
draw_by_quota <- function(quota) {
  quota <- setNames(quota, pool_by_journal$journal)
  empirical_articles %>%
    group_by(journal) %>%
    group_modify(~ slice_sample(.x, n = quota[[.y$journal]])) %>%
    ungroup()
}
if (SAMPLING_METHOD == "simple") {
  sampled <- empirical_articles %>% slice_sample(n = n_target)
} else if (SAMPLING_METHOD == "sqrt") {
  sampled <- draw_by_quota(quota_sqrt)
} else if (SAMPLING_METHOD == "balanced") {
  # The cap overshoots by fewer articles than there are capped journals; the
  # surplus is removed by taking one fewer from randomly chosen capped journals.
  quota <- setNames(quota_balanced, pool_by_journal$journal)
  surplus <- sum(quota) - n_target
  if (surplus > 0) {
    capped <- names(quota)[quota == journal_cap]
    drop_from <- sample(capped, surplus)
    quota[drop_from] <- quota[drop_from] - 1
  }
  sampled <- draw_by_quota(unname(quota))
} else {
  stop("SAMPLING_METHOD must be \"sqrt\", \"simple\" or \"balanced\".")
}

# Sampling weight: journal's empirical articles / articles sampled from it.
# Weighted analyses reproduce the journal mix of the full empirical pool.
sampled <- sampled %>%
  left_join(pool_by_journal, by = "journal") %>%
  add_count(journal, name = "n_sampled_journal") %>%
  mutate(sampling_weight = n_empirical / n_sampled_journal)

empirical_sample <- sampled %>%
  select(article_id, doi, title, journal, abstract, year, volume, issue, pages,
         authors, mt_labels, n_journal_empirical = n_empirical,
         n_journal_sampled = n_sampled_journal, sampling_weight) %>%
  mutate(
    title   = str_squish(str_remove_all(title, "<[^>]+>")),
    # Remove control / invisible characters only; letters in any script are kept
    authors = str_squish(str_remove_all(authors, "\\p{C}"))
  )

cat(sprintf("Sampled: %d articles from %d journals (seed = %d)\n", nrow(empirical_sample),
            n_distinct(empirical_sample$journal), RANDOM_SEED))
cat("Articles per journal in the sample:\n")
print(summary(as.integer(table(empirical_sample$journal))))
cat("\n")
write_csv(empirical_sample, "articles_empirical_sample.csv")

journal_sample_summary <- journal_article_counts %>%
  group_by(journal_title = journal) %>%
  summarise(n_downloaded = sum(n_downloaded), .groups = "drop") %>%
  left_join(empirical_sample %>% count(journal, name = "n_articles"),
            by = c("journal_title" = "journal")) %>%
  mutate(
    n_articles    = coalesce(n_articles, 0L),
    in_sample     = if_else(n_articles > 0, "Yes", "No"),
    pct_of_sample = round(100 * n_articles / nrow(empirical_sample), 2)
  ) %>%
  arrange(desc(n_articles), journal_title)
write_csv(journal_sample_summary, "journal_sample_summary.csv")

cat(sprintf("Journals with >= 1 sampled article: %d of %d\n\n",
            sum(journal_sample_summary$in_sample == "Yes"), nrow(journal_sample_summary)))


################################################################################
# STEP 7: EXPORT EMPIRICAL SAMPLE TO RIS FOR ZOTERO
################################################################################

section("STEP 7: WRITING RIS FILES")

create_ris <- function(row) {
  ris <- "TY  - JOUR\n"
  if (!is.na(row$authors) && row$authors != "") ris <- paste0(ris, "AU  - ", row$authors, "\n")
  if (!is.na(row$title)) {
    title_clean <- gsub("&quot;|<scp>|</scp>|\"", "", row$title)
    ris <- paste0(ris, "TI  - ", title_clean, "\n")
  }
  if (!is.na(row$journal)) ris <- paste0(ris, "JO  - ", row$journal, "\nT2  - ", row$journal, "\n")
  if (!is.na(row$year))                           ris <- paste0(ris, "PY  - ", row$year,   "\n")
  if (!is.na(row$volume) && row$volume != "")     ris <- paste0(ris, "VL  - ", row$volume, "\n")
  if (!is.na(row$issue)  && row$issue  != "")     ris <- paste0(ris, "IS  - ", row$issue,  "\n")
  if (!is.na(row$pages)  && row$pages  != "")     ris <- paste0(ris, "SP  - ", row$pages,  "\n")
  if (!is.na(row$doi)) {
    ris <- paste0(ris, "DO  - ", str_remove(row$doi, "^https://doi.org/"), "\n")
    ris <- paste0(ris, "UR  - ", row$doi, "\n")
  }
  paste0(ris, "DB  - OpenAlex\nER  - \n\n")
}

n_ris_batches <- ceiling(nrow(empirical_sample) / RIS_BATCH_SIZE)
for (rb in seq_len(n_ris_batches)) {
  row_start <- (rb - 1) * RIS_BATCH_SIZE + 1
  row_end   <- min(rb * RIS_BATCH_SIZE, nrow(empirical_sample))
  batch_df  <- empirical_sample[row_start:row_end, ]
  ris_file  <- sprintf("psychology_%d_empirical_for_zotero_part_%02d.ris", PUBLICATION_YEAR, rb)
  con <- file(ris_file, open = "w", encoding = "UTF-8")
  for (i in seq_len(nrow(batch_df))) cat(create_ris(batch_df[i, ]), file = con)
  close(con)
  cat(sprintf("  Saved: %s (%d records)\n", ris_file, nrow(batch_df)))
}
cat("\n")


################################################################################
# STEP 8: SUMMARY REPORT
################################################################################

section("STEP 8a: EXCLUSION TABLES (JOURNALS AND ARTICLES)")

# Two tables for the write-up, rebuilt from the objects of this run (works
# the same whether Steps 0-3 were run or loaded from saved files):
#   exclusion_table_journals.csv  - journals: NPI register -> sampled
#   exclusion_table_articles.csv  - articles: OpenAlex download -> sampled
#   exclusion_reasons_detail.csv  - article exclusions by detailed reason
#   journal_funnel_to_sample.csv  - every journal sent to OpenAlex, with its
#                                   counts at each stage and why it is not
#                                   in the sampling pool (if it is not)

classified_keys <- norm_doi(classified_articles$doi)
empirical_keys  <- norm_doi(classified_articles$doi[classified_articles$mt_status == "empirical"])

# --- Journal funnel: each NPI journal sent to OpenAlex, matched to the
# downloaded articles through its Online ISSN (and Print ISSN, if present)
print_issn_col <- if ("Print ISSN" %in% names(journals_for_openalex))
  journals_for_openalex$`Print ISSN` else rep(NA_character_, nrow(journals_for_openalex))
npi_keys <- journals_for_openalex %>%
  transmute(npi_title = `International Title`, online_issn = `Online ISSN`,
            k_online = norm_issn(`Online ISSN`), k_print = norm_issn(print_issn_col)) %>%
  pivot_longer(c(k_online, k_print), values_to = "issn_key") %>%
  filter(issn_key != "") %>%
  distinct(npi_title, online_issn, issn_key)
art_issn <- articles_df %>%
  select(doi_key, source_id, journal_openalex = journal, status, source_issns) %>%
  separate_rows(source_issns, sep = "\\|") %>%
  mutate(issn_key = norm_issn(source_issns)) %>%
  filter(issn_key != "")
# Reasons a journal is not in the sampling pool (defined once, used twice).
funnel_reason <- c(
  no_openalex = sprintf("OpenAlex: no %d articles for the journal's ISSN(s)", PUBLICATION_YEAR),
  cleaned     = "Cleaning: all of the journal's articles removed",
  not_in_mt   = "Not in the MultiTagger predictions file",
  no_emp      = "MultiTagger: no article empirical under the decision rule"
)
journal_funnel <- journals_for_openalex %>%
  select(npi_title = `International Title`, online_issn = `Online ISSN`) %>%
  left_join(
    npi_keys %>%
      inner_join(art_issn, by = "issn_key", relationship = "many-to-many") %>%
      distinct(npi_title, online_issn, doi_key, .keep_all = TRUE) %>%
      group_by(npi_title, online_issn) %>%
      summarise(openalex_name  = paste(unique(journal_openalex), collapse = " | "),
                source_id      = paste(unique(source_id), collapse = " | "),
                n_downloaded   = n_distinct(doi_key),
                n_after_cleaning = n_distinct(doi_key[status == "for_classification"]),
                n_classified   = n_distinct(doi_key[doi_key %in% classified_keys]),
                n_empirical    = n_distinct(doi_key[doi_key %in% empirical_keys]),
                .groups = "drop"),
    by = c("npi_title", "online_issn")) %>%
  mutate(across(starts_with("n_"), ~ coalesce(.x, 0L)),
         reason_not_in_pool = case_when(
           n_downloaded == 0     ~ funnel_reason[["no_openalex"]],
           n_after_cleaning == 0 ~ funnel_reason[["cleaned"]],
           n_classified == 0     ~ funnel_reason[["not_in_mt"]],
           n_empirical == 0      ~ funnel_reason[["no_emp"]],
           TRUE                  ~ NA_character_))
write_csv(journal_funnel, "journal_funnel_to_sample.csv")

n_funnel <- function(r) sum(journal_funnel$reason_not_in_pool == r, na.rm = TRUE)
j_sent     <- nrow(journals_for_openalex)
j_no_oa    <- n_funnel(funnel_reason[["no_openalex"]])
j_cleaned  <- n_funnel(funnel_reason[["cleaned"]])
j_not_mt   <- n_funnel(funnel_reason[["not_in_mt"]])
j_no_emp   <- n_funnel(funnel_reason[["no_emp"]])
j_pool_npi <- sum(journal_funnel$n_empirical > 0)
j_pool_oa  <- n_distinct(empirical_articles$journal)
j_sample   <- n_distinct(empirical_sample$journal)

exclusion_table_journals <- tribble(
  ~stage, ~reason_excluded, ~n_excluded, ~n_remaining,
  "NPI register", sprintf("All journals (downloaded %s)", format(npi_download_time, "%Y-%m-%d")),
  NA, n_npi_entries,
  "Field and language", "Not NPI field Psychology, or not English",
  n_npi_entries - nrow(psych_db), nrow(psych_db),
  "1a. NPI level", sprintf("Not level 1 or 2 in %s", level_col),
  nrow(psych_db) - n_level_eligible, n_level_eligible,
  "1b. Online ISSN", "No online ISSN in the NPI",
  n_level_eligible - n_issn_eligible, n_issn_eligible,
  "1c. Journal title", "Title keyword suggesting non-empirical content",
  n_issn_eligible - nrow(filtered_psych_db), nrow(filtered_psych_db),
  "1e-f. Journal classification", "Judged not to publish original empirical research (LLM + manual review)",
  n_journals_excluded_classification, j_sent,
  "OpenAlex download", sprintf("No %d research articles in OpenAlex for the journal's ISSN(s)", PUBLICATION_YEAR),
  j_no_oa, j_sent - j_no_oa,
  "Cleaning", "All of the journal's articles removed (e.g. no abstracts available)",
  j_cleaned, j_sent - j_no_oa - j_cleaned
)
if (j_not_mt > 0)
  exclusion_table_journals <- bind_rows(exclusion_table_journals, tibble(
    stage = "MultiTagger file", reason_excluded = "Cleaned articles not in the MultiTagger predictions file",
    n_excluded = j_not_mt, n_remaining = j_sent - j_no_oa - j_cleaned - j_not_mt))
exclusion_table_journals <- bind_rows(exclusion_table_journals, tribble(
  ~stage, ~reason_excluded, ~n_excluded, ~n_remaining,
  sprintf("MultiTagger (rule %s)", MT_DECISION_RULE), "No article classified as empirical",
  j_no_emp, j_pool_npi,
  "Sampling pool", "NPI journals that OpenAlex treats as one journal counted once (not an exclusion)",
  j_pool_npi - j_pool_oa, j_pool_oa,
  "Sample", sprintf("Journals with >= 1 sampled article (%s sampling)", SAMPLING_METHOD),
  j_pool_oa - j_sample, j_sample
))

# --- Article table
a_down     <- nrow(articles_df)
a_record   <- sum(articles_df$status == "excluded_record")
a_title    <- sum(articles_df$status == "excluded_title")
a_noabs    <- sum(articles_df$status == "no_abstract")
a_junk     <- sum(articles_df$status == "junk_abstract")
a_clean    <- sum(articles_df$status == "for_classification")
a_mt       <- nrow(classified_articles)
a_noop     <- sum(classified_articles$mt_status == "no_opinion")
a_nonemp   <- sum(classified_articles$mt_status == "non_empirical")
a_eligible <- nrow(empirical_articles)
a_sample   <- nrow(empirical_sample)
a_pubmed   <- sum(classified_articles$abstract_source %in% "pubmed")

exclusion_table_articles <- tribble(
  ~stage, ~reason_excluded, ~n_excluded, ~n_remaining,
  "OpenAlex download", sprintf("%d %s articles, language %s, from the journals above",
                               PUBLICATION_YEAR, DOCUMENT_TYPE, LANGUAGE), NA, a_down,
  "3b. Record cleaning", "Missing title, missing or duplicate DOI, or title identical to journal name",
  a_record, a_down - a_record,
  "3c. Abstract missing", "No abstract in OpenAlex or PubMed",
  a_noabs, a_down - a_record - a_noabs,
  "3c. Abstract unusable", "Boilerplate/placeholder, < 100 characters, same as title, non-English, or duplicated across articles",
  a_junk, a_down - a_record - a_noabs - a_junk,
  "3c2. Title screening", "Not a research article by title (front matter, notices, editorials, awards, conference and other announcements)",
  a_title, a_clean
)
if (a_mt != a_clean)
  exclusion_table_articles <- bind_rows(exclusion_table_articles, tibble(
    stage = "MultiTagger file", reason_excluded = "Difference between cleaned articles and MultiTagger predictions file (cleaning changed after the MultiTagger run)",
    n_excluded = a_clean - a_mt, n_remaining = a_mt))
exclusion_table_articles <- bind_rows(exclusion_table_articles, tribble(
  ~stage, ~reason_excluded, ~n_excluded, ~n_remaining,
  "MultiTagger: no opinion", "No publication-type label assigned",
  a_noop, a_mt - a_noop,
  sprintf("MultiTagger: non-empirical (rule %s)", MT_DECISION_RULE),
  "At least one review/commentary/notice-type label (Groups 2-3, incl. labels moved after manual review)",
  a_nonemp, a_eligible,
  "Sampling", sprintf("Not selected (%s sampling, seed %d) - by design, not an exclusion",
                      SAMPLING_METHOD, RANDOM_SEED),
  a_eligible - a_sample, a_sample
))

exclusion_reasons_detail <- articles_df %>%
  filter(status != "for_classification") %>%
  mutate(reason = case_when(status == "excluded_record" ~ exclusion_reason,
                            status == "excluded_title"  ~ title_screen_reason,
                            TRUE                        ~ abstract_reason)) %>%
  count(status, reason, name = "n") %>%
  arrange(status, desc(n))

write_csv(exclusion_table_journals, "exclusion_table_journals.csv")
write_csv(exclusion_table_articles, "exclusion_table_articles.csv")
write_csv(exclusion_reasons_detail, "exclusion_reasons_detail.csv")

print_exclusion_tables <- function() {
  cat("TABLE 1. JOURNAL EXCLUSIONS\n")
  print(exclusion_table_journals, n = Inf, width = 200)
  cat("\nTABLE 2. ARTICLE EXCLUSIONS\n")
  print(exclusion_table_articles, n = Inf, width = 200)
  cat(sprintf("\nNote: %d of the %d articles given to MultiTagger have an abstract recovered from PubMed.\n",
              a_pubmed, a_mt))
  cat("\nArticle exclusions by detailed reason:\n")
  print(exclusion_reasons_detail, n = Inf, width = 160)
  cat("\nJournals sent to OpenAlex but not in the sampling pool:\n")
  journal_funnel %>% filter(!is.na(reason_not_in_pool)) %>%
    arrange(reason_not_in_pool, npi_title) %>%
    select(reason_not_in_pool, npi_title, online_issn, n_downloaded, n_after_cleaning) %>%
    print(n = Inf, width = 200)
  cat("\n")
}
print_exclusion_tables()
cat("Saved: exclusion_table_journals.csv, exclusion_table_articles.csv,\n")
cat("       exclusion_reasons_detail.csv, journal_funnel_to_sample.csv\n\n")

section("STEP 8b: WRITING SUMMARY REPORT")

stage_n <- function(s) sum(articles_df$status == s)

sink("classification_summary.txt")
cat(sprintf("PSYCHOLOGY ARTICLES %d - CLEANING, CLASSIFICATION AND SAMPLING SUMMARY\n",
            PUBLICATION_YEAR))
cat("=====================================================================\n\n")
cat(sprintf("Generated:       %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat(sprintf("Run label:       %s\n", RUN_LABEL))
cat(sprintf("NPI downloaded:  %s\n", format(npi_download_time, "%Y-%m-%d %H:%M:%S")))
cat(sprintf("NPI header fix:  %s\n\n", if (header_fix_applied) "applied" else "not needed"))

cat("JOURNAL FILTERING (NPI)\n-----------------------\n")
cat(sprintf("Total NPI entries:                    %d\n", n_npi_entries))
cat(sprintf("Psychology journals (English):        %d\n", nrow(psych_db)))
cat(sprintf("1a. Level 1-2 (%s):           %d\n", level_col, n_level_eligible))
cat(sprintf("1b. ... with Online ISSN:             %d\n", n_issn_eligible))
cat(sprintf("1c. ... after title keyword filter:   %d\n", nrow(filtered_psych_db)))
cat(sprintf("Excluded by journal classification:   %d\n", n_journals_excluded_classification))
cat(sprintf("Classification carried over (%s): %d\n", previous_source, nrow(journals_carried_over)))
cat(sprintf("Classified for this run:              %d\n", nrow(journals_to_classify)))
cat(sprintf("Dropped since previous list:          %d\n", n_dropped))
if (!is.null(journal_classification_changes))
  cat(sprintf("Classification changed vs previous:   %d\n", nrow(journal_classification_changes)))
cat(sprintf("Journals sent to OpenAlex:            %d\n", nrow(journals_for_openalex)))
cat(sprintf("  ISSNs with no articles returned:    %d\n\n", nrow(issns_without_articles)))

cat("ARTICLE DOWNLOAD AND CLEANING\n-----------------------------\n")
cat(sprintf("Year / type / language:               %d / %s / %s\n", PUBLICATION_YEAR, DOCUMENT_TYPE, LANGUAGE))
cat(sprintf("OpenAlex downloaded:                  %s\n", format(openalex_download_time, "%Y-%m-%d %H:%M")))
cat(sprintf("Downloaded (OpenAlex reported):       %d (%d)\n", total_fetched, sum(openalex_counts)))
cat(sprintf("Excluded - record cleaning:           %d\n", stage_n("excluded_record")))
cat(sprintf("Excluded - no abstract:               %d\n", stage_n("no_abstract")))
cat(sprintf("Excluded - unusable abstract:         %d\n", stage_n("junk_abstract")))
cat(sprintf("Excluded - title screening:           %d\n", stage_n("excluded_title")))
cat(sprintf("Sent to MultiTagger:                  %d\n", stage_n("for_classification")))
cat(sprintf("  abstract from OpenAlex / PubMed:    %d / %d\n",
            sum(classified_articles$abstract_source %in% "openalex"),
            sum(classified_articles$abstract_source %in% "pubmed")))
cat(sprintf("Poorly indexed journals:              %d\n", nrow(journals_poorly_indexed)))
if (file.exists(PUBMED_CACHE_FILE)) {
  pubmed_dates <- range(read_chr_csv(PUBMED_CACHE_FILE)$retrieved, na.rm = TRUE)
  cat(sprintf("PubMed lookups made:                  %s to %s\n", pubmed_dates[1], pubmed_dates[2]))
}
cat("  (original run: 37659 sent to MultiTagger, 3183 abstracts from PubMed,\n")
cat("   PubMed lookups Sept 2026 - see PUBLIC VERSION NOTE)\n")
if (abstracts_removed)
  cat("Abstracts in multitagger_predictions.csv: removed (public version)\n")
cat("\n")

cat("MULTITAGGER CLASSIFICATION\n--------------------------\n")
cat(sprintf("Decision rule:                        %s\n", MT_DECISION_RULE))
cat(sprintf("Manual review decision (Step 4e-1):   moved to non-empirical: %s\n",
            if (length(MANUAL_LABELS_TO_NON_EMPIRICAL) == 0) "none" else
              paste(sprintf("%s (%d articles)", manual_label_decisions$label,
                            manual_label_decisions$n_articles), collapse = ", ")))
for (s in c("empirical", "non_empirical", "no_opinion"))
  cat(sprintf("  %-34s %d (%.1f%%)\n", s, sum(classified_articles$mt_status == s),
              100 * mean(classified_articles$mt_status == s)))
cat("\n")

cat("RANDOM SAMPLE\n-------------\n")
cat(sprintf("Empirical articles available:         %d\n", nrow(empirical_articles)))
cat(sprintf("Sample size requested / achieved:     %d / %d\n", SAMPLE_SIZE, nrow(empirical_sample)))
cat(sprintf("Sampling method:                      %s%s\n", SAMPLING_METHOD,
            switch(SAMPLING_METHOD,
                   balanced = sprintf(" (cap %d per journal)", journal_cap),
                   sqrt = sprintf(" (stratified by journal, n proportional to sqrt(journal size)%s)",
                                  if (SQRT_MIN_PER_JOURNAL > 0) sprintf(", min %d", SQRT_MIN_PER_JOURNAL) else ""),
                   "")))
cat(sprintf("Journals in sample:                   %d\n", n_distinct(empirical_sample$journal)))
cat(sprintf("Random seed:                          %d\n", RANDOM_SEED))
cat(sprintf("RIS files:                            %d\n\n", n_ris_batches))

cat("EXCLUSION TABLES\n----------------\n")
print_exclusion_tables()

cat("R SESSION INFO\n--------------\n")
cat(sprintf("R version: %s\nPlatform:  %s\n", R.version.string, R.version$platform))
sink()
cat("Saved: classification_summary.txt\n\n")


################################################################################
# STEP 9 (OPTIONAL): COMPARE AGAINST A REFERENCE RUN
#
# For checking reproduction of an earlier pilot: set PUBLICATION_YEAR and
# NPI_LEVEL_YEAR to that pilot's values, point REFERENCE_DIRECTORY at its
# folder, and compare stage by stage. Differences at the journal stage point
# to NPI register changes; at the article stage to OpenAlex changes; after
# that to cleaning/classification changes (the classifier itself changed from
# LLM to MultiTagger after Pilot 2, so sample-level differences are expected).
################################################################################

if (!is.na(REFERENCE_DIRECTORY) && dir.exists(REFERENCE_DIRECTORY)) {
  section("STEP 9: COMPARING AGAINST REFERENCE RUN")
  
  compare_sets <- function(label, current, reference) {
    current <- unique(na.omit(current)); reference <- unique(na.omit(reference))
    cat(sprintf("%-28s current %6d | reference %6d | shared %6d | only current %6d | only reference %6d\n",
                label, length(current), length(reference), length(intersect(current, reference)),
                length(setdiff(current, reference)), length(setdiff(reference, current))))
  }
  ref <- function(f) {
    p <- file.path(REFERENCE_DIRECTORY, f)
    if (file.exists(p)) read_csv(p, show_col_types = FALSE, col_types = cols(.default = "c")) else NULL
  }
  
  sink("reference_comparison.txt", split = TRUE)
  cat(sprintf("Reference: %s\n\n", REFERENCE_DIRECTORY))
  r <- ref("journals_for_openalex.csv")
  if (!is.null(r)) compare_sets("Journals (Online ISSN)", journals_for_openalex$`Online ISSN`, r$`Online ISSN`)
  r <- ref("articles_master.csv")
  if (!is.null(r)) compare_sets("Downloaded articles (DOI)", articles_df$doi_key, norm_doi(r$doi))
  r <- ref("articles_classified_all.csv")
  if (!is.null(r)) compare_sets("Classified articles (DOI)", norm_doi(classified_articles$doi), norm_doi(r$doi))
  r <- ref("articles_empirical_sample.csv")
  if (!is.null(r)) compare_sets("Sampled articles (DOI)", norm_doi(empirical_sample$doi), norm_doi(r$doi))
  sink()
  cat("\nSaved: reference_comparison.txt\n\n")
}

section("PIPELINE COMPLETE")