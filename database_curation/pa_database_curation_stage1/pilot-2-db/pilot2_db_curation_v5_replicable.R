################################################################################
# Pilot TF Meta-Assessment Psychology Journal Pilot 2 Database Curation
# REPLICABLE VERSION
################################################################################
#
# PURPOSE:
#   Builds the Pilot 2 article database for the Pilot TF Meta-Assessment.
#   Filters psychology journals from the Norwegian Publication Indicator (NPI)
#   system to identify high-quality (levels 1-2), empirical, English-language
#   journals with online ISSNs from 2023. Downloads articles for those journals
#   from OpenAlex, classifies them as empirical or non-empirical via Claude AI,
#   randomly samples 6,000 empirical articles, and exports to RIS for Zotero.
#
# REPLICABLE VERSION vs. REPRODUCIBLE VERSION:
#   This REPLICABLE VERSION is the actual R script used to build the Pilot 2
#   psychology article database. Running it end to end will replicate the full
#   pipeline from scratch, fetching live data from the NPI register and the
#   OpenAlex API, classifying articles via LLM, and sampling 6,000 empirical
#   articles for Zotero import.
#
#   Note that results may not be identical to the original Pilot 2 database.
#   OpenAlex in particular indexes new sources continuously, so the set of
#   articles returned for a given journal and year can grow or change between
#   runs. The NPI register is also updated periodically. This means the
#   downloaded article pool, and consequently the empirical sample, may differ
#   from ours even when the script and configuration are unchanged.
#
#   This is why a companion REPRODUCIBLE VERSION of the script was created.
#   The reproducible version checks for saved CSV outputs at each step and
#   loads them from disk rather than re-fetching from online sources, allowing
#   exact reproduction of the Pilot 2 database given the original output files.
#   The reproducible version is not included in this public set.
#
# WORKFLOW:
#   Step 0  [auto]    Download NPI database; extract Psychology (English) journals
#   Step 1  [auto]    Keyword / level / ISSN filter / pre-curated journal classification exclusions
#   Step 2  [auto]    Download articles from OpenAlex for included journals
#   Step 3  [auto]    Pre-filter articles; prepare batches for LLM classification
#   Step 3d [manual]  LLM article-level empirical/non-empirical classification (if no classified files exist)
#   Step 4  [auto]    Merge classified batches; sample 6,000 empirical articles
#   Step 5  [auto]    Export sample to RIS for Zotero
#   Step 6  [auto]    Write summary report
#
# INPUT FILES:
#   None required at start (NPI database is downloaded automatically).
#   Before Step 1c: journals_llm_classified_final.csv  (see JOURNAL_CLASSIFICATION_README.md)
#   Before Step 4:  articles_classified_batch_XX.csv   (LLM output, one per batch; Step 3d)
#
# OUTPUT FILES:
#   NPI_Scientific_Journals_2023.csv          Full NPI database (downloaded)
#   psych_db.csv                              All Psychology (English) journals
#   excluded_psych_db.csv                     Journals excluded by keyword filter
#   filtered_psych_db.csv                     Journals after keyword/level/ISSN filter
#   journals_for_openalex.csv                 Final journal list after classification exclusions
#   articles_master.csv                       All downloaded articles (pre-classification)
#   articles_excluded_by_title_keyword.csv    Articles removed by title keyword filter
#   articles_abstracts_for_classification.csv Articles with usable abstracts (article_id
#                                             assigned here). Also the basis of the
#                                             MultiTagger input (see the MultiTagger README)
#   articles_for_classification_batch_XX.csv  Article batches for LLM classification
#   articles_classified_batch_XX.csv          Classification results (manual input)
#   articles_classified_all.csv               Merged classification results
#   articles_empirical_sample.csv             Random sample of 6,000 empirical articles
#   journal_sample_summary.csv                Journal representation in final sample
#   psychology_2023_empirical_for_zotero_part_XX.ris  Zotero import files (batched)
#   classification_summary.txt                Summary report
#
# CONTACT:     Mary Beth Neff (marybethneff@gmail.com)
# INSTITUTION: University of Oslo, Norway
# DATE:        2026-02-23 (original); 2026-11-19 (public tidy: working folder,
#              View() calls, file names; logic unchanged)
# VERSION:     5 (original - i.e. replicable vs)
#
# DEPENDENCIES:
#   R >= 4.1.0
#   dplyr    >= 1.0.0   data manipulation
#   readr    >= 2.0.0   CSV I/O
#   stringr  >= 1.4.0   string operations
#   httr     >= 1.4.0   HTTP requests
#   jsonlite >= 1.7.0   JSON parsing
#
# LLM TRANSPARENCY NOTE:
#   This script was developed with Claude (Anthropic, Sonnet 4.5).
#   LLM-dependent classification is used at one point in the automated pipeline:
#     Step 3d  Article-level empirical/non-empirical classification (title + abstract)
#
#   Journal-level classification (used in Step 1c) was performed externally via LLM and
#   manual review, and is provided as a pre-curated CSV. See
#   JOURNAL_CLASSIFICATION_README.md for full documentation of that process.
#
#   Article classification criteria:
#     EMPIRICAL (Yes)     Experiments, surveys, observational studies, meta-analyses,
#                         case studies, longitudinal studies, psychometric validation,
#                         secondary data analyses, qualitative studies (interviews,
#                         ethnography, thematic analysis), discourse/narrative/
#                         conversation analysis, mixed methods
#     NON-EMPIRICAL (No)  Theoretical papers, narrative literature reviews (without
#                         meta-analysis), commentaries, perspectives, editorials,
#                         methodological tutorials without data, guidelines
#
################################################################################
# SETUP
################################################################################

library(dplyr)
library(readr)
library(stringr)
library(httr)
library(jsonlite)

# SET THIS: the folder where input files are kept and all outputs are written.
# Example: output_directory <- "C:/path/to/your/folder"
# Leave as NA to use the current working directory (getwd()).
output_directory <- NA
if (is.na(output_directory)) output_directory <- getwd()
if (!dir.exists(output_directory))
  stop("output_directory not found: ", output_directory,
       "\nEdit output_directory in the SETUP section.")
setwd(output_directory)

cat("Package versions:\n")
cat(sprintf("  dplyr:    %s\n", packageVersion("dplyr")))
cat(sprintf("  readr:    %s\n", packageVersion("readr")))
cat(sprintf("  stringr:  %s\n", packageVersion("stringr")))
cat(sprintf("  httr:     %s\n", packageVersion("httr")))
cat(sprintf("  jsonlite: %s\n\n", packageVersion("jsonlite")))


################################################################################
# CONFIGURATION
################################################################################

PUBLICATION_YEAR          <- 2023    # Target publication year
DOCUMENT_TYPE             <- "article" # OpenAlex term
LANGUAGE                  <- "en"
ARTICLES_PER_PAGE         <- 200     # OpenAlex max page size
REQUEST_DELAY             <- 0.5     # Seconds between API requests (polite usage)
SAMPLE_SIZE               <- 6000    # Empirical articles to randomly sample
RANDOM_SEED               <- 123     # Reproducibility seed
ISSN_BATCH_SIZE           <- 25      # ISSNs per OpenAlex request (avoids HTTP 400)
CLASSIFICATION_BATCH_SIZE <- 5000    # Articles per CSV sent to Claude
RIS_BATCH_SIZE            <- 1000    # Articles per RIS export file


################################################################################
# HELPER FUNCTIONS
################################################################################

# Reconstruct abstract text from OpenAlex inverted-index format.
# OpenAlex stores abstracts as word-to-position mappings; this reverses that.
reconstruct_abstract <- function(inverted_index) {
  if (is.null(inverted_index) || length(inverted_index) == 0) return(NA)
  tryCatch({
    max_pos <- max(unlist(inverted_index))
    words   <- character(max_pos + 1)        # +1 to accommodate 0-based positions
    for (word in names(inverted_index)) {
      for (pos in inverted_index[[word]]) words[pos + 1] <- word  # +1 for R's 1-based vectors
    }
    paste(words[words != ""], collapse = " ")
  }, error = function(e) NA)
}

