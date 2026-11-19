# =============================================================================
# MultiTagger vs Claude: empirical / non-empirical classification comparison
# Pilot 2 (2023) article pool
# =============================================================================
#
# WHAT THIS SCRIPT DOES
#   In the Pilot 2 database, articles were classified as empirical or
#   non-empirical by Claude (an LLM) from their abstracts. This script
#   classifies the same articles with MultiTagger V2, a publication-type tagger
#   trained on biomedical (MEDLINE) indexing, and compares the two. The aim is
#   to judge whether MultiTagger could replace the LLM step.
#
#   MultiTagger does not say "empirical" or "non-empirical". It gives each
#   article zero or more of 59 publication-type labels (e.g. "cohort_study",
#   "editorial"). The script therefore:
#     1. sorts the 59 labels into four groups                   (Section 2)
#     2. turns each article's labels into an empirical /
#        non-empirical call with a decision rule                (Section 4)
#     3. compares those calls with Claude's                     (Sections 6-8)
#
# SECTIONS
#   1. Settings and data
#   2. MultiTagger labels and label groups
#   3. MultiTagger: how often each label was assigned
#   4. MultiTagger: decision rules (empirical / non-empirical / no opinion)
#   5. Claude: summary
#   6. Agreement between MultiTagger and Claude (default rule)
#   7. Sensitivity: agreement under the alternative decision rules
#   8. Articles MultiTagger did not label ("no opinion")
#   9. Save outputs
#
# INPUT FILES (in the working directory)
#   articles_classified_all.csv   Claude's classification of the Pilot 2 pool:
#                                 article_id, title, abstract, ...,
#                                 is_empirical (Yes / No), empirical_reasoning.
#                                 WHERE IT COMES FROM: written by the Pilot 2
#                                 pipeline, pilot2_db_curation_v5_replicable.R,
#                                 after its title, abstract and LLM steps
#                                 (Step 3d).
#   multitagger_predictions.csv   MultiTagger V2 output for the same articles.
#                                 Columns used: "pmid" (holds the Pilot 2
#                                 article_id, not a PubMed ID) and
#                                 "predictions" (59 values of 0/1, one per label,
#                                 in the order of Section 2).
#                                 WHERE IT COMES FROM: made outside R, with the
#                                 MultiTagger scripts and their README:
#                                   1. articles_abstracts_for_classification.csv,
#                                      written by the curation script in Step 3c,
#                                      is reformatted to the MultiTagger layout
#                                      (article_id renamed to pmid; see the
#                                      MultiTagger README, "Input") and saved
#                                      under the same name.
#                                   2. run_multitagger_pilot2db.py runs the model
#                                      on that file and writes
#                                      multitagger_predictions.csv.
#                                   3. Copy it into this script's working folder.
#
#   Neither file is shared publicly: both contain full abstracts, which are
#   usually copyrighted by the publishers. Regenerate them as described above.
#
# KNOWN ISSUE IN THE MULTITAGGER INPUT
#   The 0/1 values in "predictions" were made with an earlier MultiTagger script
#   that matched 47 of the 59 labels to the wrong cut-off (see the MultiTagger
#   README, "Earlier script version: the Pilot 2 predictions quirks"). The
#   probabilities are correct. This script uses the stored 0/1 values as they
#   are, so its results reflect that error. Re-applying the correct cut-offs
#   changes at least one label for 3,658 of the 24,911 articles; overall
#   agreement under rule A moves from 87.6% to 87.8%, and the share of
#   articles with no label from 31.2% to 30.2%.
#
# OUTPUT FILES
#   multitagger_claude_output.txt  All results (nothing prints to the console)
#   articles_with_agreement.csv    One row per article: Claude's call, the 59
#                                  MultiTagger label columns, MultiTagger's call
#                                  under each rule, agreement category, Claude
#                                  ambiguity flag and case type
#   mt_no_opinion_articles.csv     The articles MultiTagger gave no label
#
# REFERENCES
#   MultiTagger V1 - label definitions and the "Clinically related" (Table 1)
#   vs "Other publication types" (Table 2) grouping:
#     Cohen AM, Schneider J, Fu Y, McDonagh MS, Das P, Holt AW, Smalheiser NR
#     (2021). Fifty ways to tag your pubtypes: Multi-Tagger, a set of
#     probabilistic publication type and study design taggers to support
#     biomedical indexing and evidence-based medicine. medRxiv.
#     https://doi.org/10.1101/2021.07.13.21260468
#   MultiTagger V2 - the model that produced the predictions (PubMedBERT,
#   multi-label, trained jointly across all labels; the pretrained release
#   linked from the AMIA folder of https://github.com/ScienceNLP-Lab/MultiTagger-v2):
#     Menke JD, Kilicoglu H, Smalheiser NR (2024). Publication type tagging
#     using transformer models and multi-label classification. AMIA Annual
#     Symposium Proceedings. https://pubmed.ncbi.nlm.nih.gov/40417522/
#
# CONTACT:     Mary Beth Neff (marybethneff@gmail.com)
# INSTITUTION: University of Oslo, Norway
# DATE:        2026-05-15 (original); 2026-11-18 (tidied for outside readers)
# VERSION:     2 (tidied; logic and results unchanged from version 1)
#
# LLM TRANSPARENCY NOTE:
#   This script was developed with Claude (Anthropic, Sonnet 5.5); the
#   tidied version with Claude Opus 5.5. The script itself makes no LLM calls. One of its
#   inputs (articles_classified_all.csv) holds the LLM classification of
#   articles from the Pilot 2 pipeline (Step 3d), which is what MultiTagger
#   is compared against.
#
# DEPENDENCIES:
#   R >= 4.1.0; tidyverse (uses readr, dplyr, tidyr, stringr, purrr, tibble)
# =============================================================================

