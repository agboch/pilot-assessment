# Journal Classification Curation README

This document describes how `journals_llm_classified_final.csv` was created and how to recreate or update it. This file is required by Step 1c of the Pilot 2 curation script, `pilot2_db_curation_v5_replicable.R`; the script stops at Step 1c if it is missing.

---

## Overview

The goal of this process is to identify psychology journals that do **not** primarily publish original empirical research, so they can be excluded from downstream OpenAlex queries. The final classification file combines LLM-assisted classification with a manual review layer.

---

## File: `journals_llm_classified_final.csv`

### Column reference

| Column | Description |
|---|---|
| `journal_id` | Internal journal identifier |
| `Online ISSN` | Journal ISSN (used as the join key in the R script) |
| `Original Title` | Journal title as listed in the source database |
| `International Title` | Standardised international title |
| `Level 2023` | Journal level rating from the source database |
| `publishes_original_research` | LLM classification: `yes`, `mixed`, or `no` |
| `confidence` | LLM confidence: `high`, `medium`, or `low` |
| `manual_review` | `yes` if flagged through manual review; blank otherwise |
| `final_empirical_no` | `yes` if the journal should be excluded from the empirical dataset (see logic below) |

### Exclusion logic for `final_empirical_no`

A journal receives `final_empirical_no = yes` if **either** of the following is true:

- The LLM classified it as `publishes_original_research = no` **and** `confidence` is `medium` or `high`
- `manual_review = yes` (regardless of LLM classification)

Low-confidence `no` classifications (`confidence = low`) are **not** excluded automatically — they are flagged in the R script console for human review.

---

## Step 1: LLM Classification

### Input file

`journals_for_llm_review.csv` — the 525 journals that remain after Step 1b of the curation script (`filtered_psych_db.csv`), reduced to the columns `journal_id`, `Online ISSN`, `Original Title`, `International Title` and `Level 2023`. The curation script does not write this file itself; make it from `filtered_psych_db.csv` by keeping those five columns.

### LLM prompt

Copy the prompt below and submit it to Claude (or another LLM) along with `journals_for_llm_review.csv` as an attachment:

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

- **Unquoted titles containing commas** — journal titles with commas (e.g., "Aging, Neuropsychology and Cognition") will cause extra fields if the LLM does not quote them. These must be detected and the title fragments rejoined.
- **Merged fields** — occasionally adjacent fields get concatenated (e.g., `2yes` instead of `2` and `yes`). Check for rows with fewer than the expected 7 fields.
- **Windows line endings** — `.txt` output from some LLMs may use `\r\n`. R handles this but it is worth checking if parsing issues arise.

In the original classification these issues were fixed with a small Python script (not included); any CSV repair that rejoins split titles and splits merged fields will do.

### Running classification with multiple LLMs

To compare classifications across models (recommended for quality control):

1. Run the prompt with each LLM and save outputs as separate files (e.g., `journals_llm_classified_gpt.csv`, `journals_llm_classified_claude.csv`).
2. Compare the `publishes_original_research` column across files. Journals where models disagree warrant manual review.
3. Agreement rate in this project was approximately 87% across GPT-4 and Claude Sonnet. Disagreements were concentrated in psychoanalytic and theoretical journals.

---

## Step 2: Manual Review

After LLM classification, review journals that were:

- Classified `no` with `low` confidence (LLM was uncertain)
- Classified `mixed` or `yes` but are known to be non-empirical based on domain knowledge
- Flagged as disagreements between multiple LLMs

For any journal confirmed as non-empirical through manual review, set `manual_review = yes` in the final file. The `final_empirical_no` column should then be updated accordingly (see logic above).

### Journals added via manual review in this project

The following journals were added to `manual_review = yes` based on domain knowledge, as the LLM either missed them or classified them as `mixed`/`yes`:

| Journal | Reason |
|---|---|
| Behavioral and Brain Sciences | Strictly a target article + peer commentary journal; no original empirical research |
| New Ideas in Psychology | Focuses on theoretical and conceptual psychology rather than primary empirical research |
| Janus Head | Multidisciplinary, emphasises phenomenology and philosophical dialogue; not standard empirical research |
| Mind and Matter | Philosophical and interdisciplinary journal on mind–body issues; largely conceptual/theoretical |
| Psychoanalytic Dialogues | Psychoanalytic theory, clinical insights, and dialogue; largely qualitative/case-oriented and conceptual |
| Psychoanalytic Inquiry | Theoretical and interpretive psychoanalytic scholarship; largely conceptual and clinical |

---

## Step 3: Finalising the File

Once LLM classification and manual review are complete, compute the `final_empirical_no` column using the logic described above. This can be done in R or Python.

**In R:**

```r
journals_llm_classified_final <- journals_llm_classified %>%
  mutate(
    final_empirical_no = case_when(
      tolower(manual_review) == "yes"                                        ~ "yes",
      tolower(publishes_original_research) == "no" &
        tolower(confidence) %in% c("medium", "high")                        ~ "yes",
      TRUE                                                                   ~ ""
    )
  )

write_csv(journals_llm_classified_final, "journals_llm_classified_final.csv")
```

**In Python:**

```python
import pandas as pd

df = pd.read_csv("journals_llm_classified.csv")

df["final_empirical_no"] = ""
df.loc[
    (df["publishes_original_research"].str.lower() == "no") &
    (df["confidence"].str.lower().isin(["medium", "high"])),
    "final_empirical_no"
] = "yes"
df.loc[df["manual_review"].str.lower() == "yes", "final_empirical_no"] = "yes"

df.to_csv("journals_llm_classified_final.csv", index=False)
```

Save the completed file as `journals_llm_classified_final.csv` in the curation script's working folder (`output_directory`) before running Step 1c.

---

## Summary of exclusions in this project

| Source | Count |
|---|---|
| LLM classified `no` (medium/high confidence) | 6 |
| Manual review additions | 6 |
| **Total excluded (`final_empirical_no = yes`)** | **12** |

Journals excluded: Behavior and Philosophy, Behavioral and Brain Sciences, Janus Head, JUNG (e-Journal of the Jungian Society), KronoScope, Mind and Matter, Minnesota Symposia on Child Psychology, Nebraska Symposium on Motivation, New Ideas in Psychology, Psychoanalytic Dialogues, Psychoanalytic Inquiry, The Psychologist.