safe_field <- function(x) if (is.null(x) || length(x) == 0) NA else x[[1]]


################################################################################
# STEP 0: DOWNLOAD NPI DATABASE AND EXTRACT PSYCHOLOGY JOURNALS
#
# Sub-steps:
#   0a. Download NPI database
#   0b. Correct column headers
#   0c. Extract Psychology (English) journals
################################################################################

# --- 0a. Download NPI database ------------------------------------------------
cat("================================================================================\n")
cat("STEP 0a: DOWNLOADING NPI DATABASE\n")
cat("================================================================================\n\n")

npi_url    <- "https://kanalregister.hkdir.no/publiseringskanaler/csvliste/tidsskrift?request_locale=en"
local_file <- "NPI_Scientific_Journals_2023.csv"

cat("Downloading NPI database...\n")
download_success <- tryCatch({
  download.file(npi_url, destfile = local_file, method = "auto", quiet = FALSE)
  TRUE
}, error = function(e) {
  cat(sprintf("ERROR: %s\n", e$message))
  FALSE
})
if (!download_success) stop("Download failed. Check internet connection and try again.")

full_db <- read_delim(
  local_file,
  delim          = ";",
  quote          = '"',
  locale         = locale(encoding = "UTF-8"),
  show_col_types = FALSE,
  col_types      = cols(.default = "c")
)
cat(sprintf("Loaded: %d journal entries\n\n", nrow(full_db)))

cat("Step 0a complete.\n\n")

# --- 0b. Correct column headers -----------------------------------------------
cat("================================================================================\n")
cat("STEP 0b: CORRECTING COLUMN HEADERS\n")
cat("================================================================================\n\n")

# As of Jan/Feb 2026 the NPI download has a one-position left-shift from
# publisher_id onwards in headers despite following NPI import instructions.
# Fix: shift those headers one position right. The slot at the original
# "publisher_id" position is renamed to UNKNOWN_BUT_IRRELEVANT as it is not
# needed here.
# WARNING: Always verify your own column alignment first; if okay, skip this
# step and proceed straight to Step 0c.

cat("Applying column-header correction...\n")
corrected_full_db  <- full_db
original_names     <- names(full_db)
publisher_id_index <- which(original_names == "publisher_id")

if (length(publisher_id_index) > 0) {
  corrected_names <- original_names
  for (i in length(corrected_names):(publisher_id_index + 1)) {
    corrected_names[i] <- original_names[i - 1]
  }
  corrected_names[publisher_id_index] <- "UNKNOWN_BUT_IRRELEVANT"
  names(corrected_full_db) <- corrected_names
  cat("Column headers corrected.\n\n")
} else {
  cat("WARNING: 'publisher_id' not found - skipping header correction.\n\n")
}

cat("Corrected column headers:\n")
print(names(corrected_full_db))
cat("\n")

cat("Sample (first 5 journals, key columns):\n")
corrected_full_db %>%
  select(`NPI Scientific Field`, Language, `International Title`,
         `Level 2023`, `Online ISSN`) %>%
  head(5) %>%
  print()
cat("\n")

cat("Step 0b complete.\n\n")

# --- 0c. Extract Psychology (English) journals --------------------------------
cat("================================================================================\n")
cat("STEP 0c: EXTRACTING PSYCHOLOGY (ENGLISH) JOURNALS\n")
cat("================================================================================\n\n")

psych_db <- corrected_full_db %>%
  filter(`NPI Scientific Field` == "Psychology", Language == "English")

cat(sprintf("Total NPI entries:             %d\n", nrow(corrected_full_db)))
cat(sprintf("Psychology (English) journals: %d\n", nrow(psych_db)))
cat(sprintf("Excluded:                      %d\n\n",
            nrow(corrected_full_db) - nrow(psych_db)))

write_csv(psych_db, "psych_db.csv")
cat("Saved: psych_db.csv\n\n")

cat("Step 0c complete.\n\n")

cat("================================================================================\n")
cat("STEP 0 COMPLETE\n")
cat("================================================================================\n\n")


################################################################################
# STEP 1: KEYWORD / LEVEL / ISSN FILTER
#
# Sub-steps:
#   1a. Define non-empirical keyword pattern
#   1b. Apply filter and save results
#   1c. Apply pre-curated journal classification exclusions
################################################################################

# --- 1a. Define non-empirical keyword pattern ---------------------------------
cat("================================================================================\n")
cat("STEP 1a: DEFINING NON-EMPIRICAL KEYWORD PATTERN\n")
cat("================================================================================\n\n")

# Title keywords that suggest predominantly non-empirical content.
non_empirical_pattern <- regex(
  paste(collapse = "|", c(
    "REVIEW", "OVERVIEW", "ANNUAL",
    "OPINION", "COMMENTARY", "COMMENT", "PERSPECTIVES", "VIEWPOINT",
    "TRENDS", "DIRECTIONS", "FRONTIERS", "HORIZON", "COMPASS",
    "THEORY", "THEORETICAL",
    "METHODS", "METHODOLOGY", "METHODOLOGICAL",
    "ADVANCES", "ADVANCING", "PROGRESS",
    "BULLETIN", "BRIEF", "NEWS", "NEWSLETTER", "REPORT",
    "PROCEEDINGS", "CONFERENCE",
    "FORUM", "DEBATE", "CURRENT", "CONTEMPORARY", "EMERGING",
    "HANDBOOK", "ENCYCLOPEDIA", "ENCYCLOPAEDIA"
  )),
  ignore_case = TRUE
)

cat("Non-empirical keyword pattern defined.\n\n")
cat("Step 1a complete.\n\n")

# --- 1b. Apply filter and save results ----------------------------------------
cat("================================================================================\n")
cat("STEP 1b: APPLYING KEYWORD / LEVEL / ISSN FILTER\n")
cat("================================================================================\n\n")

filtered_psych_db <- psych_db %>%
  filter(
    !is.na(`Online ISSN`) & `Online ISSN` != "" & `Online ISSN` != '""',
    `Level 2023` %in% c("1", "2"),
    !str_detect(`Original Title`,      non_empirical_pattern),
    !str_detect(`International Title`, non_empirical_pattern)
  )

excluded_psych_db <- psych_db %>%
  filter(!journal_id %in% filtered_psych_db$journal_id)

cat(sprintf("Psychology journals (Step 0): %d\n",   nrow(psych_db)))
cat(sprintf("Included after filtering:     %d\n",   nrow(filtered_psych_db)))
cat(sprintf("Excluded:                     %d\n\n", nrow(excluded_psych_db)))

write_csv(filtered_psych_db, "filtered_psych_db.csv")
write_csv(excluded_psych_db, "excluded_psych_db.csv")
cat("Saved: filtered_psych_db.csv\n")
cat("Saved: excluded_psych_db.csv\n\n")

cat("Step 1b complete.\n\n")

cat("================================================================================\n")
cat("STEP 1 COMPLETE\n")
cat("================================================================================\n\n")


################################################################################
# STEP 1c (PRE-CURATED): JOURNAL EMPIRICAL CLASSIFICATION FILTER
#
# The keyword filter catches most non-empirical journals by title, but some
# slip through. This step loads a pre-curated classification file and excludes
# any journals flagged as non-empirical before the OpenAlex download.
#
# The classification file (journals_llm_classified_final.csv) was produced
# through a combination of LLM classification and manual review. See
# JOURNAL_CLASSIFICATION_README.md for full documentation of that process.
#
# EXCLUSION RULE:
#   Journals where final_empirical_no = "yes" are excluded. This covers:
#     - LLM-classified 'no' with medium or high confidence
#     - Journals added via manual review
#   Journals classified 'yes', 'mixed', or 'no' with low confidence are retained.
#
################################################################################