library(tidyverse)


# =============================================================================
# 1. SETTINGS AND DATA
# =============================================================================

# SET THIS: the folder holding the two input files. All output files are
# written here too. Example: WORKING_DIRECTORY <- "C:/path/to/your/folder"
# Leave as NA to use the current working directory (getwd()).
WORKING_DIRECTORY <- NA

CLAUDE_FILE          <- "articles_classified_all.csv"
MT_FILE              <- "multitagger_predictions.csv"
LOG_FILE             <- "multitagger_claude_output.txt"
RANDOM_SEED          <- 123  # only affects which example titles are shown
N_EXAMPLES_PER_LABEL <- 2

# Claude's reasoning text is searched for these phrases to flag calls where
# Claude was uncertain. In practice the flag mostly marks "No" calls made
# because the abstract showed no empirical signals, rather than calls based on
# positive evidence of non-empirical content.
CLAUDE_AMBIGUITY_PATTERN <-
  "no clear|ambiguous|unclear|insufficient|cannot|not enough|no empirical|no indicator"

# --- Working folder and input checks (shown in the console) ------------------
if (!is.na(WORKING_DIRECTORY)) {
  if (!dir.exists(WORKING_DIRECTORY))
    stop("WORKING_DIRECTORY not found: ", WORKING_DIRECTORY,
         "\nEdit WORKING_DIRECTORY at the top of Section 1.")
  setwd(WORKING_DIRECTORY)
}
missing_inputs <- c(CLAUDE_FILE, MT_FILE)[!file.exists(c(CLAUDE_FILE, MT_FILE))]
if (length(missing_inputs) > 0)
  stop("Input file(s) not found in ", getwd(), ":\n  ",
       paste(missing_inputs, collapse = "\n  "))

# --- Results log ---------------------------------------------------------------
# Results (everything printed with cat() / print()) go to LOG_FILE, not the
# console. Warnings and errors still appear in the console, so a problem is
# never hidden inside the log. To also see results in the console, change
# split = FALSE to split = TRUE.
while (sink.number() > 0) sink()   # close any log left open by an earlier failed run
log_path <- file.path(getwd(), LOG_FILE)
cat("Writing results to:", log_path, "\n")
log_con <- file(log_path, open = "wt")
sink(log_con, type = "output", split = FALSE)

