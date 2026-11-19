"""
Check which labels the MultiTagger checkpoint actually has, and in what order.

Run from the MultiTagger-v2-main folder (the one containing AMIA/ and
best_verbalize_478k/, set up as in the README):
    python check_multitagger_labels.py

Prints:
  1. the number of outputs of the trained model (from the checkpoint)
  2. the labels in best_thresholds.pkl, in their stored order
  3. anything in the checkpoint that looks like a label list
  4. a side-by-side comparison with the 59-label order the R scripts assume

Mary Beth Neff, University of Oslo, 2026-11-19.
LLM transparency: written with Claude (Anthropic, Opus 5.5).
"""
import argparse
import pickle

import torch

CHECKPOINT = "best_verbalize_478k/best_f1.mdl"        # set up as in the README
THRESHOLDS = "best_verbalize_478k/best_thresholds.pkl"

# Order assumed by pilot2_db_multitagger-comparison.R and the curation script
R_LABEL_ORDER = [
    "autobiography", "bibliography", "biography", "case_control_study",
    "case_reports", "clinical_conference", "clinical_studies_as_topic",
    "clinical_study", "clinical_trial", "clinical_trial_protocol",
    "cohort_study", "comment", "congress", "consensus_development_conference",
    "cross_cultural_comparison", "cross_over_study", "cross_sectional_study",
    "double_blind_method", "editorial", "evaluation_studies",
    "evaluation_studies_as_topic", "expression_of_concern", "feasibility_studies",
    "focus_groups", "follow_up_studies", "genome_wide_association_study",
    "historical_article", "human_experimentation", "interview",
    "interviews_as_topic", "lectures", "legal_cases", "letter",
    "longitudinal_studies", "matched_pair_analysis", "meta_analysis",
    "multicenter_study", "news", "newspaper_article", "personal_narratives",
    "portaits", "practice_guideline", "predictive_value_of_tests",
    "prospective_studies", "published_erratum", "random_allocation",
    "randomized_controlled_trial", "reproducibility_of_results",
    "retraction_of_publication", "retrospective_studies", "review",
    "scientific_integrity_review", "systematic_review", "systematic_review_as_topic",
    "twin_study", "validation_studies", "veterinary_clinical_trial",
    "veterinary_observational_study", "veterinary_randomized_controlled_trial",
]

# 1. Checkpoint: number of model outputs and any stored label list
torch.serialization.add_safe_globals([argparse.Namespace])
state = torch.load(CHECKPOINT, map_location="cpu", weights_only=False)
print("Checkpoint keys:", list(state.keys()) if isinstance(state, dict) else type(state))

weights = state["model"]
last_name, last_w = [(k, v) for k, v in weights.items() if k.endswith("weight")][-1]
print(f"\n1. Final layer: {last_name}, shape {tuple(last_w.shape)}")
print(f"   -> the model has {last_w.shape[0]} outputs (labels)")

# 3. Anything else stored with the checkpoint (e.g. training arguments)
for k, v in state.items():
    if k == "model":
        continue
    text = str(vars(v)) if isinstance(v, argparse.Namespace) else str(v)
    print(f"\n3. checkpoint['{k}'] (first 1500 characters):\n   {text[:1500]}")

# 2. Thresholds file
with open(THRESHOLDS, "rb") as f:
    t = pickle.load(f)
print(f"\n2. best_thresholds.pkl: {type(t).__name__} with {len(t)} entries")
keys = list(t.keys()) if isinstance(t, dict) else list(range(len(t)))
for i, k in enumerate(keys):
    print(f"   {i:2d}  {k}")

# 4. Side by side with the R order
print("\n4. Position | thresholds file | R scripts")
for i in range(max(len(keys), len(R_LABEL_ORDER))):
    a = keys[i] if i < len(keys) else "-"
    b = R_LABEL_ORDER[i] if i < len(R_LABEL_ORDER) else "-"
    print(f"   {i:2d}  {str(a):42s} {b}")
