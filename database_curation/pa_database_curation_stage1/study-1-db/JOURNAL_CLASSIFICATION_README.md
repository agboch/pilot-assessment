# Journal Classification README (Study 1, 2025)

This document describes how `2025journals_llm_classified_final.csv` was created and how to recreate or update it. The file is required by Step 1f of the Study 1 script, `pilot-assessment_2025-db-curation_v2_public.R`; the script stops at Step 1e if it is missing.

Study 1 builds on the Pilot 2 journal classification (`2023journals_llm_classified_final.csv`, made as described in the Pilot 2 `JOURNAL_CLASSIFICATION_README.md`). Journals still on the list keep their Pilot 2 classification; only journals that are new to the list are classified again.

---

## Overview

The goal is to identify psychology journals that do **not** primarily publish original empirical research, so they can be excluded from the OpenAlex download. The classification combines an LLM step with manual review.

---

## File: `2025journals_llm_classified_final.csv`

### Column reference

| Column | Description |
|---|---|
| `journal_id` | NPI journal identifier |
| `Online ISSN` | Journal ISSN (used as the join key in the R script) |
| `Original Title` | Journal title as listed in the NPI register |
| `International Title` | Standardised international title |
| `Level 2023` | NPI level column carried over from the Pilot 2 file (the script filters on the current level year itself, in Step 1a) |
| `publishes_original_research` | LLM classification: `yes`, `mixed`, or `no` |
| `confidence` | LLM confidence: `high`, `medium`, or `low` |
| `manual_review` | `yes` if excluded through manual review; blank otherwise |
| `final_empirical_no` | `yes` if the journal is excluded (see logic below); may be left blank for newly classified journals |
| `classification_source` | `carried over from pilot-2` or `classified for study-1-db` |

### Exclusion logic (Step 1f)

A journal is excluded if `final_empirical_no = yes`. For journals classified in this run, the script fills a blank `final_empirical_no` with the Pilot 2 rule:

- the LLM classified it as `publishes_original_research = no` **and** `confidence` is `medium` or `high`, or
- `manual_review = yes` (set `final_empirical_no = yes` by hand for these).

Carried-over journals are used exactly as they are in the Pilot 2 file. Low-confidence `no` classifications are kept and reported in the log.

---

## Step 1: Find the journals to classify (Step 1d, automatic)

The script compares the current journal list (level 1–2, online ISSN, after the title keyword filter) with the Pilot 2 file and writes:

- `2025journals_vs_2023_comparison.csv`: every journal, marked as in both lists, new, or dropped (with the reason).
- `2025journals_to_classify.csv`: the new journals, in the same columns as the Pilot 2 file. This is the file given to the LLM.
- `2025journals_llm_classified_draft.csv`: the carried-over journals with their Pilot 2 classification.

Set `JOURNAL_RECLASSIFY_ALL = TRUE` in the script's configuration to classify every journal again instead of only the new ones.

---

## Step 2: LLM classification and manual review (Step 1e, manual)

### LLM prompt

Submit the prompt below to Claude (or another LLM) with `2025journals_to_classify.csv` attached. It is the same prompt as in Pilot 2.

```
You are evaluating academic psychology journals.

Task:
For each journal in the attached CSV, assess whether it primarily publishes
original empirical research articles (quantitative or qualitative data),
versus primarily editorials, commentaries, reviews, or theoretical pieces.

Add two new columns:
1. publishes_original_research
   yes   = regularly publishes standard empirical research articles
   mixed = publishes some empirical research but also substantial non-empirical content
   no    = primarily non-empirical (commentary / review / theoretical / editorial)

2. confidence
   high / medium / low

Instructions:
- Base assessments on general knowledge of each journal's publication model.
- Do not fabricate specific policies.
- If uncertain, use confidence = low.
- Return the full CSV with the two new columns added.
- Output ONLY valid CSV — no commentary, no markdown code fences.
```

### Known parsing issues

When working with LLM-generated CSVs, watch for:

- **Unquoted titles containing commas**: titles with commas (e.g. "Aging, Neuropsychology and Cognition") cause extra fields if the LLM does not quote them. Detect these and rejoin the title fragments.
- **Merged fields**: adjacent fields can get concatenated (e.g. `2yes` instead of `2` and `yes`). Check for rows with fewer fields than expected.
- **Windows line endings**: `.txt` output from some LLMs uses `\r\n`. R handles this, but check it if parsing fails.

### Manual review

Review journals that were:

- classified `no` with `low` confidence,
- classified `mixed` or `yes` but known to be non-empirical,
- classified differently by different LLMs, if more than one was used.

For any journal confirmed as non-empirical, set `manual_review = yes` and `final_empirical_no = yes`.

### Finalising the file

Append the classified rows to `2025journals_llm_classified_draft.csv`, add `classification_source`, and save the result as `2025journals_llm_classified_final.csv` in the run folder. Then run the script again: Step 1f checks that every journal on the current list is classified exactly once and stops if any are missing or duplicated.

---

## Summary for Study 1

| | Journals |
|---|---|
| In the Pilot 2 file | 525 |
| Dropped from the current list | 3 |
| Carried over from Pilot 2 | 522 |
| New, classified for Study 1 | 11 |
| **In `2025journals_llm_classified_final.csv`** | **533** |

Dropped: Journal of Cognitive and Behavioral Psychotherapies (JCBP), Journal of College Student Psychotherapy, Psych.

**Exclusions.** The 12 Pilot 2 exclusions are carried over (6 LLM `no` with medium/high confidence, 6 manual review): Behavior and Philosophy, Behavioral and Brain Sciences, Janus Head, JUNG (e-Journal of the Jungian Society), KronoScope, Mind and Matter, Minnesota Symposia on Child Psychology, Nebraska Symposium on Motivation, New Ideas in Psychology, Psychoanalytic Dialogues, Psychoanalytic Inquiry, The Psychologist.

Of the 11 new journals, 2 were classified `no` with medium confidence: *Psychological Methods* and *The Quantitative Methods for Psychology*. Their `final_empirical_no` is blank in the file, so the script's rule excludes them in Step 1f, giving **14 excluded journals** in total. No new journal was added through manual review.