# --- Helpers -----------------------------------------------------------------
section <- function(title) {
  cat("\n", strrep("=", 78), "\n", title, "\n", strrep("=", 78), "\n\n", sep = "")
}
subsection <- function(title) cat("\n--", title, strrep("-", max(3, 74 - nchar(title))), "\n")
pct <- function(n, total) round(100 * n / total, 1)

# --- Load --------------------------------------------------------------------
claude <- read_csv(CLAUDE_FILE, show_col_types = FALSE, progress = FALSE)
mt_raw <- read_csv(MT_FILE,     show_col_types = FALSE, progress = FALSE)

cat("MultiTagger vs Claude comparison - results log\n")
cat("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Folder:   ", getwd(), "\n")


# =============================================================================
# 2. MULTITAGGER LABELS AND LABEL GROUPS
# =============================================================================
#
# MultiTagger's 59 labels, in the order of its prediction array, with:
#   paper_group  how the V1 paper (Cohen et al., 2021) groups the label:
#                "Clinical" = Table 1, clinically related study designs, which
#                             the paper treats as indexing research
#                "Other"    = Table 2, other publication types (editorials,
#                             letters, news, but also interviews, conferences)
#                "Not in paper" = veterinary labels and clinical_trial_protocol
#   our_group    our assessment for PSYCHOLOGY, one of four groups:
#
#   Empirical (30 labels)  Study designs and study types. Mostly "Clinical" in
#                          the paper; also two "Other" labels that describe
#                          study types (predictive_value_of_tests,
#                          reproducibility_of_results).
#   Group 1   (8 labels)   Strong empirical candidates for psychology: formally
#                          non-empirical in biomedical indexing, but often
#                          attached to primary research in psychology (e.g.
#                          interview-based qualitative studies, conference
#                          abstracts reporting studies, meta-analyses).
#   Group 2   (6 labels)   Grey zone: can be empirical or not (a review may or
#                          may not synthesise data; a historical article may or
#                          may not analyse original data).
#   Group 3   (15 labels)  Non-empirical: notices, opinion and commentary
#                          formats, and other non-research document types.
#
# NOTE ON MODEL VERSIONS: definitions and the paper's grouping come from V1;
# the predictions come from V2. In V1, some labels had no working model
# (retraction_of_publication, newspaper_article, scientific_integrity_review
# and published_erratum had too few training examples; clinical_trial had a
# training-query bug) and the veterinary labels were not modelled. V2 models
# these, so some of them are assigned in this dataset.

EMP <- "Empirical"
G1  <- "Group 1: strong empirical candidate"
G2  <- "Group 2: grey zone"
G3  <- "Group 3: non-empirical"
GROUPS <- c(EMP, G1, G2, G3)

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

label_order          <- label_info$label
label_group          <- setNames(label_info$our_group, label_info$label)
labels_in            <- function(group) label_info$label[label_info$our_group == group]
empirical_labels     <- labels_in(EMP)
group1_labels        <- labels_in(G1)
group2_labels        <- labels_in(G2)
group3_labels        <- labels_in(G3)

stopifnot(length(label_order) == 59, !anyDuplicated(label_order),
          lengths(list(empirical_labels, group1_labels, group2_labels, group3_labels)) ==
            c(30, 8, 6, 15))

# --- Parse MultiTagger predictions into one 0/1 column per label --------------
pred_values <- mt_raw$predictions |> str_extract_all("[0-9]+") |> lapply(as.integer)
if (any(lengths(pred_values) != length(label_order)))
  stop("Some prediction arrays do not have ", length(label_order), " values.")

label_matrix <- do.call(rbind, pred_values)
colnames(label_matrix) <- label_order
fired <- lapply(seq_len(nrow(label_matrix)), function(i) label_order[label_matrix[i, ] == 1])

mt <- as_tibble(label_matrix) |>
  mutate(
    article_id  = mt_raw$pmid,                 # "pmid" holds the Pilot 2 article_id
    mt_all_zero = rowSums(label_matrix) == 0,  # TRUE = no label assigned ("no opinion")
    mt_labels   = map_chr(fired, ~ if (length(.x)) paste(.x, collapse = "; ") else "(no labels)"),
    mt_groups   = map_chr(fired, ~ if (length(.x))
      paste(intersect(GROUPS, label_group[.x]), collapse = "; ") else "No opinion"),
    .before = 1
  )