# --- 1c. Load journal classifications and apply exclusions --------------------
cat("================================================================================\n")
cat("STEP 1c: LOADING JOURNAL CLASSIFICATIONS AND APPLYING EXCLUSIONS\n")
cat("================================================================================\n\n")

# This step expects a pre-curated file: journals_llm_classified_final.csv
# See JOURNAL_CLASSIFICATION_README.md for instructions on how to create or
# update this file.

classified_file <- file.path(output_directory, "journals_llm_classified_final.csv")

if (!file.exists(classified_file)) {
  cat("ERROR: journals_llm_classified_final.csv not found.\n\n")
  cat("This file must be present before running Step 1c.\n")
  cat("See JOURNAL_CLASSIFICATION_README.md for instructions on how to create it.\n\n")
  cat(sprintf("Expected location: %s\n\n", classified_file))
  stop("Stopping. Re-run after placing journals_llm_classified_final.csv in the output directory.")
}

cat("Found journals_llm_classified_final.csv - loading.\n\n")

journals_llm_classified <- read_csv(classified_file, show_col_types = FALSE)

# Validate expected columns are present
required_cols <- c("Online ISSN", "International Title", "publishes_original_research",
                   "confidence", "manual_review", "final_empirical_no")
missing_cols  <- setdiff(required_cols, colnames(journals_llm_classified))
if (length(missing_cols) > 0) {
  cat(sprintf("ERROR: journals_llm_classified_final.csv is missing required column(s): %s\n",
              paste(missing_cols, collapse = ", ")))
  cat("See JOURNAL_CLASSIFICATION_README.md for the expected file structure.\n\n")
  stop("Stopping. Fix the classification file and re-run.")
}

# Exclusions
excluded_by_classification <- journals_llm_classified %>%
  filter(tolower(final_empirical_no) == "yes") %>%
  pull(`Online ISSN`)

# Transparency reporting: LLM-classified exclusions
llm_excluded <- journals_llm_classified %>%
  filter(
    tolower(final_empirical_no) == "yes",
    tolower(manual_review) != "yes"
  )
if (nrow(llm_excluded) > 0) {
  cat(sprintf("Journals excluded by LLM classification (no, medium/high confidence): %d\n",
              nrow(llm_excluded)))
  for (j in llm_excluded$`International Title`) cat(sprintf("  - %s\n", j))
  cat("\n")
}

# Transparency reporting: manual review exclusions
manual_excluded <- journals_llm_classified %>%
  filter(tolower(manual_review) == "yes")
if (nrow(manual_excluded) > 0) {
  cat(sprintf("Journals excluded via manual review: %d\n", nrow(manual_excluded)))
  for (j in manual_excluded$`International Title`) cat(sprintf("  - %s\n", j))
  cat("\n")
}

# Transparency reporting: low-confidence "no" journals retained
low_confidence_no <- journals_llm_classified %>%
  filter(
    tolower(publishes_original_research) == "no",
    tolower(confidence) == "low"
  )
if (nrow(low_confidence_no) > 0) {
  cat(sprintf("NOTE: %d journal(s) classified 'no' with low confidence - retained in dataset:\n",
              nrow(low_confidence_no)))
  for (j in low_confidence_no$`International Title`) cat(sprintf("  - %s\n", j))
  cat("\n")
}

# Apply exclusions and save
journals_for_openalex <- filtered_psych_db %>%
  filter(!`Online ISSN` %in% excluded_by_classification)

cat(sprintf("Journals after keyword filter:              %d\n", nrow(filtered_psych_db)))
cat(sprintf("Journals excluded (final_empirical_no=yes): %d\n", length(excluded_by_classification)))
cat(sprintf("Journals retained (yes / mixed):            %d\n\n", nrow(journals_for_openalex)))

write_csv(journals_for_openalex, "journals_for_openalex.csv")
cat("Saved: journals_for_openalex.csv\n\n")

cat("Step 1c complete.\n\n")

cat("================================================================================\n")
cat("STEP 1c COMPLETE\n")
cat("================================================================================\n\n")


################################################################################
# STEP 2: DOWNLOAD ARTICLES FROM OPENALEX
#
# Sub-steps:
#   2a. Set up ISSN batches
#   2b. Download articles from OpenAlex API
################################################################################

# --- 2a. Set up ISSN batches --------------------------------------------------
cat("================================================================================\n")
cat("STEP 2a: SETTING UP ISSN BATCHES\n")
cat("================================================================================\n\n")

# Pull ISSNs dynamically from the included journal database.
issns <- journals_for_openalex %>%
  filter(!is.na(`Online ISSN`) & `Online ISSN` != "") %>%
  pull(`Online ISSN`) %>%
  unique()

cat(sprintf("ISSNs sourced from journals_for_openalex: %d\n", length(issns)))
cat(sprintf("Publication year:                         %d\n", PUBLICATION_YEAR))
cat(sprintf("Document type:                            %s\n", DOCUMENT_TYPE))
cat(sprintf("Language:                                 %s\n\n", LANGUAGE))

# ISSNs are split into batches before querying OpenAlex.
# Passing all ISSNs in a single request produces an HTTP 400 error because the
# resulting URL exceeds server length limits. Batches of ISSN_BATCH_SIZE are
# queried sequentially and results are merged into all_articles.
issn_batches   <- split(issns, ceiling(seq_along(issns) / ISSN_BATCH_SIZE))
all_articles   <- list()
total_fetched  <- 0
n_issn_batches <- length(issn_batches)

cat(sprintf("ISSNs split into %d batches of up to %d (avoids HTTP 400).\n\n",
            n_issn_batches, ISSN_BATCH_SIZE))

cat("Step 2a complete.\n\n")

# --- 2b. Download articles from OpenAlex API ----------------------------------
cat("================================================================================\n")
cat("STEP 2b: DOWNLOADING ARTICLES FROM OPENALEX API\n")
cat("================================================================================\n\n")

cat("Starting download (this may take several minutes)...\n\n")

