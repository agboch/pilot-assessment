"""
run_multitagger_pilot2db.py  -  Pilot 2 database (RECONSTRUCTION)

This is the earlier version of our MultiTagger script, reconstructed for the
Pilot 2 predictions. The file found in September 2026 listed 61 label names
(NUM_LABELS = 61) and could not load the 59-label model. The Pilot 2 run must
have used an edited copy, which was not kept. This reconstruction makes the
minimum edits that reproduce the stored Pilot 2 output exactly:
  - 'meta-analysis_as_topic' and 'practice_guidelines_as_topic' removed
    from label_order, and NUM_LABELS set to 59
  - input/output file names set to the Pilot 2 files
All other code is unchanged.

KNOWN ISSUE (kept on purpose, so the Pilot 2 output can be reproduced):
the cut-offs are matched to the wrong labels for labels 11-58 (47 of 59).
The probabilities are correct. Do not use this script for new runs; use
run_multitagger_study1db.py, which reads the labels and cut-offs from the
model. See the README, "Earlier script version".
"""
import torch
import torch.nn as nn
import pandas as pd
from transformers import AutoTokenizer
import numpy as np
import pickle
import os
from AMIA.models.bert_model import BertForMultiLabelClassification

# -----------------------------
# CONFIGURATION
# -----------------------------
BERT_MODEL_NAME = "microsoft/BiomedNLP-PubMedBERT-base-uncased-abstract-fulltext"
MAX_LEN = 512
NUM_LABELS = 59  # reconstruction: was 61 in the file found in September 2026

# -----------------------------
# LOAD THRESHOLDS
# -----------------------------
from difflib import get_close_matches

def load_thresholds(threshold_file, label_order):
    with open(threshold_file, "rb") as f:
        t = pickle.load(f)

    thresholds = []
    for label in label_order:
        if label in t:
            thresholds.append(t[label])
        else:
            # find closest match in threshold dict
            match = get_close_matches(label, t.keys(), n=1, cutoff=0.6)
            if match:
                print(f"Mapping '{label}' → '{match[0]}'")
                thresholds.append(t[match[0]])
            else:
                raise KeyError(f"No threshold found for label '{label}'")

    # ensure correct length
    thresholds = np.array(thresholds)
    if len(thresholds) != len(label_order):
        raise ValueError(f"Threshold count mismatch: expected {len(label_order)}, got {len(thresholds)}")

    return thresholds


# -----------------------------
# LABEL ORDER (59 labels; reconstruction - see header)
# -----------------------------
label_order = [
    'autobiography', 'bibliography', 'biography', 'case-control_studies',
    'case_reports', 'clinical_conference', 'clinical_studies_as_topic',
    'clinical_study', 'clinical_trial', 'clinical_trial_protocol',
    'clinical_trials_as_topic', 'cohort_studies', 'comment', 'congress',
    'consensus_development_conference', 'cross-cultural_comparison',
    'cross-over_studies', 'cross-sectional_studies', 'double-blind_method',
    'editorial', 'evaluation_studies_as_topic', 'evaluation_study',
    'expression_of_concern', 'feasibility_studies', 'focus_groups',
    'follow-up_studies', 'genome-wide_association_study', 'historical_article',
    'human_experimentation', 'interview', 'interviews_as_topic', 'lecture',
    'legal_case', 'letter', 'longitudinal_studies', 'matched-pair_analysis',
    'meta-analysis', 'multicenter_study', 'news',
    'newspaper_article', 'personal_narrative', 'portrait', 'practice_guideline',
    'predictive_value_of_tests', 'prospective_studies',
    'published_erratum', 'random_allocation', 'randomized_controlled_trial_humans',
    'reproducibility_of_results', 'retraction_of_publication', 'retrospective_studies',
    'review', 'scientific_integrity_review', 'systematic_review',
    'systematic_reviews_as_topic', 'twin_study', 'validation_study',
    'veterinary_clinical_trial', 'veterinary_randomized_controlled_trial'
]

# -----------------------------
# LOAD MODEL
# -----------------------------
class SimpleConfig:
    def __init__(self, bert_model_name, bert_dropout):
        self.bert_model_name = bert_model_name
        self.bert_dropout = bert_dropout

def load_model(checkpoint_dir):
    config = SimpleConfig(BERT_MODEL_NAME, bert_dropout=0.1)
    model = BertForMultiLabelClassification(config, num_labels=NUM_LABELS)

    checkpoint_path = os.path.join(checkpoint_dir, "best_f1.mdl")
    import argparse
    torch.serialization.add_safe_globals([argparse.Namespace])
    state = torch.load(checkpoint_path, map_location="cpu", weights_only=False)

    model.load_state_dict(state["model"])
    model.eval()
    return model

# -----------------------------
# TOKENIZATION
# -----------------------------
def tokenize_batch(tokenizer, texts):
    enc = tokenizer(
        texts,
        padding=True,
        truncation=True,
        max_length=MAX_LEN,
        return_tensors="pt"
    )
    return enc["input_ids"], enc["attention_mask"]

# -----------------------------
# INFERENCE
# -----------------------------
def predict(model, tokenizer, df, text_column, thresholds):
    all_probs = []
    all_preds = []

    for text in df[text_column].fillna(""):
        ids, mask = tokenize_batch(tokenizer, [text])
        batch = type("Batch", (), {})()
        batch.text_ids = ids
        batch.attention_mask_text = mask

        with torch.no_grad():
            logits = model(batch)
            probs = torch.sigmoid(logits).numpy()[0]

        preds = (probs >= thresholds).astype(int)

        all_probs.append(probs)
        all_preds.append(preds)

    df["probabilities"] = all_probs
    df["predictions"] = all_preds
    return df

# -----------------------------
# MAIN
# -----------------------------
def run_inference(input_csv, text_column, checkpoint_dir, threshold_file, output_csv):
    tokenizer = AutoTokenizer.from_pretrained(BERT_MODEL_NAME)
    thresholds = load_thresholds(threshold_file, label_order)
    model = load_model(checkpoint_dir)

    df = pd.read_csv(input_csv)
    df = predict(model, tokenizer, df, text_column, thresholds)

    df.to_csv(output_csv, index=False)
    print(f"Saved predictions to {output_csv}")

if __name__ == "__main__":
    run_inference(
        input_csv="articles_abstracts_for_classification.csv",
        text_column="abstract",                           # already correct
        checkpoint_dir="AMIA/models/best_model",
        threshold_file="AMIA/models/best_model/best_thresholds.pkl",
        output_csv="multitagger_predictions.csv"
    )