section("1. DATA CHECK")
cat(sprintf("Claude articles:                 %d\n", nrow(claude)))
cat(sprintf("MultiTagger articles:            %d\n", nrow(mt)))
cat(sprintf("Claude articles found in MT:     %d\n", sum(claude$article_id %in% mt$article_id)))
cat(sprintf("Labels per prediction array:     %d\n", length(label_order)))
cat(sprintf("Labels assigned in total:        %d\n", sum(label_matrix)))

section("2. LABEL GROUPS")
label_info |> count(our_group, paper_group) |> print()


# =============================================================================
# 3. MULTITAGGER: HOW OFTEN EACH LABEL WAS ASSIGNED
# =============================================================================
# Lists every label with its count and a few random example titles, so the
# group each label is in can be checked by eye.

set.seed(RANDOM_SEED)
mt_titles <- mt |> left_join(select(claude, article_id, title), by = "article_id")

section("3. MULTITAGGER: LABEL COUNTS")

subsection("3a. No opinion (no label assigned)")
cat(sprintf("%d of %d articles (%.1f%%)\n", sum(mt$mt_all_zero), nrow(mt),
            100 * mean(mt$mt_all_zero)))
cat("\nExample titles:\n")
mt_titles |> filter(mt_all_zero, !is.na(title)) |> slice_sample(n = 5) |> pull(title) |>
  iwalk(~ cat(sprintf("  %d. %s\n", .y, .x)))

label_counts <- label_info |>
  mutate(count = as.integer(colSums(label_matrix)[label]),
         pct   = round(100 * count / nrow(mt), 2)) |>
  arrange(desc(count))

subsection("3b. Every label, most frequent first, with example titles")
for (i in seq_len(nrow(label_counts))) {
  lbl <- label_counts$label[i]
  cat(sprintf("\n[%s]  n = %d (%.2f%%)  |  %s\n", lbl, label_counts$count[i],
              label_counts$pct[i], label_counts$our_group[i]))
  if (label_counts$count[i] == 0) {
    cat("  (not assigned to any article)\n")
    next
  }
  mt_titles |> filter(.data[[lbl]] == 1, !is.na(title)) |>
    slice_sample(n = N_EXAMPLES_PER_LABEL) |> pull(title) |>
    walk(~ cat("  -", .x, "\n"))
}

subsection("3c. Label counts by group")
for (g in GROUPS) {
  cat("\n", g, ":\n", sep = "")
  label_counts |> filter(our_group == g) |> select(label, count, pct) |> print(n = Inf)
}

subsection("3d. Articles with at least one label from each group (groups overlap)")
n_with_any <- function(labels) sum(rowSums(label_matrix[, labels, drop = FALSE]) > 0)
tibble(group = c(GROUPS, "No opinion"),
       n     = c(map_int(list(empirical_labels, group1_labels, group2_labels, group3_labels),
                         n_with_any),
                 sum(mt$mt_all_zero))) |>
  mutate(pct = pct(n, nrow(mt))) |>
  print()


# =============================================================================
# 4. MULTITAGGER: DECISION RULES
# =============================================================================
# An article is NON-EMPIRICAL if any of its labels is in the rule's
# non-empirical set, EMPIRICAL if it has labels but none in that set, and
# NO OPINION (NA) if it has no labels at all.
#
#   Rule  Counted as empirical          Counted as non-empirical
#   A     Empirical + Group 1           Groups 2 + 3
#   B     Empirical + Group 2           Groups 1 + 3
#   C     Empirical + Groups 1 + 2      Group 3 only           <- default
#
# The default rule C is used for the main comparison (Section 6); A and B are
# sensitivity checks (Section 7).

non_empirical_sets <- list(
  A = c(group2_labels, group3_labels),
  B = c(group1_labels, group3_labels),
  C = group3_labels
)
DEFAULT_RULE <- "C"