for (batch_num in seq_along(issn_batches)) {
  
  batch_issns   <- issn_batches[[batch_num]]
  issn_string   <- paste(batch_issns, collapse = "|")
  filter_string <- paste0(
    "primary_location.source.issn:", issn_string,
    ",publication_year:",            PUBLICATION_YEAR,
    ",type:",                        DOCUMENT_TYPE,
    ",language:",                    LANGUAGE
  )
  
  cat(sprintf("Batch %d / %d (%d ISSNs):\n", batch_num, n_issn_batches, length(batch_issns)))
  
  page          <- 1
  batch_fetched <- 0
  
  repeat {
    url <- paste0(
      "https://api.openalex.org/works?",
      "filter=",    URLencode(filter_string),
      "&per-page=", ARTICLES_PER_PAGE,
      "&page=",     page
    )
    
    response <- GET(url)
    
    if (status_code(response) != 200) {
      cat(sprintf("  ERROR on page %d: HTTP %d - skipping batch\n",
                  page, status_code(response)))
      break
    }
    
    parsed <- fromJSON(
      content(response, as = "text", encoding = "UTF-8"),
      simplifyVector = FALSE
    )
    
    if (length(parsed$results) == 0) {
      cat("  No more results.\n")
      break
    }
    
    for (article in parsed$results) {
      
      doi   <- safe_field(article$doi)
      title <- safe_field(article$display_name)
      year  <- safe_field(article$publication_year)
      
      journal <- if (!is.null(article$primary_location$source$display_name))
        article$primary_location$source$display_name else NA
      
      volume <- safe_field(article$biblio$volume)
      issue  <- safe_field(article$biblio$issue)
      
      first_page <- safe_field(article$biblio$first_page)
      last_page  <- safe_field(article$biblio$last_page)
      pages <- if (!is.na(first_page) && !is.na(last_page)) {
        paste0(first_page, "-", last_page)
      } else if (!is.na(first_page)) {
        first_page
      } else NA
      
      # Format authors (Zotero fetches full list via DOI)
      authors <- NA
      if (!is.null(article$authorships) && length(article$authorships) > 0) {
        author_names <- Filter(Negate(is.na), sapply(article$authorships, function(a) {
          safe_field(a$author$display_name)
        }))
        authors <- if (length(author_names) == 1) {
          author_names[1]
        } else if (length(author_names) == 2) {
          paste(author_names, collapse = " and ")
        } else if (length(author_names) > 2) {
          paste0(author_names[1], " et al.")
        }
      }
      
      # Reconstruct abstract from inverted index
      abstract <- if (!is.null(article$abstract_inverted_index))
        reconstruct_abstract(article$abstract_inverted_index) else NA
      
      all_articles[[length(all_articles) + 1]] <- list(
        doi = doi, title = title, journal = journal, abstract = abstract,
        year = year, volume = volume, issue = issue, pages = pages, authors = authors
      )
    }
    
    batch_fetched <- batch_fetched + length(parsed$results)
    total_fetched <- total_fetched + length(parsed$results)
    cat(sprintf("  Page %d: %d results (batch total: %d | overall total: %d)\n",
                page, length(parsed$results), batch_fetched, total_fetched))
    
    if (length(parsed$results) < ARTICLES_PER_PAGE) {
      cat("  Reached last page of batch.\n")
      break
    }
    
    page <- page + 1
    Sys.sleep(REQUEST_DELAY)
  }
  
  cat("\n")
}

cat(sprintf("Download complete: %d articles retrieved across %d batches\n\n",
            total_fetched, n_issn_batches))

cat("Step 2b complete.\n\n")

cat("================================================================================\n")
cat("STEP 2 COMPLETE\n")
cat("================================================================================\n\n")


################################################################################
# STEP 3: PROCESS ARTICLES AND PREPARE FOR CLASSIFICATION
#
# Sub-steps:
#   3a. Convert article list to data frame
#   3b. Pre-filter articles by title keyword
#   3c. Split into abstracts / no-abstracts and batch for classification
################################################################################

# --- 3a. Convert article list to data frame -----------------------------------
cat("================================================================================\n")
cat("STEP 3a: CONVERTING ARTICLE LIST TO DATA FRAME\n")
cat("================================================================================\n\n")

safe_val <- function(lst, key) sapply(lst, function(x) {
  val <- x[[key]]
  if (is.null(val) || length(val) == 0 || is.na(val)) NA else val
})

articles_df <- data.frame(
  doi      = safe_val(all_articles, "doi"),
  title    = safe_val(all_articles, "title"),
  journal  = safe_val(all_articles, "journal"),
  abstract = safe_val(all_articles, "abstract"),
  year     = safe_val(all_articles, "year"),
  volume   = safe_val(all_articles, "volume"),
  issue    = safe_val(all_articles, "issue"),
  pages    = safe_val(all_articles, "pages"),
  authors  = safe_val(all_articles, "authors"),
  stringsAsFactors = FALSE
)

cat(sprintf("Total articles converted:   %d\n", nrow(articles_df)))
cat(sprintf("With abstracts:             %d (%.1f%%)\n",
            sum(!is.na(articles_df$abstract)),
            100 * mean(!is.na(articles_df$abstract))))
cat(sprintf("Without abstracts:          %d (%.1f%%)\n",
            sum(is.na(articles_df$abstract)),
            100 * mean(is.na(articles_df$abstract))))
cat(sprintf("With author info:           %d (%.1f%%)\n\n",
            sum(!is.na(articles_df$authors)),
            100 * mean(!is.na(articles_df$authors))))

cat("Step 3a complete.\n\n")

# Inspect whether abstracts imported correctly (did not truncate at first word).
# Note: if truncation recurs, check reconstruct_abstract() - OpenAlex uses 0-based
# indexing so positions need +1 adjustment for R's 1-based vectors.
articles_df$abstract[1]
articles_df$abstract[18230]
articles_df$abstract[36460]

# --- 3b. Pre-filter articles by title keyword ---------------------------------
cat("================================================================================\n")
cat("STEP 3b: PRE-FILTERING ARTICLES BY TITLE KEYWORD\n")
cat("================================================================================\n\n")

# SCOPE: Keywords are matched against ARTICLE TITLES only. This is intentional -
# the content types being excluded (award notices, conference schedules, calls
# for papers, etc.) are reliably identifiable from the title alone, and
# title-based matching avoids false exclusions from abstracts that may
# legitimately discuss these topics (e.g. a study about conference behaviour
# or a paper reviewing editorial practices).
#
# CHANGELOG:
#   Original v1 set: typographical corrections, retractions, and editorials
#   Extended v2 set: award notices (anchored), advertisements, conference
#     schedules, calls for papers, year-based course listings, webinars,
#     recaps, and supplemental material notices observed in Zotero import
#     review (2026-02-16)
#
# REGEX NOTES:
#   - All matching is case-insensitive via ignore.case = TRUE
#   - \\b = word boundary (prevents false matches, e.g. "award" != "reward")
#   - ^  = start-of-title anchor (used for ambiguous terms)
#   - $  = end-of-title anchor
#   - perl = TRUE ensures \\b word boundaries work reliably across platforms

exclude_keywords <- c(
  
  # --- Typographical / post-publication notices ---
  "corrigendum", "erratum", "\\bretraction\\b", "\\bretracted\\b",
  "\\bcorrection\\b",
  
  # --- Editorial / non-research content ---
  "\\beditorial\\b", "from the editor", "book review", "obituary", "in memoriam",
  "letter to the editor",
  
  # --- Award notices ---
  # Anchored start catches "Award: ..." titles; punctuation variants catch
  # mid-title awards (e.g. "International Humanitarian Award: Garth Neufeld");
  # end-anchor catches titles that close with "...Award"
  "^award", "award announcement", "award notice", "^distinguished contribution award",
  "gold medal",
  "award:",      # mid-title award followed by colon (person/org name)
  "award,",      # comma variant
  "\\baward$",   # title ending with "award"
  
  # --- Advertisements and promotional content ---
  "\\bad(s)?\\b", "advertisement",
  
  # --- Conference / meeting content ---
  "\\bconference\\b", "annual meeting", "symposium recap",
  "\\brecap\\b", "conference schedule", "\\bproceedings\\b",
  
  # --- Calls and announcements ---
  "call for", "call for papers", "\\bcfp\\b",
  "^special issue", "special issue$",
  "save the date",
  
  # --- Training and educational listings ---
  "\\bwebinar\\b",
  "^\\d{4} .* course$",
  "on-demand", "on demand",
  
  # --- Supplemental / ancillary material notices ---
  "^supplemental material", "^supplementary material",
  
  # --- Cover and front matter ---
  "\\bfront matter\\b",
  
  # --- Index and directory content ---
  "author index", "subject index",
  
  # --- Administrative notices ---
  "\\bnotice\\b", "\\bnewsletter\\b",
  
  # --- Standalone schedule entries ---
  "^schedule$"
)

exclude_pattern <- paste(exclude_keywords, collapse = "|")

excluded_articles <- articles_df %>%
  filter(grepl(exclude_pattern, title, ignore.case = TRUE, perl = TRUE))

filtered_articles <- articles_df %>%
  filter(!grepl(exclude_pattern, title, ignore.case = TRUE, perl = TRUE))

cat(sprintf("Before pre-filtering:  %d articles\n",   nrow(articles_df)))
cat(sprintf("After pre-filtering:   %d articles\n",   nrow(filtered_articles)))
cat(sprintf("Removed:               %d articles\n\n", nrow(excluded_articles)))

if (nrow(excluded_articles) > 0) {
  cat("Breakdown by exclusion keyword:\n")
  for (kw in exclude_keywords) {
    n <- sum(grepl(kw, excluded_articles$title, ignore.case = TRUE, perl = TRUE))
    if (n > 0) cat(sprintf("  %-35s %d\n", kw, n))
  }
  cat("\n")
}

write_csv(excluded_articles, "articles_excluded_by_title_keyword.csv")
cat("Saved: articles_excluded_by_title_keyword.csv\n\n")

cat("Step 3b complete.\n\n")

# --- 3c. Split into abstracts / no-abstracts and batch for classification -----
cat("================================================================================\n")
cat("STEP 3c: SPLITTING AND BATCHING ARTICLES FOR CLASSIFICATION\n")
cat("================================================================================\n\n")

# The full set is saved as articles_master.csv (no article_id at this stage).
# It is then split into articles_abstracts_for_classification (articles with
# abstracts, sent to Claude) and articles_no_abstracts (set aside - LLM
# classification was unreliable for title-only articles). The no-abstracts
# save is commented out as it is not needed for the current workflow but
# retained for reference.
#
# Article IDs are assigned AFTER the abstract split, on the abstracts-only
# subset, so that IDs run sequentially from 1 to the number of classified
# articles. This keeps the ID range consistent with classification outputs
# and avoids confusion with the larger article counts seen in earlier steps.
#
# Abstract quality filtering:
#   Some OpenAlex records contain non-abstract content in the abstract field
#   (e.g. funding acknowledgments, HAL "International audience" tags, MathML
#   rendering notices). These are detected and excluded BEFORE cleaning so
#   the junk detection operates on raw content. Remaining abstracts are then
#   cleaned of formatting artifacts (duplicated "Abstract" prefixes, HTML tags)
#   inherited from upstream sources.

# Minimal prep: trim only, no cleaning yet
classification_input <- filtered_articles %>%
  select(doi, title, journal, abstract, year, volume, issue, pages, authors) %>%
  mutate(abstract = str_squish(abstract))

# Define junk abstract patterns BEFORE cleaning.
# Patterns where the entire abstract field contains non-abstract content.
# Sourced from OpenAlex upstream data quality issues (HAL metadata tags,
# funding acknowledgments misplaced in abstract field, rendering notices).
junk_abstract_pattern <- regex(
  paste(collapse = "|", c(
    # HAL / repository metadata
    "^international audience$",
    "^contains fulltext",
    "^item does not contain fulltext",
    "^no description supplied$",
    # Funding / sponsorship
    "^sponsorship:",
    "^this work was supported by",
    "^funding:",
    "^formulae display",
    # Supplementary material notices
    "^the online version contains supplementary material",
    # PDF / link prompts
    "^click on the pdf file",
    # Availability / status tags
    "^no abstract available",
    "^status: published",
    "^this is the final version",
    "^peer reviewed$",
    "^editorial reviewed$",
    # Clinical trial registration only
    "^clinicaltrials",
    "^the trial is registered",
    "^registered at clinicaltrials",
    "^us nih clinical trials",
    # Preregistration-only notices
    "^this study is not (pre-?)?registered",
    "^this study was not (pre-?)?registered",
    "^preregistered on osf",
    # URLs only
    "^http",
    # DOI repeated as abstract
    "^10\\.",
    # Single slash
    "^/$",
    # Test entry
    "^test$",
    # Commentary label
    "^commentary$",
    # Non-English metadata
    "^data de publicaci",
    # Congress metadata
    "international congress of psychology"
  )),
  ignore_case = TRUE
)

# Identify articles with no abstract (NA or empty)
articles_no_abstracts <- classification_input %>%
  filter(is.na(abstract) | abstract == "")

# Identify junk abstracts: short (<100 chars) or matching junk patterns
articles_junk_abstracts <- classification_input %>%
  filter(
    !is.na(abstract) &
      abstract != "" &
      (nchar(abstract) < 100 | str_detect(abstract, junk_abstract_pattern))
  )

# Print junk abstracts for review before proceeding
cat(nrow(articles_junk_abstracts), "junk abstracts detected (review before proceeding):\n\n")
for (i in seq_len(min(25, nrow(articles_junk_abstracts)))) {
  cat(sprintf("[%d] %s | %s\n    %s\n\n",
              i,
              articles_junk_abstracts$doi[i],
              articles_junk_abstracts$journal[i],
              str_trunc(articles_junk_abstracts$abstract[i], 120)))
}
if (interactive()) {   # View() only works in an interactive session such as RStudio
  articles_junk_abstracts %>%
    select(doi, title, journal, abstract) %>%
    View()
}

# Capture pre-cleaning state for articles that will need cleaning
needs_cleaning <- classification_input %>%
  filter(
    !is.na(abstract) &
      abstract != "" &
      nchar(abstract) >= 100 &
      !str_detect(abstract, junk_abstract_pattern)
  ) %>%
  filter(
    str_detect(abstract, "^Abstract\\s*Abstract") |
      str_detect(abstract, "^Abstract\\s+") |
      str_detect(abstract, "<[^>]+>") |
      str_detect(abstract, "&lt;|&gt;|&amp;|&#[0-9]+;")
  ) %>%
  select(doi, journal, abstract) %>%
  rename(abstract_before = abstract)

cat(sprintf("Articles requiring cleaning: %d\n", nrow(needs_cleaning)))

# Clean remaining abstracts.
# Applied only to abstracts that passed junk detection. Handles formatting
# artifacts from OpenAlex upstream sources without discarding real content.
# Deliberately conservative: only removes duplicated "Abstract" prefixes and
# HTML tags/entities. Keyword/disclosure/funding suffix removal was excluded
# as these strings can appear legitimately in abstract text.
articles_abstracts_for_classification <- classification_input %>%
  filter(
    !is.na(abstract) &
      abstract != "" &
      nchar(abstract) >= 100 &
      !str_detect(abstract, junk_abstract_pattern)
  ) %>%
  mutate(
    # Remove duplicated "Abstract" prefix artifacts
    abstract = str_replace(abstract, "^Abstract\\s*Abstract\\s*", ""),
    abstract = str_replace(abstract, "^Abstract\\s*", ""),
    # Strip HTML tags and decode common entities
    abstract = str_replace_all(abstract, "<[^>]+>", " "),
    abstract = str_replace_all(abstract, "&lt;", "<"),
    abstract = str_replace_all(abstract, "&gt;", ">"),
    abstract = str_replace_all(abstract, "&amp;", "&"),
    abstract = str_replace_all(abstract, "&#[0-9]+;", " "),
    abstract = str_squish(abstract)
  ) %>%
  mutate(article_id = row_number()) %>%
  select(article_id, everything())

# Before/after comparison for cleaned articles
cleaning_comparison <- needs_cleaning %>%
  left_join(
    articles_abstracts_for_classification %>%
      select(doi, abstract) %>%
      rename(abstract_after = abstract),
    by = "doi"
  )

cat(sprintf("Before/after comparison ready: %d rows\n\n", nrow(cleaning_comparison)))
if (interactive()) View(cleaning_comparison)   # interactive sessions only

# Reporting
cat(sprintf("Total articles:                %d\n",   nrow(classification_input)))
cat(sprintf("  With usable abstracts:       %d (%.1f%%)\n",
            nrow(articles_abstracts_for_classification),
            100 * nrow(articles_abstracts_for_classification) / nrow(classification_input)))
cat(sprintf("  Without abstracts (NA):      %d (%.1f%%)\n",
            nrow(articles_no_abstracts),
            100 * nrow(articles_no_abstracts) / nrow(classification_input)))