classify_mt <- function(non_empirical_labels) {
  has_non_empirical <- rowSums(label_matrix[, non_empirical_labels, drop = FALSE]) > 0
  if_else(mt$mt_all_zero, NA, !has_non_empirical)
}
for (r in names(non_empirical_sets))
  mt[[paste0("mt_empirical_", r)]] <- classify_mt(non_empirical_sets[[r]])
mt$mt_empirical <- mt[[paste0("mt_empirical_", DEFAULT_RULE)]]

section("4. MULTITAGGER: CALLS UNDER EACH DECISION RULE")
map_dfr(names(non_empirical_sets), function(r) {
  x <- mt[[paste0("mt_empirical_", r)]]
  tibble(rule = r, empirical = sum(x %in% TRUE), non_empirical = sum(x %in% FALSE),
         no_opinion = sum(is.na(x)), default = r == DEFAULT_RULE)
}) |> print()


# =============================================================================
# 5. CLAUDE: SUMMARY
# =============================================================================

claude <- claude |>
  mutate(claude_ambiguous = str_detect(tolower(empirical_reasoning), CLAUDE_AMBIGUITY_PATTERN))

section("5. CLAUDE")
subsection("5a. Empirical calls")
claude |> count(is_empirical) |> mutate(pct = pct(n, sum(n))) |> print()
subsection("5b. Reasoning flagged as ambiguous")
claude |> count(claude_ambiguous) |> mutate(pct = pct(n, sum(n))) |> print()


# =============================================================================
# 6. AGREEMENT BETWEEN MULTITAGGER AND CLAUDE (default rule)
# =============================================================================

agreement_category <- function(claude_call, mt_call) {
  case_when(
    is.na(mt_call)                    ~ "MultiTagger: No opinion",
    claude_call == "Yes" &  mt_call   ~ "Both: Empirical",
    claude_call == "No"  & !mt_call   ~ "Both: Not Empirical",
    claude_call == "Yes" & !mt_call   ~ "Only Claude: Empirical",
    claude_call == "No"  &  mt_call   ~ "Only MultiTagger: Empirical"
  )
}

# Case types single out the informative disagreements:
#   True disagreement  MultiTagger gave labels AND Claude was not ambiguous,
#                      yet the two calls differ
#   Both uncertain     MultiTagger gave no labels AND Claude was ambiguous
combined <- claude |>
  left_join(mt, by = "article_id") |>
  mutate(
    agreement = agreement_category(is_empirical, mt_empirical),
    case_type = case_when(
      !mt_all_zero & !claude_ambiguous & agreement == "Only Claude: Empirical" ~
        "True disagreement: Claude empirical, MT not",
      !mt_all_zero & !claude_ambiguous & agreement == "Only MultiTagger: Empirical" ~
        "True disagreement: MT empirical, Claude not",
      mt_all_zero & claude_ambiguous ~ "Both uncertain",
      TRUE ~ "Other"
    )
  )

section(sprintf("6. AGREEMENT (rule %s)", DEFAULT_RULE))

subsection("6a. All articles")
combined |> count(agreement) |> mutate(pct = pct(n, sum(n))) |> print()

subsection("6b. Articles MultiTagger labelled")
with_opinion <- combined |> filter(!mt_all_zero)
with_opinion |> count(agreement) |> mutate(pct = pct(n, sum(n))) |> print()
cat(sprintf("Overall agreement: %.1f%%\n",
            100 * mean(with_opinion$agreement %in% c("Both: Empirical", "Both: Not Empirical"))))

subsection("6c. Claude ambiguity, by whether MultiTagger gave labels")
combined |>
  mutate(mt_status     = if_else(mt_all_zero, "MT: No opinion", "MT: Had opinion"),
         claude_status = if_else(claude_ambiguous, "Claude: Ambiguous", "Claude: Confident")) |>
  count(mt_status, claude_status) |>
  group_by(mt_status) |> mutate(pct = pct(n, sum(n))) |> ungroup() |>
  print()

subsection("6d. Case types")
combined |> filter(case_type != "Other") |> count(case_type) |>
  mutate(pct_of_all_articles = pct(n, nrow(combined))) |> print()