cat(sprintf("  Junk/short abstracts:        %d (%.1f%%)\n\n",
            nrow(articles_junk_abstracts),
            100 * nrow(articles_junk_abstracts) / nrow(classification_input)))

# Save
write_csv(classification_input,                  "articles_master.csv")
write_csv(articles_abstracts_for_classification, "articles_abstracts_for_classification.csv")
# write_csv(articles_no_abstracts,   "articles_no_abstracts.csv")   # uncomment if needed
# write_csv(articles_junk_abstracts, "articles_junk_abstracts.csv") # uncomment if needed
cat("Saved: articles_master.csv\n")
cat("Saved: articles_abstracts_for_classification.csv\n\n")

# Batch for Claude.
# The complete file exceeds Claude's upload size limit so it is split into
# numbered CSVs of CLASSIFICATION_BATCH_SIZE rows each.
n_classification_batches <- ceiling(nrow(articles_abstracts_for_classification) / CLASSIFICATION_BATCH_SIZE)

cat(sprintf("Batching into %d CSV(s) of up to %d rows...\n\n",
            n_classification_batches, CLASSIFICATION_BATCH_SIZE))

for (b in seq_len(n_classification_batches)) {
  row_start  <- (b - 1) * CLASSIFICATION_BATCH_SIZE + 1
  row_end    <- min(b * CLASSIFICATION_BATCH_SIZE, nrow(articles_abstracts_for_classification))
  batch_df   <- articles_abstracts_for_classification[row_start:row_end, ]
  batch_file <- sprintf("articles_for_classification_batch_%02d.csv", b)
  
  write_csv(batch_df, batch_file)
  cat(sprintf("  Saved: %-50s (%d articles, rows %d-%d)\n",
              batch_file, nrow(batch_df), row_start, row_end))
}

cat(sprintf("\nAll %d batch file(s) saved to:\n  %s\n\n", n_classification_batches, output_directory))

cat("Step 3c complete.\n\n")

cat("================================================================================\n")
cat("STEP 3 COMPLETE\n")
cat("================================================================================\n\n")


################################################################################
# STEP 3d: LLM ARTICLE CLASSIFICATION
#
# Classifies articles as empirical or non-empirical using an LLM.
# Articles are processed in batches due to Claude's file size limits.
#
# The script first checks whether all expected articles_classified_batch_XX.csv
# files already exist in the working directory (e.g. from a previous run).
# If all expected files are found, the script skips to Step 4.
#
# The LLM prompt is printed in any case. If files are missing the script stops
# with an error. In that case, use the prompt to run the classification in your
# LLM and save the resulting files in the working directory manually before
# re-running the script from Step 3d.
#
# IMPORTANT if using an LLM:
#   Use a NEW chat session for each batch.
#
# Sub-steps:
#   3d-i.  Check for existing classified batch files
#   3d-ii. Print LLM prompt for missing files (if any)
################################################################################

# --- 3d-i. Check for existing classified batch files --------------------------
cat("================================================================================\n")
cat("STEP 3d-i: CHECKING FOR EXISTING CLASSIFIED BATCH FILES\n")
cat("================================================================================\n\n")

expected_classified <- sprintf("articles_classified_batch_%02d.csv", seq_len(n_classification_batches))
missing_classified  <- expected_classified[
  !file.exists(file.path(output_directory, expected_classified))
]

if (length(missing_classified) == 0) {
  
  cat(sprintf("Found all %d classified batch file(s) - proceeding to Step 4.\n\n",
              n_classification_batches))
  cat("Step 3d-i complete.\n\n")
  
} else {
  
  # --- 3d-ii. Print LLM prompt for missing files ----------------------------
  cat("================================================================================\n")
  cat("STEP 3d-ii: LLM CLASSIFICATION REQUIRED FOR MISSING BATCHES\n")
  cat("================================================================================\n\n")
  
  # Prompt v7 - see "article-classification-prompt-changelog.txt"
  # for prompt decision overview.
  llm_article_prompt <- "
You are a research classifier. Use your best judgment to determine whether an academic paper presents empirical research. The classifications must be based on the abstract; inferring empirical work from the title or topic alone is insufficient.

Empirical papers involve original data collection or analysis, including quantitative work (experiments, RCTs, surveys, observational/longitudinal/cohort studies, secondary data analyses, psychometric/scale validation, simulations, meta-analyses), qualitative work (interviews, ethnography, autoethnography, testimonios, thematic analysis, grounded theory, IPA, discourse/narrative analysis, systematic case studies), or any mixed-methods combination.

Non-empirical work includes theoretical papers, literature reviews without quantitative synthesis, commentaries, editorials, and methodological proposals without data application.

Important distinctions:
- A paper that discusses or synthesizes empirical work is not itself empirical
- Narrative or scoping reviews are NOT empirical; reviews with a quantitative meta-analysis ARE
- Qualitative studies with systematic data collection ARE empirical even without statistics
- If an abstract explicitly labels the article type, treat that label as a strong signal
- Methodological or theoretical papers that describe or introduce an approach without reporting findings from applying it are NOT empirical

Hard overrides - classify as non-empirical if the abstract contains any of the following (exception: review terms paired with 'meta-analysis' should still be classified as empirical):
- 'systematic review' / 'scoping review' / 'narrative review' / 'meta-narrative review'
- 'commentary' / 'editorial' / 'response to' / 'letter to'
- 'conceptual paper' / 'theoretical paper' / 'theoretical overview'

Return a CSV named articles_classified_batch_XX.csv with two additional columns:
- is_empirical (true/false)
- empirical_reasoning (citing specific abstract evidence or key non-empirical phrases)
"
  
  cat(sprintf("%d / %d batch file(s) still need classification:\n",
              length(missing_classified), n_classification_batches))
  for (f in missing_classified) cat(sprintf("  MISSING: %s\n", f))
  cat("\n")
  cat("LLM PROMPT (copy and paste into Claude for each missing batch file):\n")
  cat(strrep("-", 80), "\n")
  cat(llm_article_prompt)
  cat(strrep("-", 80), "\n\n")
  cat(">>> MANUAL STEP: Classify the missing batch(es) above. Save results as\n")
  cat("    articles_classified_batch_XX.csv in your working directory:\n")
  cat(sprintf("    %s\n", output_directory))
  cat("    Then re-run the script from Step 3d.\n\n")
  
  stop("Stopping. Re-run after saving all classified batch files.")
}

cat("================================================================================\n")
cat("STEP 3d COMPLETE\n")
cat("================================================================================\n\n")


################################################################################
# STEP 4: MERGE CLASSIFICATIONS AND SAMPLE EMPIRICAL ARTICLES
#
# NOTE: If you manually classified CSVs via an LLM, make sure they are in
# your working directory before running this step.
#
# Sub-steps:
#   4a. Locate and validate classified batch files
#   4b. Merge all batches into a single file
#   4c. Sample empirical articles
#   4d. Summarize journal representation
################################################################################

# --- 4a. Locate and validate classified batch files ---------------------------
cat("================================================================================\n")
cat("STEP 4a: LOCATING AND VALIDATING CLASSIFIED BATCH FILES\n")
cat("================================================================================\n\n")

classified_batch_files <- sort(
  list.files(output_directory,
             pattern    = "^articles_classified_batch_\\d+\\.csv$",
             full.names = TRUE)
)

if (length(classified_batch_files) == 0) {
  stop(paste0(
    "No classified batch files found in:\n  ", output_directory, "\n\n",
    "Expected files matching: articles_classified_batch_XX.csv\n",
    "Complete Step 3d for all batches and try again."
  ))
}

cat(sprintf("Found %d classified batch file(s):\n", length(classified_batch_files)))
for (f in classified_batch_files) cat(sprintf("  %s\n", basename(f)))
cat("\n")