subsection("6e. Example titles per agreement category")
set.seed(RANDOM_SEED)
for (category in c("Both: Empirical", "Both: Not Empirical", "Only Claude: Empirical",
                   "Only MultiTagger: Empirical", "MultiTagger: No opinion")) {
  n_show <- if (category == "MultiTagger: No opinion") 10 else 2
  cat("\n", category, ":\n", sep = "")
  combined |> filter(agreement == category) |>
    select(title, mt_groups, mt_labels, is_empirical, empirical_reasoning) |>
    slice_sample(n = n_show) |>
    print(width = 160)
}


# =============================================================================
# 7. SENSITIVITY: AGREEMENT UNDER THE ALTERNATIVE DECISION RULES
# =============================================================================
# Shows how much the choice of rule (i.e. where Groups 1 and 2 go) changes
# agreement. Only articles MultiTagger labelled are included. "Claude agrees"
# percentages are within MultiTagger's own call.

rule_descriptions <- c(
  A = "Empirical + Group 1 = empirical; Groups 2+3 = non-empirical",
  B = "Empirical + Group 2 = empirical; Groups 1+3 = non-empirical",
  C = "Empirical + Groups 1+2 = empirical; Group 3 = non-empirical"
)

agreement_by_rule <- function(r) {
  combined |>
    mutate(mt_call = .data[[paste0("mt_empirical_", r)]]) |>
    filter(!is.na(mt_call)) |>
    mutate(agreement = agreement_category(is_empirical, mt_call))
}

section("7. SENSITIVITY: AGREEMENT UNDER EACH DECISION RULE")

subsection("7a. Summary")
map_dfr(names(rule_descriptions), function(r) {
  d <- agreement_by_rule(r)
  tibble(
    rule                     = r,
    mt_empirical_n           = sum(d$mt_call),
    claude_agrees_pct        = pct(sum(d$agreement == "Both: Empirical"), sum(d$mt_call)),
    mt_non_empirical_n       = sum(!d$mt_call),
    claude_agrees_pct_nonemp = pct(sum(d$agreement == "Both: Not Empirical"), sum(!d$mt_call)),
    overall_agreement_pct    = pct(sum(d$agreement %in% c("Both: Empirical", "Both: Not Empirical")),
                                   nrow(d))
  )
}) |> print(width = 160)

subsection("7b. Full breakdown per rule (pct = % within MultiTagger's call)")
for (r in names(rule_descriptions)) {
  cat(sprintf("\nRule %s - %s%s:\n", r, rule_descriptions[[r]],
              if (r == DEFAULT_RULE) " (default)" else ""))
  agreement_by_rule(r) |>
    count(mt_call, agreement) |>
    group_by(mt_call) |> mutate(pct = pct(n, sum(n))) |> ungroup() |>
    select(agreement, n, pct) |>
    print()
}


# =============================================================================
# 8. ARTICLES MULTITAGGER DID NOT LABEL ("NO OPINION")
# =============================================================================
# These articles would drop out of a MultiTagger-based pipeline, so this
# section describes them from Claude's side.

mt_no_opinion <- combined |> filter(mt_all_zero)

section("8. MULTITAGGER NO-OPINION ARTICLES")
cat(sprintf("No-opinion articles: %d of %d (%.1f%%)\n", nrow(mt_no_opinion), nrow(combined),
            100 * nrow(mt_no_opinion) / nrow(combined)))

subsection("8a. Claude's call")
mt_no_opinion |> count(is_empirical) |> mutate(pct = pct(n, sum(n))) |> print()

subsection("8b. Claude ambiguity within each call")
mt_no_opinion |>
  count(is_empirical, claude_ambiguous) |>
  group_by(is_empirical) |> mutate(pct_within_call = pct(n, sum(n))) |> ungroup() |>
  print()


# =============================================================================
# 9. SAVE OUTPUTS
# =============================================================================

write_csv(mt_no_opinion, "mt_no_opinion_articles.csv")
write_csv(combined,      "articles_with_agreement.csv")

section("9. SAVED FILES")
cat("mt_no_opinion_articles.csv\narticles_with_agreement.csv\n")

sink(type = "output")
close(log_con)
cat("Done. Results log:  ", log_path, "\n")
cat("Data files saved in:", getwd(), "\n")