expected_batches <- sprintf("articles_classified_batch_%02d.csv", seq_len(n_classification_batches))
missing_batches  <- setdiff(expected_batches, basename(classified_batch_files))
if (length(missing_batches) > 0) {
  cat(sprintf("WARNING: %d expected batch file(s) not found:\n", length(missing_batches)))
  for (f in missing_batches) cat(sprintf("  MISSING: %s\n", f))
  cat("Proceeding with available batches - sample will be drawn from incomplete data.\n\n")
}

cat("Step 4a complete.\n\n")

# --- 4b. Merge classified batches ---------------------------------------------
cat("================================================================================\n")
cat("STEP 4b: MERGING CLASSIFIED BATCHES\n")
cat("================================================================================\n\n")

# All columns read as character first to avoid type-mismatch errors across
# batches; numeric columns and controlled-vocabulary fields coerced after merge.
classified_articles <- bind_rows(
  lapply(classified_batch_files, read_csv,
         show_col_types = FALSE,
         col_types      = cols(.default = "c"))
) %>%
  mutate(
    article_id   = as.integer(article_id),
    year         = as.integer(year),
    # Normalise is_empirical: LLM returns true/True/false/False inconsistently
    is_empirical = case_when(
      tolower(is_empirical) == "true"  ~ "Yes",
      tolower(is_empirical) == "false" ~ "No",
      TRUE                             ~ NA_character_
    )
  )

# Diagnostic: check row counts per batch against expected.
# Expected counts are derived from articles_abstracts_for_classification, which
# is the source of all batch files. The last batch may be smaller than
# CLASSIFICATION_BATCH_SIZE if the total does not divide evenly.
n_abstracts   <- nrow(articles_abstracts_for_classification)
expected_rows <- c(
  rep(CLASSIFICATION_BATCH_SIZE, n_classification_batches - 1),
  n_abstracts - (n_classification_batches - 1) * CLASSIFICATION_BATCH_SIZE
)

cat("Row count diagnostics (expected vs. actual per batch):\n")
for (i in seq_along(classified_batch_files)) {
  df   <- read_csv(classified_batch_files[i], show_col_types = FALSE)
  diff <- nrow(df) - expected_rows[i]
  cat(sprintf("  Batch %02d: expected %d, got %d (%+d)\n",
              i, expected_rows[i], nrow(df), diff))
}
cat("\n")

# Verify article_id range matches the abstracts-only subset.
# IDs should run 1 to nrow(articles_abstracts_for_classification) with no gaps.
id_min      <- min(classified_articles$article_id, na.rm = TRUE)
id_max      <- max(classified_articles$article_id, na.rm = TRUE)
id_expected <- nrow(articles_abstracts_for_classification)
cat(sprintf("Article ID range: %d to %d (expected 1 to %d)\n\n", id_min, id_max, id_expected))

# Diagnostic: confirm is_empirical values are clean after normalisation.
cat("is_empirical value counts:\n")
print(table(classified_articles$is_empirical, useNA = "always"))
cat("\n")

write_csv(classified_articles, "articles_classified_all.csv")
cat(sprintf("Saved: articles_classified_all.csv (%d total articles)\n\n",
            nrow(classified_articles)))

cat(sprintf("Empirical:     %d (%.1f%%)\n",
            sum(classified_articles$is_empirical == "Yes"),
            100 * mean(classified_articles$is_empirical == "Yes")))
cat(sprintf("Non-empirical: %d (%.1f%%)\n\n",
            sum(classified_articles$is_empirical == "No"),
            100 * mean(classified_articles$is_empirical == "No")))

cat("Step 4b complete.\n\n")

# --- 4c. Sample empirical articles --------------------------------------------
cat("================================================================================\n")
cat("STEP 4c: SAMPLING EMPIRICAL ARTICLES\n")
cat("================================================================================\n\n")

empirical_articles <- classified_articles %>%
  filter(is_empirical == "Yes", !is.na(doi) & doi != "")

cat(sprintf("Empirical articles with valid DOI: %d\n\n", nrow(empirical_articles)))

set.seed(RANDOM_SEED)
n_sample <- min(SAMPLE_SIZE, nrow(empirical_articles))

if (nrow(empirical_articles) < SAMPLE_SIZE) {
  cat(sprintf("WARNING: Only %d empirical articles available; sampling all.\n\n",
              nrow(empirical_articles)))
}

empirical_sample <- empirical_articles %>%
  filter(doi %in% sample(empirical_articles$doi, size = n_sample))

cat(sprintf("Sampled: %d articles (seed = %d)\n\n", nrow(empirical_sample), RANDOM_SEED))

write_csv(empirical_sample, "articles_empirical_sample.csv")
cat("Saved: articles_empirical_sample.csv\n\n")

cat("Step 4c complete.\n\n")

# --- 4d. Summarize journal representation -------------------------------------
cat("================================================================================\n")
cat("STEP 4d: SUMMARIZING JOURNAL REPRESENTATION\n")
cat("================================================================================\n\n")

# Use classification_input already in memory (same data as articles_master.csv)
journal_sample_summary <- classification_input %>%
  distinct(journal_title = journal) %>%
  filter(!is.na(journal_title)) %>%
  left_join(
    empirical_sample %>% count(journal, name = "n_articles"),
    by = c("journal_title" = "journal")
  ) %>%
  mutate(
    n_articles    = coalesce(n_articles, 0L),
    in_sample     = if_else(n_articles > 0, "Yes", "No"),
    pct_of_sample = round(100 * n_articles / nrow(empirical_sample), 2)
  ) %>%
  select(journal_title, in_sample, n_articles, pct_of_sample) %>%
  arrange(desc(n_articles), journal_title)

write_csv(journal_sample_summary, "journal_sample_summary.csv")
cat("Saved: journal_sample_summary.csv\n")
cat(sprintf("  Journals in master list:           %d\n", nrow(journal_sample_summary)))
cat(sprintf("  Journals with >=1 sampled article: %d\n", sum(journal_sample_summary$in_sample == "Yes")))
cat(sprintf("  Journals with 0 sampled articles:  %d\n", sum(journal_sample_summary$in_sample == "No")))
cat(sprintf("  Top journal: %s (%d articles, %.1f%%)\n\n",
            journal_sample_summary$journal_title[1],
            journal_sample_summary$n_articles[1],
            journal_sample_summary$pct_of_sample[1]))

cat("Step 4d complete.\n\n")

cat("================================================================================\n")
cat("STEP 4 COMPLETE\n")
cat("================================================================================\n\n")


################################################################################
# STEP 5: EXPORT EMPIRICAL SAMPLE TO RIS FOR ZOTERO
#
# Sub-steps:
#   5a. Define RIS record builder
#   5b. Write batched RIS files
################################################################################

# --- 5a. Define RIS record builder --------------------------------------------
cat("================================================================================\n")
cat("STEP 5a: DEFINING RIS RECORD BUILDER\n")
cat("================================================================================\n\n")

# Clean titles and authors for RIS export
empirical_sample <- empirical_sample %>%
  mutate(
    title   = str_remove_all(title, "<[^>]+>"),
    title   = str_squish(title),
    authors = str_remove_all(authors, "[^\x01-\xFF]"),
    authors = str_squish(authors)
  )

write_csv(empirical_sample, "articles_empirical_sample.csv")
cat("Saved: articles_empirical_sample.csv\n\n")

# Build one RIS record from a single data frame row.
# Uses open = "w" with encoding = "UTF-8" (not binary mode) to avoid
# character corruption on Windows.
create_ris <- function(row) {
  ris <- "TY  - JOUR\n"
  
  if ("authors" %in% names(row) && !is.na(row$authors) && row$authors != "")
    ris <- paste0(ris, "AU  - ", row$authors, "\n")
  
  if (!is.na(row$title)) {
    title_clean <- row$title
    title_clean <- gsub("&quot;", "", title_clean)
    title_clean <- gsub("<scp>",  "", title_clean)
    title_clean <- gsub("</scp>", "", title_clean)
    title_clean <- gsub('"',      "", title_clean)
    ris <- paste0(ris, "TI  - ", title_clean, "\n")
  }
  
  if (!is.na(row$journal)) {
    ris <- paste0(ris, "JO  - ", row$journal, "\n")
    ris <- paste0(ris, "T2  - ", row$journal, "\n")
  }
  
  if (!is.na(row$year))                                                    ris <- paste0(ris, "PY  - ", row$year,   "\n")
  if ("volume" %in% names(row) && !is.na(row$volume) && row$volume != "") ris <- paste0(ris, "VL  - ", row$volume, "\n")
  if ("issue"  %in% names(row) && !is.na(row$issue)  && row$issue  != "") ris <- paste0(ris, "IS  - ", row$issue,  "\n")
  if ("pages"  %in% names(row) && !is.na(row$pages)  && row$pages  != "") ris <- paste0(ris, "SP  - ", row$pages,  "\n")
  
  if (!is.na(row$doi)) {
    doi_clean <- str_replace(row$doi, "https://doi.org/", "")
    ris <- paste0(ris, "DO  - ", doi_clean, "\n")
    ris <- paste0(ris, "UR  - ", row$doi,   "\n")
  }
  
  ris <- paste0(ris, "DB  - OpenAlex\n")
  ris <- paste0(ris, "ER  - \n\n")
  ris
}

cat("RIS record builder defined.\n\n")
cat("Step 5a complete.\n\n")

# --- 5b. Write batched RIS files ----------------------------------------------
cat("================================================================================\n")
cat("STEP 5b: WRITING BATCHED RIS FILES\n")
cat("================================================================================\n\n")

# RIS output is split into batches of RIS_BATCH_SIZE records.
# Some Zotero versions stall or error on very large single RIS files; smaller
# batches import reliably and can be imported sequentially into the same library.
n_ris_batches <- ceiling(nrow(empirical_sample) / RIS_BATCH_SIZE)

cat(sprintf("Splitting %d articles into %d RIS file(s) of up to %d records...\n\n",
            nrow(empirical_sample), n_ris_batches, RIS_BATCH_SIZE))

for (rb in seq_len(n_ris_batches)) {
  row_start <- (rb - 1) * RIS_BATCH_SIZE + 1
  row_end   <- min(rb * RIS_BATCH_SIZE, nrow(empirical_sample))
  batch_df  <- empirical_sample[row_start:row_end, ]
  
  ris_file_path <- sprintf("psychology_2023_empirical_for_zotero_part_%02d.ris", rb)
  ris_con       <- file(ris_file_path, open = "w", encoding = "UTF-8")
  
  for (i in seq_len(nrow(batch_df))) {
    if (i %% 500 == 0)
      cat(sprintf("  [Part %02d] Processed %d / %d records...\n", rb, i, nrow(batch_df)))
    cat(create_ris(batch_df[i, ]), file = ris_con)
  }
  close(ris_con)
  
  cat(sprintf("  Saved: %-55s (%d records, rows %d-%d)\n",
              ris_file_path, nrow(batch_df), row_start, row_end))
}

cat(sprintf("\n%d RIS file(s) created. Import each into Zotero separately.\n\n",
            n_ris_batches))

cat("Step 5b complete.\n\n")

cat("================================================================================\n")
cat("STEP 5 COMPLETE\n")
cat("================================================================================\n\n")


################################################################################
# STEP 6: WRITE SUMMARY REPORT
#
# Sub-steps:
#   6a. Write classification_summary.txt
################################################################################

# --- 6a. Write classification_summary.txt -------------------------------------
cat("================================================================================\n")
cat("STEP 6a: WRITING SUMMARY REPORT\n")
cat("================================================================================\n\n")

sink("classification_summary.txt")

cat("PSYCHOLOGY ARTICLES 2023 - CLASSIFICATION AND SAMPLING SUMMARY\n")
cat("===============================================================\n\n")
cat(sprintf("Generated: %s\n\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

cat("SOURCE DATA\n")
cat("-----------\n")
cat("Database:       OpenAlex (https://openalex.org)\n")
cat(sprintf("Year:           %d\n", PUBLICATION_YEAR))
cat(sprintf("Document type:  %s\n", DOCUMENT_TYPE))
cat(sprintf("Language:       %s\n", LANGUAGE))
cat(sprintf("Journals (ISSNs queried): %d\n\n", length(issns)))

cat("JOURNAL FILTERING (NPI DATABASE)\n")
cat("---------------------------------\n")
cat(sprintf("Total NPI entries:                   %d\n", nrow(corrected_full_db)))
cat(sprintf("Psychology journals (English):        %d\n", nrow(psych_db)))
cat(sprintf("Included after keyword/level filter:  %d\n", nrow(filtered_psych_db)))
cat(sprintf("Excluded by keyword/level filter:     %d\n", nrow(excluded_psych_db)))
cat(sprintf("Excluded by LLM journal check:        %d\n", length(excluded_by_classification)))
cat(sprintf("Journals sent to OpenAlex:            %d\n\n", nrow(journals_for_openalex)))

cat("ARTICLE DOWNLOAD\n")
cat("----------------\n")
cat(sprintf("Total articles downloaded:   %d\n", total_fetched))
cat(sprintf("After pre-filtering:         %d\n", nrow(filtered_articles)))
cat(sprintf("Removed (errata, etc.):      %d\n\n", nrow(excluded_articles)))

cat("CLASSIFICATION\n")
cat("--------------\n")
cat(sprintf("Total classified:            %d\n", nrow(classified_articles)))
cat(sprintf("Empirical:                   %d (%.1f%%)\n",
            sum(classified_articles$is_empirical == "Yes"),
            100 * mean(classified_articles$is_empirical == "Yes")))
cat(sprintf("Non-empirical:               %d (%.1f%%)\n\n",
            sum(classified_articles$is_empirical == "No"),
            100 * mean(classified_articles$is_empirical == "No")))

cat("RANDOM SAMPLE\n")
cat("-------------\n")
cat(sprintf("Empirical articles with DOI: %d\n", nrow(empirical_articles)))
cat(sprintf("Sample size requested:       %d\n", SAMPLE_SIZE))
cat(sprintf("Sample size achieved:        %d\n", nrow(empirical_sample)))
cat(sprintf("Random seed:                 %d\n\n", RANDOM_SEED))

cat("OUTPUT FILES\n")
cat("------------\n")
cat("1.  NPI_Scientific_Journals_2023.csv\n")
cat("2.  psych_db.csv\n")
cat("3.  excluded_psych_db.csv\n")
cat("4.  filtered_psych_db.csv\n")
cat("5.  journals_for_openalex.csv\n")
cat("6.  articles_master.csv\n")
cat("7.  articles_excluded_by_title_keyword.csv\n")
cat(sprintf("8.  articles_for_classification_batch_01..%02d.csv\n", n_classification_batches))
cat(sprintf("9.  articles_classified_batch_01..%02d.csv\n",         n_classification_batches))
cat("10. articles_classified_all.csv\n")
cat("11. articles_empirical_sample.csv\n")
cat(sprintf("12. psychology_2023_empirical_for_zotero_part_01..%02d.ris\n", n_ris_batches))
cat("13. journal_sample_summary.csv\n")
cat("14. classification_summary.txt\n\n")

cat("R SESSION INFO\n")
cat("--------------\n")
cat(sprintf("R version: %s\n", R.version.string))
cat(sprintf("Platform:  %s\n", R.version$platform))

sink()

cat("Saved: classification_summary.txt\n\n")

cat("Step 6a complete.\n\n")

cat("================================================================================\n")
cat("STEP 6 COMPLETE\n")
cat("================================================================================\n\n")


################################################################################
# PIPELINE COMPLETE
################################################################################